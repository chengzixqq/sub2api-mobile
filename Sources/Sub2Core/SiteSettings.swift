import Foundation

extension APIClient {
    /// 00 §1.2: `session_binding_native_mode` of `GET /api/v1/admin/settings` (strict, device, ua_only or off; the server reads an empty value
    /// as strict). Nothing else of the reply is decoded or kept; nil when the server leaves the field out.
    public func sessionBindingNativeMode() async throws -> String? {
        let reply: SessionBindingSettings = try await request("admin/settings", timeout: RequestTimeout.probe)
        return reply.sessionBindingNativeMode
    }
}

private struct SessionBindingSettings: Decodable, Sendable {
    let sessionBindingNativeMode: String?
    enum CodingKeys: String, CodingKey { case sessionBindingNativeMode = "session_binding_native_mode" }
}
