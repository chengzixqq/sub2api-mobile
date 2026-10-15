import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private actor CostSnapshotTransport: HTTPTransport {
    let stats: String
    private var seen = [URLRequest]()
    init(stats: String) { self.stats = stats }
    func data(for request: URLRequest) async throws -> HTTPResponse {
        seen.append(request)
        return HTTPResponse(statusCode: 200, data: Data("{\"code\":0,\"data\":{\"stats\":\(stats)}}".utf8))
    }
    func stream(for request: URLRequest) async throws -> HTTPStreamResponse { throw URLError(.unsupportedURL) }
    func requests() -> [URLRequest] { seen }
}

private let costStats = #"{"today_requests":12,"today_tokens":1234567,"today_cost":"99.99","today_actual_cost":"12.34567891","today_account_cost":"4.56789123","total_users":8,"total_accounts":3,"error_accounts":1,"rpm":1234,"tpm":987654}"#

@Test func overviewCostSnapshotUsesOnlyStatsAndPreservesBothMoneyValues() async throws {
    let transport = CostSnapshotTransport(stats: costStats)
    let server = ServerProfile(name: "Fixture", baseURL: URL(string: "https://costs.example.invalid")!, authentication: .adminKey)
    let client = APIClient(server: server, credential: .adminKey("fixture"), transport: transport)
    let snapshot = try await client.dashboardCostSnapshot()
    #expect(snapshot.actual == Decimal(string: "12.34567891"))
    #expect(snapshot.account == Decimal(string: "4.56789123"))
    let requests = await transport.requests()
    let request = try #require(requests.first)
    #expect(requests.count == 1)
    #expect(request.url?.path == "/api/v1/admin/dashboard/snapshot-v2")
    #expect(request.timeoutInterval == 45)
    let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(query["include_stats"] == "true")
    for key in ["include_trend", "include_model_stats", "include_group_stats", "include_users_trend"] {
        #expect(query[key] == "false")
    }
    #expect(query["start_date"] == query["end_date"])
}

@Test func overviewCostSnapshotNeverSubstitutesStandardCostForMissingAccountCost() async throws {
    var fields = try JSONSerialization.jsonObject(with: Data(costStats.utf8)) as! [String: Any]
    fields.removeValue(forKey: "today_account_cost")
    let incomplete = try JSONSerialization.data(withJSONObject: fields)
    let transport = CostSnapshotTransport(stats: String(decoding: incomplete, as: UTF8.self))
    let server = ServerProfile(name: "Fixture", baseURL: URL(string: "https://costs.example.invalid")!, authentication: .adminKey)
    let client = APIClient(server: server, credential: .adminKey("fixture"), transport: transport)
    await #expect(throws: APIError.self) { try await client.dashboardCostSnapshot() }
}
