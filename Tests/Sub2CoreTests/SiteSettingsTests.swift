import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func settingsClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: stubTokens(), deviceID: stubDeviceID, transport: transport, requestClock: .immediate)
}

/// 00 §1.2: only the native binding mode is read from the (large) system settings.
@Test func sessionBindingNativeModeReadsOnlyThatField() async throws {
    let transport = ScriptedTransport { _ in
        okReply(#"{"site_name":"主站","session_binding_native_mode":"device","smtp_password_configured":true,"default_balance":5}"#)
    }
    #expect(try await settingsClient(transport).sessionBindingNativeMode() == "device")
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/v1/admin/settings")
    #expect(request.httpBody == nil)
    #expect(sentHeader(request, "Authorization") == "Bearer old-access")
}

@Test func sessionBindingNativeModeIsNilWhenTheServerLeavesItOut() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"site_name":"主站"}"#) }
    #expect(try await settingsClient(transport).sessionBindingNativeMode() == nil)
}

@Test func sessionBindingNativeModeKeepsAnEmptyMode() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"session_binding_native_mode":""}"#) }
    #expect(try await settingsClient(transport).sessionBindingNativeMode() == "")
}
