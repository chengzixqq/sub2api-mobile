import Foundation
import Network
import Sub2Core

/// 20 §7.4-6: while Safari shows a link whose callback is this phone's loopback address, the App answers that address itself, so
/// the callback comes back without copying. Loopback connections only (127.0.0.1 and ::1 alike); the first callback stops it.
/// A port another app holds, or any other failure, leaves the paste field (`onFailure`). The caller decides whether to listen:
/// new accounts do, 重新授权 pastes (20 §6.3). Neither the address nor the code is logged or echoed.
@MainActor
final class OAuthCallbackListener {
    enum State: Equatable { case idle, listening, failed }
    private(set) var state: State = .idle
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var onCallback: (@MainActor (URL) -> Void)?
    private var onFailure: (@MainActor () -> Void)?

    func start(_ endpoint: OAuthLoopbackEndpoint, onCallback: @escaping @MainActor (URL) -> Void, onFailure: @escaping @MainActor () -> Void) {
        stop()
        self.onCallback = onCallback
        self.onFailure = onFailure
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: endpoint.port), let listener = try? NWListener(using: parameters, on: port) else {
            fail()
            return
        }
        self.listener = listener
        // Everything runs on the main queue, so the handlers are already on the main actor.
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.listenerChanged(state) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection, endpoint: endpoint) }
        }
        state = .listening
        listener.start(queue: .main)
    }

    /// Safari closed, the view left or the link changed; safe to call again.
    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections = []
        onCallback = nil
        onFailure = nil
        if state == .listening { state = .idle }
    }

    private func listenerChanged(_ newState: NWListener.State) {
        switch newState {
        case .failed, .waiting: fail()
        default: break
        }
    }
    private func fail() {
        let handler = onFailure
        stop()
        state = .failed
        handler?()
    }

    private func accept(_ connection: NWConnection, endpoint: OAuthLoopbackEndpoint) {
        guard Self.isLoopback(connection.endpoint) else { connection.cancel(); return }
        connections.append(connection)
        connection.start(queue: .main)
        receive(connection, buffer: Data(), endpoint: endpoint)
    }
    private func receive(_ connection: NWConnection, buffer: Data, endpoint: OAuthLoopbackEndpoint) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: OAuthLoopback.maxHeadBytes) { [weak self] data, _, isComplete, error in
            let read = buffer + (data ?? Data()), ended = isComplete || error != nil
            MainActor.assumeIsolated { self?.received(connection, buffer: read, ended: ended, endpoint: endpoint) }
        }
    }
    private func received(_ connection: NWConnection, buffer: Data, ended: Bool, endpoint: OAuthLoopbackEndpoint) {
        let head = OAuthLoopback.parse(head: buffer, endpoint: endpoint)
        switch head {
        case .incomplete where !ended: receive(connection, buffer: buffer, endpoint: endpoint)
        case .callback(let url):
            reply(connection, head)
            finish(url)
        default: reply(connection, .rejected)
        }
    }
    private func reply(_ connection: NWConnection, _ head: OAuthLoopback.Head) {
        connection.send(content: OAuthLoopback.response(for: head), contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }
    /// The page goes out on its own connection; the listener stops at once.
    private func finish(_ url: URL) {
        let handler = onCallback
        listener?.cancel()
        listener = nil
        onCallback = nil
        onFailure = nil
        state = .idle
        handler?(url)
    }

    private static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return address.isLoopback
        case .ipv6(let address): return address.isLoopback || address.asIPv4?.isLoopback == true
        case .name(let name, _): return name == "localhost"
        @unknown default: return false
        }
    }
}
