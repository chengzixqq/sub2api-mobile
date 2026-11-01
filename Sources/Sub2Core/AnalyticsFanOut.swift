import Foundation

/// 40 §0.6 降级扇出: one request per input, at most four at a time, answers in input order. A failure is that input's alone; one
/// that `stopsAfter` matches (a 429) sends nothing more, while the requests already out finish. Only the caller's cancellation
/// throws. The old server's profit segments use `map` (S4-13b), the request-type fallback `results` (S4-17b).
public enum AnalyticsFanOut {
    public static let maxConcurrent = 4

    /// Each input's result in order; nil for an input never sent after a stopping error.
    public static func results<Input: Sendable, Output: Sendable>(
        _ inputs: [Input], limit: Int = maxConcurrent, stopsAfter shouldStop: @escaping @Sendable (any Error) -> Bool = { _ in false },
        _ operation: @escaping @Sendable (Input) async throws -> Output
    ) async throws -> [Result<Output, any Error>?] {
        let results = await withTaskGroup(of: (Int, Result<Output, any Error>).self, returning: [Result<Output, any Error>?].self) { group in
            var results = [Result<Output, any Error>?](repeating: nil, count: inputs.count)
            var sent = 0, stopped = false
            while sent < min(max(limit, 1), inputs.count) {
                let index = sent, input = inputs[index]
                group.addTask { await attempt(index, input, operation) }
                sent += 1
            }
            while let (index, result) = await group.next() {
                results[index] = result
                if case .failure(let error) = result, shouldStop(error) { stopped = true }
                guard !stopped, !Task.isCancelled, sent < inputs.count else { continue }
                let next = sent, input = inputs[next]
                group.addTask { await attempt(next, input, operation) }
                sent += 1
            }
            return results
        }
        try Task.checkCancellation()
        return results
    }

    private static func attempt<Input: Sendable, Output: Sendable>(_ index: Int, _ input: Input,
                                                                   _ operation: @Sendable (Input) async throws -> Output) async
        -> (Int, Result<Output, any Error>) {
        do { return (index, .success(try await operation(input))) } catch { return (index, .failure(error)) }
    }

    /// `results` with failures and inputs never sent both nil.
    public static func map<Input: Sendable, Output: Sendable>(
        _ inputs: [Input], limit: Int = maxConcurrent, stopsAfter shouldStop: @escaping @Sendable (any Error) -> Bool = { _ in false },
        _ operation: @escaping @Sendable (Input) async throws -> Output
    ) async throws -> [Output?] {
        try await results(inputs, limit: limit, stopsAfter: shouldStop, operation).map { try? $0?.get() }
    }
}

extension APIClient {
    /// 40 §1.3: where the trend has no `account_cost` (an old server), each bucket's own `usage/stats` with the query's filter and
    /// zone, four at a time; a 429 sends no more. A segment that failed, was never sent or came back without `total_account_cost`
    /// is left out (its row shows “—”). Only cancellation throws.
    public func profitSegmentCosts(_ query: AnalyticsQuery, buckets: [AnalyticsBucket]) async throws -> ProfitSegmentCosts {
        let costs = try await AnalyticsFanOut.map(buckets, stopsAfter: { ($0 as? APIError)?.statusCode == 429 }) { [self] bucket in
            var segment = query
            segment.start = bucket.start; segment.end = bucket.end
            return try await usageAnalysis(segment).accountCost
        }
        return ProfitSegmentCosts(buckets, costs: costs.map { $0.flatMap { $0 } })
    }
}
