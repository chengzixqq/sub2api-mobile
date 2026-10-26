import Foundation
import Testing
@testable import NativeSessionSupport

// 30 §3.4 X-Request-ID echo: stored per site id, read across the ids of one address (S3-06).

@MainActor @Test func requestIDFlagIsReadAcrossSameAddressAndClearedPerSite() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let flags = SiteFlags(defaults: scratch.defaults)
    let marked = UUID(), sibling = UUID()
    #expect(!flags.requestIDUnreliable(serverID: marked)); #expect(flags.requestIDUsable(sameAddress: [marked, sibling]))
    flags.markRequestIDUnreliable(serverID: marked)
    #expect(flags.requestIDUnreliable(serverID: marked)); #expect(!flags.requestIDUnreliable(serverID: sibling))
    // The proxy belongs to the address, so any marked id of it decides.
    #expect(!flags.requestIDUsable(sameAddress: [marked, sibling])); #expect(flags.requestIDUsable(sameAddress: [sibling]))
    #expect(flags.requestIDUsable(sameAddress: []))
    #expect(SiteFlags(defaults: scratch.defaults).requestIDUnreliable(serverID: marked))
    flags.removeAll(serverID: sibling)
    #expect(flags.requestIDUnreliable(serverID: marked))
    flags.removeAll(serverID: marked)
    #expect(flags.requestIDUsable(sameAddress: [marked, sibling]))
}

@MainActor @Test func requestIDFlagKey() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let id = UUID(uuidString: "5B6C7D8E-9F0A-4B1C-8D2E-3F4A5B6C7D8E")!
    SiteFlags(defaults: scratch.defaults).markRequestIDUnreliable(serverID: id)
    #expect(SiteFlags.requestIDKey(id) == "site.requestIDUnreliable.5B6C7D8E-9F0A-4B1C-8D2E-3F4A5B6C7D8E")
    #expect(scratch.defaults.object(forKey: SiteFlags.requestIDKey(id)) as? Bool == true)
}
