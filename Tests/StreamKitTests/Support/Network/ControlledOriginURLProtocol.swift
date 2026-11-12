import Foundation

enum ControlledOriginResponse: Sendable {
    case body(statusCode: Int, headers: [String: String], data: Data)
    case redirect(URL)
    case hold
}

final class ControlledOrigin: @unchecked Sendable {
    let host: String

    private let lock = NSLock()
    private let responses: [String: ControlledOriginResponse]
    private var requests: [URLRequest] = []
    private var stoppedPaths: [String] = []
    private var completedPaths: [String] = []

    init(host: String, responses: [String: ControlledOriginResponse]) {
        self.host = host
        self.responses = responses
    }

    func register() {
        ControlledOriginURLProtocol.register(self)
    }

    func unregister() {
        ControlledOriginURLProtocol.unregister(host: host)
    }

    func response(for request: URLRequest) -> ControlledOriginResponse {
        lock.lock()
        defer { lock.unlock() }
        return responses[request.url?.path ?? ""] ?? .body(
            statusCode: 404,
            headers: ["Content-Type": "text/plain"],
            data: Data()
        )
    }

    func record(_ request: URLRequest) {
        lock.lock()
        requests.append(request)
        lock.unlock()
    }

    func recordStop(path: String) {
        lock.lock()
        stoppedPaths.append(path)
        lock.unlock()
    }

    func recordCompletion(path: String) {
        lock.lock()
        completedPaths.append(path)
        lock.unlock()
    }

    func waitForRequest(path: String) async throws -> URLRequest {
        for _ in 0..<300 {
            let request = recordedRequest(path: path)
            if let request { return request }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ControlledOriginTimeout.request(path)
    }

    func waitForStop(path: String) async throws {
        for _ in 0..<300 {
            if hasStopped(path: path) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ControlledOriginTimeout.stop(path)
    }

    func waitForCompletion(path: String) async throws {
        for _ in 0..<300 {
            if hasCompleted(path: path) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ControlledOriginTimeout.completion(path)
    }

    func hasRequest(path: String) -> Bool {
        recordedRequest(path: path) != nil
    }

    private func recordedRequest(path: String) -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.first { $0.url?.path == path }
    }

    private func hasStopped(path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stoppedPaths.contains(path)
    }

    private func hasCompleted(path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return completedPaths.contains(path)
    }
}

private enum ControlledOriginTimeout: Error {
    case request(String)
    case stop(String)
    case completion(String)
}

final class ControlledOriginURLProtocol: URLProtocol {
    private static let registry = ControlledOriginRegistry()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".streamkit.test") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let origin = Self.registry.origin(for: url.host ?? "")
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }

        origin.record(request)

        switch origin.response(for: request) {
        case let .body(statusCode, headers, data):
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
            origin.recordCompletion(path: url.path)

        case let .redirect(destination):
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": destination.absoluteString]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            var redirectedRequest = URLRequest(url: destination)
            redirectedRequest.httpMethod = request.httpMethod
            redirectedRequest.allHTTPHeaderFields = request.allHTTPHeaderFields
            client?.urlProtocol(
                self,
                wasRedirectedTo: redirectedRequest,
                redirectResponse: response
            )

        case .hold:
            break
        }
    }

    override func stopLoading() {
        guard let url = request.url,
              let origin = Self.registry.origin(for: url.host ?? "")
        else { return }
        origin.recordStop(path: url.path)
    }

    fileprivate static func register(_ origin: ControlledOrigin) {
        registry.register(origin)
    }

    fileprivate static func unregister(host: String) {
        registry.unregister(host: host)
    }
}

private final class ControlledOriginRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var origins: [String: ControlledOrigin] = [:]

    func register(_ origin: ControlledOrigin) {
        lock.lock()
        origins[origin.host] = origin
        lock.unlock()
    }

    func unregister(host: String) {
        lock.lock()
        origins.removeValue(forKey: host)
        lock.unlock()
    }

    func origin(for host: String) -> ControlledOrigin? {
        lock.lock()
        defer { lock.unlock() }
        return origins[host]
    }
}
