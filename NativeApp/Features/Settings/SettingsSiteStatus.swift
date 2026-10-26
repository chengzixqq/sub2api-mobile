import Foundation
import Observation
import Sub2Core

/// 60 §3.6: read each time the page appears, coming back from 登录设备 or the token page included, so a revocation there
/// shows here; never polled. A failure only leaves the number out; a server without `auth/sessions` (non-JSON 404) hides
/// 登录设备 for the rest of the session. The binding mode is read once per session, only for the 00 §1.2 hint. A result for
/// an older session is dropped.
@MainActor @Observable
final class SettingsSiteStatus {
    private(set) var sessionsSupported = true
    private(set) var sessionCount: Int?
    private(set) var tokenCount: Int?
    private(set) var bindingNativeMode: String?
    @ObservationIgnored private var loadedGeneration: UUID?

    func load(model: AppModel, context: SessionContext) async {
        let isFirstRead = loadedGeneration != context.generation
        if model.isUITesting {
            apply(sessions: (true, DemoData.authSessionFixtureCount(generation: context.generation)), tokens: DemoData.accessTokenCount, mode: nil,
                  generation: context.generation)
            return
        }
        let site = context.site, client = context.client
        let supported = isFirstRead || sessionsSupported
        let readsSessions = supported && SettingsPresentation.sessionsRow(authMethod: site.authMethod, fallback: site.authenticationKind,
                                                                          sessionsSupported: true) == .available
        // admin/access-tokens and admin/settings answer 423 until compliance is accepted (as in SiteSession.currentTokenScope).
        let readsTokens = SettingsPresentation.showsAccessTokens(site.me) && site.me.compliance.required != true
        let readsMode = isFirstRead && SettingsPresentation.readsBindingMode(me: site.me, authMethod: site.authMethod)
        async let sessions = Self.sessions(client, reads: readsSessions)
        async let tokens = Self.activeTokens(client, reads: readsTokens)
        async let mode = Self.bindingMode(client, reads: readsMode)
        let results = await (sessions, tokens, mode)
        guard context.generation == model.sessionGeneration, !Task.isCancelled else { return }
        apply(sessions: supported ? results.0 : (supported: false, count: nil), tokens: results.1, mode: isFirstRead ? results.2 : bindingNativeMode,
              generation: context.generation)
    }

    private func apply(sessions: (supported: Bool, count: Int?), tokens: Int?, mode: String?, generation: UUID) {
        sessionsSupported = sessions.supported; sessionCount = sessions.count
        tokenCount = tokens; bindingNativeMode = mode
        loadedGeneration = generation
    }

    private nonisolated static func sessions(_ client: APIClient, reads: Bool) async -> (supported: Bool, count: Int?) {
        guard reads else { return (true, nil) }
        do { return (true, try await client.sessions().count) }
        catch let error as APIError where error.kind == .unsupported { return (false, nil) }
        catch { return (true, nil) }
    }
    private nonisolated static func activeTokens(_ client: APIClient, reads: Bool) async -> Int? {
        guard reads, let tokens = try? await client.accessTokens() else { return nil }
        return SettingsPresentation.activeTokenCount(tokens, now: Date())
    }
    private nonisolated static func bindingMode(_ client: APIClient, reads: Bool) async -> String? {
        guard reads else { return nil }
        return try? await client.sessionBindingNativeMode()
    }
}
