//
//  HomeViewModel.swift
//  PatreonTV
//
//  Data source for HomeView. Fetches the home feed, keeps a Post → Campaign
//  lookup for creator names, and exposes a fallback hero item so the top
//  band has something to show before the user has focused a card.
//

import Foundation
import Observation
import os.log

@Observable
@MainActor
final class HomeViewModel {

    enum ViewState: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var state: ViewState = .idle
    private(set) var homeFeed: [Post] = []
    private(set) var newFromCreators: [Post] = []
    private(set) var continueWatching: [Post] = []

    /// Post ID → Campaign lookup, populated from the included array.
    private(set) var campaignsByPostID: [String: Campaign] = [:]

    /// The hero band's default when no card is focused yet.
    var heroFallback: FocusedPoster? {
        guard let post = homeFeed.first else { return nil }
        let campaign = campaign(for: post)
        return FocusedPoster(
            postID: post.id,
            title: post.attributes.title,
            heroImageURL: post.attributes.metaImageURL ?? post.attributes.thumbnailURL,
            creatorName: campaign?.attributes.name,
            campaignID: campaign?.id,
            publishedAt: post.attributes.publishedAt,
            isPaid: post.attributes.isPaid ?? false
        )
    }

    private var nextCursor: String?
    private var isFetchingMore = false

    private let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "Home")

    func load() async {
        guard state == .idle else { return }
        await reload()
    }

    func reload() async {
        state = .loading
        do {
            let page = try await PatreonClient.shared.homeFeed(limit: 30)
            homeFeed = page.data
            nextCursor = page.nextCursor
            newFromCreators = Array(page.data.prefix(12))
            indexCampaigns(from: page.included ?? [])
            rebuildContinueWatching()
            state = homeFeed.isEmpty ? .empty : .loaded
        } catch {
            log.error("Home feed load failed: \(String(describing: error))")
            state = .error(errorMessage(from: error))
        }
    }

    func loadMoreIfNeeded(current: Post) async {
        guard let cursor = nextCursor, !isFetchingMore,
              let index = homeFeed.firstIndex(where: { $0.id == current.id }),
              index >= homeFeed.count - 5
        else { return }

        isFetchingMore = true
        defer { isFetchingMore = false }

        do {
            let page = try await PatreonClient.shared.homeFeed(cursor: cursor, limit: 30)
            homeFeed.append(contentsOf: page.data)
            nextCursor = page.nextCursor
            indexCampaigns(from: page.included ?? [])
            rebuildContinueWatching()
        } catch {
            log.error("Home feed pagination failed: \(String(describing: error))")
        }
    }

    /// Rebuild the Continue Watching shelf from the persisted progress store,
    /// keeping only posts we currently have data for.
    private func rebuildContinueWatching() {
        let byID = Dictionary(uniqueKeysWithValues: homeFeed.map { ($0.id, $0) })
        let inProgress = PlaybackProgressStore.shared.continueWatching(matching: byID.keys)
        continueWatching = inProgress.compactMap { byID[$0.postID] }
    }

    /// Walk the `included` array, pulling campaigns and mapping them to the
    /// posts that reference them. Cheaper than a per-post lookup by ID because
    /// posts share creators.
    private func indexCampaigns(from included: [Included]) {
        var campaignByID: [String: Campaign] = [:]
        for inc in included {
            if case .campaign(let c) = inc {
                campaignByID[c.id] = c
            }
        }
        // Now walk the currently-known posts and update the map. This runs
        // after every page, so newly-fetched posts get their campaigns.
        for post in homeFeed {
            if let campaignID = post.relationships?.campaign?.data?.id,
               let campaign = campaignByID[campaignID] {
                campaignsByPostID[post.id] = campaign
            }
        }
    }

    func campaign(for post: Post) -> Campaign? {
        campaignsByPostID[post.id]
    }

    private func errorMessage(from error: Error) -> String {
        if let pe = error as? PatreonError {
            return pe.errorDescription ?? "Something went wrong."
        }
        return error.localizedDescription
    }
}
