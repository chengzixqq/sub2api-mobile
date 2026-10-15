import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let data: Data
    public init(statusCode: Int, headers: [String: String] = [:], data: Data) { self.statusCode = statusCode; self.headers = headers; self.data = data }
}
public struct HTTPStreamResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let bytes: AsyncThrowingStream<Data, any Error>
    public let cancel: @Sendable () -> Void
    public init(statusCode: Int, headers: [String: String] = [:], bytes: AsyncThrowingStream<Data, any Error>, cancel: @escaping @Sendable () -> Void = {}) {
        self.statusCode = statusCode; self.headers = headers; self.bytes = bytes; self.cancel = cancel
    }
}
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> HTTPResponse
    func stream(for request: URLRequest) async throws -> HTTPStreamResponse
}

/// Ephemeral sessions never share cookies, cached credentials, or automatic redirects across stations.
public final class URLSessionTransport: HTTPTransport, Sendable {
    private let session: URLSession
    public init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
    }
    public func data(for request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, data.count <= 16 * 1_024 * 1_024 else { throw APIError.invalidResponse }
        return HTTPResponse(statusCode: response.statusCode, headers: Self.headers(response), data: data)
    }
    public func stream(for request: URLRequest) async throws -> HTTPStreamResponse {
        let delegate = StreamingDelegate()
        return try await withTaskCancellationHandler {
            try await delegate.start(request: request, configuration: session.configuration)
        } onCancel: { delegate.cancel() }
    }
    fileprivate static func headers(_ response: HTTPURLResponse) -> [String: String] {
        response.allHeaderFields.reduce(into: [:]) { result, item in
            if let key = item.key as? String, let value = item.value as? String { result[key.lowercased()] = value }
        }
    }
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Delegate callbacks are serialized by URLSession; the lock coordinates task cancellation and startup.
private final class StreamingDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var headerContinuation: CheckedContinuation<HTTPStreamResponse, any Error>?
    private let stream: AsyncThrowingStream<Data, any Error>
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var cancelled = false
    override init() {
        let pair = AsyncThrowingStream<Data, any Error>.makeStream()
        stream = pair.stream; continuation = pair.continuation
        super.init()
        continuation.onTermination = { [weak self] _ in self?.cancel() }
    }
    func start(request: URLRequest, configuration: URLSessionConfiguration) async throws -> HTTPStreamResponse {
        try await withCheckedThrowingContinuation { c in
            let networkTask: URLSessionDataTask? = lock.withLock {
                guard !cancelled else { c.resume(throwing: CancellationError()); return nil }
                headerContinuation = c
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.dataTask(with: request)
                self.session = session; self.task = task
                return task
            }
            networkTask?.resume()
        }
    }
    func cancel() {
        let state = lock.withLock { () -> (URLSessionDataTask?, URLSession?, CheckedContinuation<HTTPStreamResponse, any Error>?) in
            cancelled = true
            let result = (task, session, headerContinuation)
            task = nil; session = nil; headerContinuation = nil
            return result
        }
        state.0?.cancel(); state.1?.invalidateAndCancel(); state.2?.resume(throwing: CancellationError())
        continuation.finish(throwing: CancellationError())
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            let c = lock.withLock { let c = headerContinuation; headerContinuation = nil; return c }
            c?.resume(throwing: APIError.invalidResponse); return
        }
        let c = lock.withLock { let c = headerContinuation; headerContinuation = nil; return c }
        c?.resume(returning: HTTPStreamResponse(statusCode: response.statusCode, headers: URLSessionTransport.headers(response), bytes: stream, cancel: { [self] in cancel() }))
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { continuation.yield(data) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let c = lock.withLock { let c = headerContinuation; headerContinuation = nil; self.task = nil; self.session = nil; return c }
        if let error { c?.resume(throwing: error); continuation.finish(throwing: error) }
        else { c?.resume(throwing: APIError.invalidResponse); continuation.finish() }
        session.finishTasksAndInvalidate()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
