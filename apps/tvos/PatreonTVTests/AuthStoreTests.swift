//
//  AuthStoreTests.swift
//  PatreonTVTests
//
//  The session-clearing policy: only a definitive credential rejection
//  (401/403) may destroy the stored session. Transient failures — offline,
//  outage, rate limit, decode drift — must keep it.
//

import XCTest
@testable import PatreonTV

final class AuthStoreTests: XCTestCase {

    func test_clears_session_only_on_credential_rejection() {
        XCTAssertTrue(AuthStore.shouldClearSession(after: PatreonError.unauthorized))
        XCTAssertTrue(AuthStore.shouldClearSession(after: PatreonError.forbidden))
    }

    func test_keeps_session_on_transient_errors() {
        XCTAssertFalse(AuthStore.shouldClearSession(after: URLError(.notConnectedToInternet)))
        XCTAssertFalse(AuthStore.shouldClearSession(after: URLError(.timedOut)))
        XCTAssertFalse(AuthStore.shouldClearSession(after: PatreonError.rateLimited(retryAfterSeconds: 60)))
        XCTAssertFalse(AuthStore.shouldClearSession(after: PatreonError.http(status: 503, body: "")))
        XCTAssertFalse(AuthStore.shouldClearSession(after: PatreonError.badResponse))
        XCTAssertFalse(AuthStore.shouldClearSession(
            after: PatreonError.decoding(underlying: URLError(.cannotParseResponse))
        ))
    }
}
