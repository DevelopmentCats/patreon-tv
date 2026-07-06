//
//  ContentProvider.swift
//  PatreonTVTopShelf
//
//  Populates the tvOS Home Screen's top shelf with the current user's most
//  recent posts. The extension reads a shared App Group container that the
//  main app writes to; it does not talk to Patreon directly (extensions
//  have restricted lifecycles and shouldn't make long network calls).
//
//  Design rules from tvos-design-guidelines skill (Top Shelf category):
//  - TOP-01: sectioned layout for organized content presentation
//  - TOP-02: use TVTopShelfContentProvider (TVTopShelfProvider is deprecated
//    since tvOS 14)
//  - TOP-03: images high-quality (1920x720 wide, 620x800 poster)
//  - TOP-04: every item deep-links via URL scheme (patreontv://post/<id>)
//  - TOP-05: keep content fresh — regenerate on app-side snapshots
//

import Foundation
import TVServices

final class ContentProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        // Load the snapshot the main app wrote. If nothing is there yet (fresh
        // install), we return nil which shows the default app icon behavior.
        guard let snapshot = TopShelfSnapshot.load() else {
            return nil
        }

        let items: [TVTopShelfSectionedItem] = snapshot.items.prefix(10).map { entry in
            let item = TVTopShelfSectionedItem(identifier: entry.postID)
            item.title = entry.title
            item.playAction = TVTopShelfAction(url: URL(string: "patreontv://post/\(entry.postID)/play")!)
            item.displayAction = TVTopShelfAction(url: URL(string: "patreontv://post/\(entry.postID)")!)

            if let imageURL = entry.imageURL {
                item.setImageURL(imageURL, for: .screenScale1x)
                item.setImageURL(imageURL, for: .screenScale2x)
            }

            item.imageShape = .hdtv

            return item
        }

        let section = TVTopShelfItemCollection(items: items)
        section.title = "Recent from Your Creators"

        return TVTopShelfSectionedContent(sections: [section])
    }
}
