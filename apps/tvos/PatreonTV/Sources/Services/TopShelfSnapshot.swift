//
//  TopShelfSnapshot.swift
//  Shared between the main app and the Top Shelf extension — this single file
//  is compiled into BOTH targets (see project.yml), so there is no duplicate
//  copy to keep in sync.
//
//  The main app writes a small JSON snapshot to a shared App Group container.
//  The Top Shelf extension reads it on demand. This avoids the extension
//  needing to hit the Patreon API (extensions have short runtime budgets).
//

import Foundation

/// App Group used to share data between the tvOS app and the Top Shelf
/// extension. Must be registered in Apple Developer portal and set in each
/// target's entitlements.
enum AppGroup {
    static let identifier = "group.com.patreontv.PatreonTV"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// On tvOS the App Group container *root* is read-only — attempting to write
    /// there fails with EPERM ("Operation not permitted"). Only the
    /// `Library/Caches` subdirectory is writable, so all shared files live
    /// there. Content is regenerable (a top-shelf snapshot), so the system
    /// being free to purge Caches is fine.
    static var sharedCachesURL: URL? {
        guard let root = containerURL else { return nil }
        let caches = root.appendingPathComponent("Library/Caches", isDirectory: true)
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        return caches
    }
}

/// Serializable snapshot the main app writes and the extension reads.
struct TopShelfSnapshot: Codable {

    struct Item: Codable, Identifiable {
        let postID: String
        let title: String
        let creator: String?
        let imageURL: URL?
        let publishedAt: String?
        var id: String { postID }
    }

    let items: [Item]
    let updatedAt: Date

    private static let filename = "top-shelf.json"

    /// Directory injectable for tests (round-trip against a temp dir).
    static func load(from directory: URL? = AppGroup.sharedCachesURL) -> TopShelfSnapshot? {
        guard let dir = directory else { return nil }
        let url = dir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(TopShelfSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }

    func save(to directory: URL? = AppGroup.sharedCachesURL) throws {
        guard let dir = directory else {
            throw NSError(domain: "TopShelfSnapshot", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "App Group container not available"])
        }
        let url = dir.appendingPathComponent(Self.filename)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: [.atomic])
    }
}
