//
//  PlaybackProgressStoreTests.swift
//  PatreonTVTests
//
//  Uses an injected UserDefaults suite so test runs are hermetic and never
//  touch real watch progress on a dev device.
//

import XCTest
@testable import PatreonTV

@MainActor
final class PlaybackProgressStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var store: PlaybackProgressStore!
    private let suiteName = "com.patreontv.tests.playback"

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = PlaybackProgressStore(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_record_and_retrieve() {
        let p = PlaybackProgress(
            postID: "abc",
            positionSeconds: 42,
            durationSeconds: 100,
            lastUpdated: Date()
        )
        store.record(p)

        let out = store.progress(for: "abc")
        XCTAssertEqual(out?.positionSeconds, 42)
        XCTAssertEqual(out?.durationSeconds, 100)
    }

    func test_persists_across_instances() {
        store.record(.init(postID: "persisted", positionSeconds: 30, durationSeconds: 90, lastUpdated: Date()))

        let secondStore = PlaybackProgressStore(defaults: defaults)
        XCTAssertEqual(secondStore.progress(for: "persisted")?.positionSeconds, 30)
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
        store.record(.init(postID: "watching-1", positionSeconds: 10, durationSeconds: 100, lastUpdated: now))
        store.record(.init(postID: "watching-2", positionSeconds: 40, durationSeconds: 100, lastUpdated: now))
        store.record(.init(postID: "finished", positionSeconds: 99, durationSeconds: 100, lastUpdated: now))

        // Ask only about IDs we know exist
        let list = store.continueWatching(matching: ["watching-1", "watching-2", "finished"])
        XCTAssertEqual(list.map(\.postID).sorted(), ["watching-1", "watching-2"])
    }

    func test_continueWatching_filters_by_matching_ids() {
        store.record(.init(postID: "known", positionSeconds: 10, durationSeconds: 100, lastUpdated: Date()))
        store.record(.init(postID: "stale", positionSeconds: 10, durationSeconds: 100, lastUpdated: Date()))

        let list = store.continueWatching(matching: ["known"])
        XCTAssertEqual(list.map(\.postID), ["known"])
    }

    func test_clear_removes_single_entry() {
        store.record(.init(postID: "x", positionSeconds: 10, durationSeconds: 100, lastUpdated: Date()))
        XCTAssertNotNil(store.progress(for: "x"))
        store.clear(postID: "x")
        XCTAssertNil(store.progress(for: "x"))
    }
}
