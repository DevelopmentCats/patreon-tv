//
//  TopShelfSnapshotTests.swift
//  PatreonTVTests
//
//  Round-trips the snapshot through a temp directory (the App Group container
//  isn't available in the test host, so the directory is injected).
//

import XCTest
@testable import PatreonTV

final class TopShelfSnapshotTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("top-shelf-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_save_and_load_round_trip() throws {
        let snapshot = TopShelfSnapshot(
            items: [
                .init(
                    postID: "123",
                    title: "A Post",
                    creator: "A Creator",
                    imageURL: URL(string: "https://example.com/poster.jpg"),
                    publishedAt: "2026-07-01T00:00:00.000+00:00"
                ),
                .init(postID: "456", title: "No Image", creator: nil, imageURL: nil, publishedAt: nil),
            ],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try snapshot.save(to: tempDir)
        let loaded = TopShelfSnapshot.load(from: tempDir)

        XCTAssertEqual(loaded?.items.count, 2)
        XCTAssertEqual(loaded?.items.first?.postID, "123")
        XCTAssertEqual(loaded?.items.first?.imageURL?.host(), "example.com")
        XCTAssertEqual(loaded?.items.last?.title, "No Image")
        XCTAssertEqual(loaded?.updatedAt, snapshot.updatedAt)
    }

    func test_load_returns_nil_when_missing() {
        XCTAssertNil(TopShelfSnapshot.load(from: tempDir))
    }

    func test_load_returns_nil_for_nil_directory() {
        XCTAssertNil(TopShelfSnapshot.load(from: nil))
    }

    func test_save_overwrites_previous_snapshot() throws {
        try TopShelfSnapshot(items: [], updatedAt: Date()).save(to: tempDir)
        let newer = TopShelfSnapshot(
            items: [.init(postID: "9", title: "New", creator: nil, imageURL: nil, publishedAt: nil)],
            updatedAt: Date()
        )
        try newer.save(to: tempDir)

        XCTAssertEqual(TopShelfSnapshot.load(from: tempDir)?.items.map(\.postID), ["9"])
    }
}
