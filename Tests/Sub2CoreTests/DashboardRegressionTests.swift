import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private actor DashboardRegressionTransport: HTTPTransport {
    private var seen: [URLRequest] = []
    func data(for request: URLRequest) async throws -> HTTPResponse {
        seen.append(request)
        guard request.url?.path.hasSuffix("/stats") == true else {
            throw URLError(.timedOut)
        }
        let json = #"{"code":0,"data":{"today_requests":12,"today_tokens":340,"today_cost":"0.12345678","total_users":8,"total_accounts":3,"error_accounts":1,"rpm":2.5,"tpm":22.5}}"#
        return HTTPResponse(statusCode: 200, data: Data(json.utf8))
    }
    func stream(for request: URLRequest) async throws -> HTTPStreamResponse { throw URLError(.unsupportedURL) }
    func requests() -> [URLRequest] { seen }
}

@Test func dashboardRegressionInitialLoadSurvivesDetailTimeouts() async throws {
    let transport = DashboardRegressionTransport()
    let site = ServerProfile(name: "Slow fixture", baseURL: URL(string: "https://slow.example.invalid")!, authentication: .adminKey)
    let client = APIClient(server: site, credential: .adminKey("fixture"), transport: transport)
    let result = try await client.dashboard()
    #expect(result.stats.todayRequests == 12)
    #expect(result.stats.todayCost == Decimal(string: "0.12345678"))
    let requests = await transport.requests()
    #expect(requests.count == 1)
    #expect(requests.first?.timeoutInterval == 90)
    print("DASHBOARD_REGRESSION counters=12 details_requested=\(requests.count - 1) stats_timeout=\(requests.first?.timeoutInterval ?? 0)")
}
