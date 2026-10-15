import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

@Test func analyticsKeepsDecimalDifferenceAndMissingCostDistinct() throws {
    let data = Data(#"{"total_requests":3,"total_tokens":2000000,"total_actual_cost":"9007199254740993.12","total_account_cost":"9007199254740993.11"}"#.utf8)
    let value = try JSONDecoder().decode(AnalyticsSummary.self, from: data)
    #expect(value.difference == Decimal(string: "0.01"))
    let missing = try JSONDecoder().decode(AnalyticsSummary.self, from: Data(#"{"total_requests":0,"total_tokens":0,"total_actual_cost":0}"#.utf8))
    #expect(missing.accountCost == nil)
    #expect(missing.difference == nil)
}

@Test func analyticsRejectsInvalidRangesIDsAndTimezone() {
    let start = Date(timeIntervalSince1970: 1_792_022_400)
    let invalid = [AnalyticsQuery(start: start, end: start), AnalyticsQuery(start: start, end: start.addingTimeInterval(-1)),
                   AnalyticsQuery(start: start, end: start.addingTimeInterval(368 * 86_400)),
                   AnalyticsQuery(start: start, end: start.addingTimeInterval(60), accountID: -1),
                   AnalyticsQuery(start: start, end: start.addingTimeInterval(60), timeZone: "Invalid/Zone")]
    for query in invalid { #expect(throws: (any Error).self) { try query.queryItems() } }
}

private actor AnalyticsTransport: HTTPTransport {
    private(set) var requests = [URLRequest]()
    func data(for request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        let payload: String
        switch request.url!.lastPathComponent {
        case "stats": payload = #"{"total_requests":0,"total_tokens":0,"total_actual_cost":0,"total_account_cost":0}"#
        case "trend": payload = #"{"trend":null}"#
        case "models": payload = #"{"models":null}"#
        default: payload = #"{"groups":null}"#
        }
        return HTTPResponse(statusCode: 200, data: Data("{\"code\":0,\"data\":\(payload)}".utf8))
    }
    func stream(for request: URLRequest) async throws -> HTTPStreamResponse { throw URLError(.unsupportedURL) }
}

@Test func analysisSectionsUseExactlyTheSameScopeAndExclusiveRange() async throws {
    let transport = AnalyticsTransport()
    let profile = ServerProfile(name: "Fixture", baseURL: URL(string: "https://analysis.example.invalid")!, authentication: .adminKey)
    let client = APIClient(server: profile, credential: .adminKey("fixture"), transport: transport)
    let start = Date(timeIntervalSince1970: 1_792_022_400)
    let query = AnalyticsQuery(start: start, end: start.addingTimeInterval(3600), accountID: 42, groupID: 7, userID: 9, model: " gpt&中文 ", timeZone: "Asia/Shanghai")
    _ = try await client.usageAnalysis(query)
    #expect(try await client.usageAnalysisTrend(query).isEmpty)
    #expect(try await client.usageAnalysisModels(query).isEmpty)
    #expect(try await client.usageAnalysisGroups(query).isEmpty)
    let requests = await transport.requests
    #expect(requests.count == 4)
    for request in requests {
        #expect(request.httpMethod == "GET")
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(items["start_time"] == "2026-10-15T00:00:00Z")
        #expect(items["end_time"] == "2026-10-15T01:00:00Z")
        #expect(items["account_id"] == "42"); #expect(items["group_id"] == "7"); #expect(items["user_id"] == "9")
        #expect(items["model"] == "gpt&中文"); #expect(items["timezone"] == "Asia/Shanghai")
    }
    #expect(query.hourly)
    #expect(!AnalyticsQuery(start: start, end: start.addingTimeInterval(7 * 86400)).hourly)
}
