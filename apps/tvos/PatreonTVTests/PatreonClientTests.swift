//
//  PatreonClientTests.swift
//  PatreonTVTests
//
//  Exercises the transport layer with a stub URLProtocol: status-code → error
//  mapping, cookie header assembly, Retry-After parsing, and the retry policy.
//

import XCTest
@testable import PatreonTV

// MARK: - Stub URLProtocol

/// Serves canned responses. Each test sets `handler` to inspect the request
/// and return (status, headers, body).
final class StubURLProtocol: URLProtocol {

    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, [String: String], Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (status, headers, body) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Tests

@MainActor
final class PatreonClientTests: XCTestCase {

    private var client: PatreonClient!

    override func setUp() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        // maxAttempts: 1 — no retry sleeps in tests that map status codes.
        client = PatreonClient(session: URLSession(configuration: config), maxAttempts: 1)
    }

    override func tearDown() async throws {
        StubURLProtocol.handler = nil
    }

    func test_success_decodes_current_user_and_caches_id() async throws {
        StubURLProtocol.handler = { _ in
            (200, [:], """
            { "data": { "type": "user", "id": "42", "attributes": { "full_name": "Test" } } }
            """.data(using: .utf8)!)
        }

        let user = try await client.currentUser()
        XCTAssertEqual(user.id, "42")
        XCTAssertEqual(client.currentUserID, "42")
    }

    func test_session_cookie_attached_when_set() async throws {
        let capturedCookie = CapturedValue<String?>()
        client.sessionID = "secret-session"
        StubURLProtocol.handler = { request in
            capturedCookie.value = request.value(forHTTPHeaderField: "Cookie")
            return (200, [:], """
            { "data": { "type": "user", "id": "1", "attributes": {} } }
            """.data(using: .utf8)!)
        }

        _ = try await client.currentUser()
        XCTAssertEqual(capturedCookie.value, "session_id=secret-session")
    }

    func test_401_maps_to_unauthorized() async {
        StubURLProtocol.handler = { _ in (401, [:], Data()) }
        await assertThrows(PatreonError.unauthorized)
    }

    func test_403_maps_to_forbidden() async {
        StubURLProtocol.handler = { _ in (403, [:], Data()) }
        await assertThrows(PatreonError.forbidden)
    }

    func test_404_maps_to_notFound() async {
        StubURLProtocol.handler = { _ in (404, [:], Data()) }
        await assertThrows(PatreonError.notFound)
    }

    func test_429_parses_retry_after() async {
        StubURLProtocol.handler = { _ in (429, ["Retry-After": "17"], Data()) }
        do {
            _ = try await client.currentUser()
            XCTFail("expected throw")
        } catch PatreonError.rateLimited(let seconds) {
            XCTAssertEqual(seconds, 17)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func test_clearSession_resets_state() async throws {
        StubURLProtocol.handler = { _ in
            (200, [:], """
            { "data": { "type": "user", "id": "42", "attributes": {} } }
            """.data(using: .utf8)!)
        }
        client.sessionID = "s"
        _ = try await client.currentUser()
        XCTAssertNotNil(client.currentUserID)

        client.clearSession()
        XCTAssertNil(client.sessionID)
        XCTAssertNil(client.currentUserID)
    }

    func test_retries_transient_500_then_succeeds() async throws {
        let counter = CapturedValue<Int>()
        counter.value = 0
        let retryingClient = PatreonClient(session: stubbedSession(), maxAttempts: 2)
        StubURLProtocol.handler = { _ in
            counter.value = (counter.value ?? 0) + 1
            if counter.value == 1 {
                return (500, [:], Data())
            }
            return (200, [:], """
            { "data": { "type": "user", "id": "7", "attributes": {} } }
            """.data(using: .utf8)!)
        }

        let user = try await retryingClient.currentUser()
        XCTAssertEqual(user.id, "7")
        XCTAssertEqual(counter.value, 2)
    }

    // MARK: Retry policy (pure)

    func test_retryDelay_honors_rate_limit_capped() {
        XCTAssertEqual(PatreonClient.retryDelay(for: PatreonError.rateLimited(retryAfterSeconds: 3), attempt: 1), 3)
        XCTAssertEqual(PatreonClient.retryDelay(for: PatreonError.rateLimited(retryAfterSeconds: 600), attempt: 1), 10)
    }

    func test_retryDelay_backs_off_5xx() {
        XCTAssertEqual(PatreonClient.retryDelay(for: PatreonError.http(status: 502, body: ""), attempt: 1), 1)
        XCTAssertEqual(PatreonClient.retryDelay(for: PatreonError.http(status: 503, body: ""), attempt: 2), 2)
    }

    func test_retryDelay_never_retries_auth_or_client_errors() {
        XCTAssertNil(PatreonClient.retryDelay(for: PatreonError.unauthorized, attempt: 1))
        XCTAssertNil(PatreonClient.retryDelay(for: PatreonError.forbidden, attempt: 1))
        XCTAssertNil(PatreonClient.retryDelay(for: PatreonError.notFound, attempt: 1))
        XCTAssertNil(PatreonClient.retryDelay(for: PatreonError.http(status: 400, body: ""), attempt: 1))
    }

    func test_retryDelay_retries_transient_url_errors_only() {
        XCTAssertNotNil(PatreonClient.retryDelay(for: URLError(.timedOut), attempt: 1))
        XCTAssertNotNil(PatreonClient.retryDelay(for: URLError(.networkConnectionLost), attempt: 1))
        // Offline should fail fast, not spin.
        XCTAssertNil(PatreonClient.retryDelay(for: URLError(.notConnectedToInternet), attempt: 1))
    }

    // MARK: Helpers

    private func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func assertThrows(
        _ expected: PatreonError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await client.currentUser()
            XCTFail("expected throw", file: file, line: line)
        } catch let error as PatreonError {
            switch (error, expected) {
            case (.unauthorized, .unauthorized), (.forbidden, .forbidden), (.notFound, .notFound):
                break
            default:
                XCTFail("expected \(expected), got \(error)", file: file, line: line)
            }
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}

/// Tiny reference box so the @Sendable stub handler can report values back to
/// the test without data-race diagnostics.
final class CapturedValue<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T?
    var value: T? {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
