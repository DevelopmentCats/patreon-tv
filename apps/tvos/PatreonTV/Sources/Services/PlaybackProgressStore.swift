//
//  PlaybackProgressStore.swift
//  PatreonTV
//
//  Persists "how far did I get" for each post the user has watched.
//  Backed by UserDefaults for MVP — a Core Data / SwiftData store can come
//  later if the list grows large.
//
//  A record is kept for 90 days after its last update, then evicted.
//

import Foundation

struct PlaybackProgress: Codable, Hashable {
    let postID: String
    let positionSeconds: Double
    let durationSeconds: Double
    let lastUpdated: Date

    /// True if the user watched past ~95% — we consider these done and hide
    /// them from Continue Watching.
    var isFinished: Bool {
        guard durationSeconds > 0 else { return false }
        return positionSeconds / durationSeconds >= 0.95
    }
}

@MainActor
final class PlaybackProgressStore {

    static let shared = PlaybackProgressStore()

    private let key = "playback_progress_v1"
    private let maxEntries = 200
    private let retention: TimeInterval = 60 * 60 * 24 * 90  // 90 days
    private let defaults: UserDefaults

    private var records: [String: PlaybackProgress] = [:]

    /// Injectable for tests — pass `UserDefaults(suiteName:)` so test runs
    /// never touch the real store on a dev device.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func progress(for postID: String) -> PlaybackProgress? {
        records[postID]
    }

    func record(_ progress: PlaybackProgress) {
        records[progress.postID] = progress
        prune()
        save()
    }

    /// Posts currently in "continue watching" — not finished, sorted most-recent first.
    func continueWatching(matching postIDs: some Collection<String>) -> [PlaybackProgress] {
        records.values
            .filter { !$0.isFinished }
            .filter { postIDs.contains($0.postID) }
            .sorted { $0.lastUpdated > $1.lastUpdated }
    }

    /// Every meaningfully-started, unfinished post, most-recent first —
    /// independent of the current feed. The caller resolves each postID to a
    /// Post (fetching if it isn't already loaded), so older off-feed videos
    /// still surface in Continue Watching.
    func inProgress(limit: Int = 15) -> [PlaybackProgress] {
        records.values
            .filter { !$0.isFinished && $0.positionSeconds > 5 }
            .sorted { $0.lastUpdated > $1.lastUpdated }
            .prefix(limit)
            .map { $0 }
    }

    func clear(postID: String) {
        records.removeValue(forKey: postID)
        save()
    }

    func clearAll() {
        records.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: PlaybackProgress].self, from: data)
        else { return }
        records = decoded
        prune()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-retention)
        records = records.filter { $0.value.lastUpdated > cutoff }

        if records.count > maxEntries {
            let sorted = records.values.sorted { $0.lastUpdated > $1.lastUpdated }
            let keep = Set(sorted.prefix(maxEntries).map(\.postID))
            records = records.filter { keep.contains($0.key) }
        }
    }
}
