import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// D18: going to the background suspends reads, read retries and streams; the generation (write identity), the refresh
// flight and writes already sent are left alone.

private func suspendClient(_ transport: ScriptedTransport, credential: Credential = .adminKey("fixture-key"), store: (any CredentialStore)? = nil,
                           clock: RequestClock = .immediate) -> APIClient {
    APIClient(server: stubServer(), credential: credential, credentialStore: store, deviceID: stubDeviceID, transport: transport, requestClock: clock)
}

@Test func suspendCancelsInFlightReadsButKeepsWriteIdentity() async throws {
    let started = OpenGate(); let counter = CallCounter()
    let transport = ScriptedTransport { _ in
        if counter.next() == 1 { await started.open(); try await Task.sleep(for: .seconds(60)) }
        return okReply(stubUserJSON)
    }
    let client = suspendClient(transport)
    let identity = await client.userWriteIdentity()
    let read = Task { try await client.user(id: 7) }
    await started.wait()
    let suspendedAt = ContinuousClock.now
    await client.suspend()
    await #expect(throws: CancellationError.self) { try await read.value }
    #expect(ContinuousClock.now - suspendedAt < .seconds(10))
    #expect(await transport.requests.count == 1)
    #expect(await client.userWriteIdentity() == identity)
    // A read started afterwards goes out as usual.
    #expect(try await client.user(id: 7).id == 7)
}

@Test func suspendDropsLateReadWhenTransportIgnoresCancellation() async throws {
    let started = OpenGate(); let release = OpenGate()
    let transport = ScriptedTransport { _ in await started.open(); await release.wait(); return okReply(stubUserJSON) }
    let client = suspendClient(transport)
    let read = Task { try await client.user(id: 7) }
    await started.wait(); await client.suspend(); await release.open()
    await #expect(throws: CancellationError.self) { try await read.value }
}

@Test func suspendLetsWritesAlreadySentFinish() async throws {
    let started = OpenGate(); let release = OpenGate()
    let transport = ScriptedTransport { _ in await started.open(); await release.wait(); return okReply(stubUserJSON) }
    let client = suspendClient(transport)
    let write = Task { try await client.setUserStatus(id: 7, status: "disabled") }
    await started.wait(); await client.suspend(); await release.open()
    #expect(try await write.value.id == 7)
}

@Test func suspendKeepsTheRefreshFlight() async throws {
    let started = OpenGate(); let release = OpenGate(); let store = StubCredentialStore()
    let transport = ScriptedTransport { request in
        guard isRefresh(request) else { return okReply(stubUserJSON) }
        await started.open(); await release.wait()
        return okReply(stubRefreshJSON)
    }
    let client = suspendClient(transport, credential: stubTokens(expiresAt: Date().addingTimeInterval(-1)), store: store)
    let read = Task { try await client.user(id: 7) }
    await started.wait(); await client.suspend(); await release.open()
    _ = try? await read.value
    guard case .tokens(let pair)? = await client.currentCredential() else { Issue.record("Expected a token pair"); return }
    #expect(pair.accessToken == "new-access")
    #expect(await store.values[client.server.id] == .tokens(pair))
}

@Test func suspendStopsReadRetryBackoff() async throws {
    let sleeping = OpenGate()
    let transport = ScriptedTransport(script: [.reply(errorReply(502)), .reply(okReply(stubUserJSON))])
    let clock = RequestClock(sleep: { _ in await sleeping.open(); try await Task.sleep(for: .seconds(60)) }, jitter: { .zero })
    let client = suspendClient(transport, clock: clock)
    let read = Task { try await client.user(id: 7) }
    // If the read never waits, open the gate so the test fails instead of hanging.
    let watcher = Task { _ = try? await read.value; await sleeping.open() }
    await sleeping.wait()
    let started = ContinuousClock.now
    await client.suspend()
    await #expect(throws: CancellationError.self) { try await read.value }
    #expect(ContinuousClock.now - started < .seconds(10))
    _ = await watcher.value
    #expect(await transport.requests.count == 1)
}

@Test func suspendEndsAnOpenAccountTestStream() async throws {
    let (bytes, _) = AsyncThrowingStream<Data, any Error>.makeStream()
    let transport = ScriptedTransport(stream: { _ in
        HTTPStreamResponse(statusCode: 200, headers: ["content-type": "text/event-stream"], bytes: bytes)
    }) { _ in errorReply(500) }
    let client = suspendClient(transport)
    let events = try await client.testAccount(id: 9, model: nil)
    await client.suspend()
    await #expect(throws: CancellationError.self) { for try await _ in events {} }
}
