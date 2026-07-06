//
//  TopShelfSnapshot.swift
//  PatreonTVTopShelf
//
//  Duplicate of the main app's TopShelfSnapshot to keep the extension binary
//  small — extensions have tight memory and startup budgets, so we avoid
//  linking the whole app's model layer.
//
//  If you change this file, change apps/tvos/PatreonTV/Sources/Services/TopShelfSnapshot.swift too.
//

import Foundation

enum AppGroup {
    static let identifier = "group.com.patreontv.PatreonTV"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

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

    static func load() -> TopShelfSnapshot? {
        guard let dir = AppGroup.containerURL else { return nil }
        let url = dir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(TopShelfSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }
}
