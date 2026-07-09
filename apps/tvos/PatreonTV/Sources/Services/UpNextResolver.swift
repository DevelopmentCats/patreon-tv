//
//  UpNextResolver.swift
//  PatreonTV
//
//  Picks the post to queue after playback finishes: the next playable post
//  from the same creator, in the campaign feed's newest-first order (so
//  "next" walks backward through the catalog, the direction a viewer browsing
//  from the top of a feed naturally moves). Prefers posts the user hasn't
//  finished; falls back to the immediate neighbor if everything's watched.
//

import Foundation
import os.log

enum UpNextResolver {

    private static let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "UpNext")

    /// Post types we can actually hand to a player.
    nonisolated static let playableTypes: Set<Post.PostType> = [
        .videoExternalFile, .videoEmbed, .audioFile, .audioEmbed, .podcast,
    ]

    nonisolated static func isPlayable(_ post: Post) -> Bool {
        guard post.attributes.currentUserCanView != false else { return false }
        guard let type = post.attributes.postType else { return false }
        return playableTypes.contains(type)
    }

    /// Pure selection core (unit-tested): given the campaign's posts in feed
    /// order (newest first), return the next playable post after `currentID`,
    /// preferring one the user hasn't finished.
    nonisolated static func selectNext(
        afterPostID currentID: String,
        in posts: [Post],
        isFinished: (String) -> Bool
    ) -> Post? {
        guard let index = posts.firstIndex(where: { $0.id == currentID }) else { return nil }
        let candidates = posts[(index + 1)...].filter { isPlayable($0) }
        return candidates.first { !isFinished($0.id) } ?? candidates.first
    }

    /// Fetches the campaign feed (following the cursor a bounded number of
    /// pages until the current post is located) and picks the next post.
    /// Returns nil on any failure — Up Next is best-effort.
    @MainActor
    static func next(after currentPostID: String, campaignID: String) async -> Post? {
        var cursor: String?
        var posts: [Post] = []

        for _ in 0..<3 {
            guard let page = try? await PatreonClient.shared.campaignPosts(
                campaignID: campaignID, cursor: cursor, limit: 30
            ) else { break }
            posts.append(contentsOf: page.data)

            // Stop once we can see past the current post.
            if let index = posts.firstIndex(where: { $0.id == currentPostID }),
               index < posts.count - 1 {
                break
            }
            guard let nextCursor = page.nextCursor else { break }
            cursor = nextCursor
        }

        let next = selectNext(afterPostID: currentPostID, in: posts) {
            PlaybackProgressStore.shared.progress(for: $0)?.isFinished == true
        }
        if let next {
            log.info("Up next after \(currentPostID): \(next.id)")
        } else {
            log.info("No up-next candidate after \(currentPostID)")
        }
        return next
    }
}
