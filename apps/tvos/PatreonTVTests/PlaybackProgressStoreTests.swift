//
//  PlaybackProgressStoreTests.swift
//  PatreonTVTests
//
//  The store uses UserDefaults.standard, which is shared across tests in a
//  target. We reset in setUp and use unique keys so tests don't interfere
//  with a real device install.
//

import XCTest
@testable import PatreonTV

@MainActor
final class PlaybackProgressStoreTests: XCTestCase {

    override func setUp() async throws {
        // Clear everything at the start so tests are hermetic. This nukes any
        // real progress data on a dev device — acceptable for a test target.
        PlaybackProgressStore.shared.clearAll()
    }

    func test_record_and_retrieve() {
        let p = PlaybackProgress(
            postID: "abc",
            positionSeconds: 42,
            durationSeconds: 100,
            lastUpdated: Date()
        )
        PlaybackProgressStore.shared.record(p)

        let out = PlaybackProgressStore.shared.progress(for: "abc")
        XCTAssertEqual(out?.positionSeconds, 42)
        XCTAssertEqual(out?.durationSeconds, 100)
    }

    func test_isFinished_thresholds() {
        let notDone = PlaybackProgress(postID: "a", positionSeconds: 94, durationSeconds: 100, lastUpdated: Date())
        XCTAssertFalse(notDone.isFinished)

        let done = PlaybackProgress(postID: "b", positionSeconds: 96, durationSeconds: 100, lastUpdated: Date())
        XCTAssertTrue(done.isFinished)

        let zeroDuration = PlaybackProgress(postID: "c", positionSeconds: 50, durationSeconds: 0, lastUpdated: Date())
        XCTAssertFalse(zeroDuration.isFinished)
    }

    func test_continueWatching_excludes_finished_and_unknown() {
        let now = Date()
        PlaybackProgressStore.shared.record(.init(postID: "watching-1", positionSeconds: 10, durationSeconds: 100, lastUpdated: now))
        PlaybackProgressStore.shared.record(.init(postID: "watching-2", positionSeconds: 40, durationSeconds: 100, lastUpdated: now))
        PlaybackProgressStore.shared.record(.init(postID: "finished", positionSeconds: 99, durationSeconds: 100, lastUpdated: now))

        // Ask only about IDs we know exist
        let list = PlaybackProgressStore.shared.continueWatching(matching: ["watching-1", "watching-2", "finished"])
        XCTAssertEqual(list.map(\.postID).sorted(), ["watching-1", "watching-2"])
    }

    func test_continueWatching_filters_by_matching_ids() {
        PlaybackProgressStore.shared.record(.init(postID: "known", positionSeconds: 10, durationSeconds: 100, lastUpdated: Date()))
        PlaybackProgressStore.shared.record(.init(postID: "stale", positionSeconds: 10, durationSeconds: 100, lastUpdated: Date()))

        let list = PlaybackProgressStore.shared.continueWatching(matching: ["known"])
        XCTAssertEqual(list.map(\.postID), ["known"])
    }

    func test_clear_removes_single_entry() {
        PlaybackProgressStore.shared.record(.init(postID: "x", positionSeconds: 10, durationSeconds: 100, lastUpdated: Date()))
        XCTAssertNotNil(PlaybackProgressStore.shared.progress(for: "x"))
        PlaybackProgressStore.shared.clear(postID: "x")
        XCTAssertNil(PlaybackProgressStore.shared.progress(for: "x"))
    }
}
