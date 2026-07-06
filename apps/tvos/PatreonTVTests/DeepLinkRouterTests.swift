//
//  DeepLinkRouterTests.swift
//  PatreonTVTests
//
//  URL parsing edge cases for patreontv:// deep links.
//

import XCTest
@testable import PatreonTV

@MainActor
final class DeepLinkRouterTests: XCTestCase {

    func test_open_post_no_autoplay() {
        let r = DeepLinkRouter()
        r.handle(url: URL(string: "patreontv://post/12345")!)
        XCTAssertEqual(r.pending, .post(id: "12345", autoplay: false))
    }

    func test_open_post_with_autoplay() {
        let r = DeepLinkRouter()
        r.handle(url: URL(string: "patreontv://post/12345/play")!)
        XCTAssertEqual(r.pending, .post(id: "12345", autoplay: true))
    }

    func test_open_creator() {
        let r = DeepLinkRouter()
        r.handle(url: URL(string: "patreontv://creator/6789")!)
        XCTAssertEqual(r.pending, .creator(id: "6789"))
    }

    func test_wrong_scheme_ignored() {
        let r = DeepLinkRouter()
        r.handle(url: URL(string: "https://patreon.com/post/12345")!)
        XCTAssertNil(r.pending)
    }

    func test_unknown_host_ignored() {
        let r = DeepLinkRouter()
        r.handle(url: URL(string: "patreontv://unknown/12345")!)
        XCTAssertNil(r.pending)
    }

    func test_missing_id_ignored() {
        let r = DeepLinkRouter()
        r.handle(url: URL(string: "patreontv://post/")!)
        XCTAssertNil(r.pending)
    }

    func test_consume_clears_pending() {
        let r = DeepLinkRouter()
        r.handle(url: URL(string: "patreontv://post/1")!)
        XCTAssertNotNil(r.pending)
        r.consume()
        XCTAssertNil(r.pending)
    }
}
