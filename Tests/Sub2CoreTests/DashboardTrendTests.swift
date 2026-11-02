import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

@Test func trendMissingActualSpendStaysUnavailable() throws {
    let inputs = [
        #"{"date":"2026-10-15 08:00","requests":12,"total_tokens":340,"cost":"99.99"}"#,
        #"{"date":"2026-10-15 08:00","requests":12,"total_tokens":340,"cost":"99.99","actual_cost":null}"#
    ]
    for input in inputs {
        let point = try JSONDecoder().decode(TrendPoint.self, from: Data(input.utf8))
        #expect(point.actualCost == nil)
        #expect(point.requests == 12 && point.totalTokens == 340)
    }
    let oldInitializer = TrendPoint(date: "2026-10-15", requests: 1, totalTokens: 2, cost: 99)
    #expect(oldInitializer.actualCost == nil)
}

@Test(arguments: ["0", "0.0000000000000000000000000001", "12345678901234567890.12345678"])
func trendSelectedAmountPreservesDecimalPrecision(raw: String) throws {
    let input = "{\"date\":\"2026-10-15 08:00\",\"requests\":1,\"total_tokens\":2,\"cost\":99.99,\"actual_cost\":\"\(raw)\"}"
    let point = try JSONDecoder().decode(TrendPoint.self, from: Data(input.utf8))
    #expect(point.actualCost == Decimal(string: raw))
}

private actor TrendWireTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> HTTPResponse {
        guard request.url?.path == "/api/v1/admin/dashboard/trend" else { throw URLError(.unsupportedURL) }
        return HTTPResponse(statusCode: 200, data: Data(#"{"code":0,"data":{"trend":[{"date":"2026-10-15 08:00","requests":12,"total_tokens":9876543210,"cost":99.99,"actual_cost":12.34567891}]}}"#.utf8))
    }
    func stream(for request: URLRequest) async throws -> HTTPStreamResponse { throw URLError(.unsupportedURL) }
}

@Test func trendEndpointDeliversActualSpendForTheDefaultMetric() async throws {
    let profile = ServerProfile(name: "Fixture", baseURL: URL(string: "https://trend.example.invalid")!, authentication: .adminKey)
    let client = APIClient(server: profile, credential: .adminKey("fixture"), transport: TrendWireTransport())
    let reply = try await client.dashboardTrend()
    let points = reply.points
    let point = try #require(points.first)
    #expect(points.count == 1)
    // No `query` in the reply: buckets are read in the zone the request carried.
    #expect(reply.timeZone.identifier == TimeZone.current.identifier)
    #expect(point.actualCost == Decimal(string: "12.34567891"))
    #expect(point.totalTokens == 9_876_543_210)
}
