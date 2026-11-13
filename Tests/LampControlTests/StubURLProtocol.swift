import Foundation
@testable import LampControl

/// Intercepts every request of a session built with `StubURLProtocol.session()`, so client
/// code can be tested without the network. Tests using it must run serially (XCTest does).
final class StubURLProtocol: URLProtocol {
    struct Reply {
        var status: Int = 200
        var body: Data = Data()
        var delay: TimeInterval = 0

        init(status: Int = 200, body: String = "", delay: TimeInterval = 0) {
            self.status = status
            self.body = Data(body.utf8)
            self.delay = delay
        }
    }

    private static let lock = NSLock()
    private static var _handler: ((URLRequest) -> Reply)?
    private static var _requests: [URLRequest] = []

    static var handler: ((URLRequest) -> Reply)? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); defer { lock.unlock() }; _handler = newValue }
    }

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _handler = nil
        _requests = []
    }

    static func session() -> URLSession {
        ServiceSession.make(timeout: 5, protocolClasses: [StubURLProtocol.self])
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self._requests.append(request)
        let handler = Self._handler
        Self.lock.unlock()

        let reply = handler?(request) ?? Reply(status: 500)
        let send = { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !reply.body.isEmpty { client?.urlProtocol(self, didLoad: reply.body) }
            client?.urlProtocolDidFinishLoading(self)
        }
        if reply.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay, execute: send)
        } else {
            send()
        }
    }

    override func stopLoading() {}
}
