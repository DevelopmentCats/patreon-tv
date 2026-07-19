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

    /// One shelf per supported creator: their campaign plus the posts we know
    /// about, newest first, with an independent pagination cursor.
    struct CreatorRow: Identifiable {
        let campaign: Campaign
        var posts: [Post]
        /// Cursor into /campaigns/{id}/posts. Meaningful once didFetchDirect.
        var cursor: String?
        /// True after the first direct campaignPosts fetch (feed grouping only
        /// sees the posts that happened to be in the stream window).
        var didFetchDirect = false
        var isFetching = false
        var id: String { campaign.id }

        var newestPublishedAt: String? { posts.first?.attributes.publishedAt }
    }

    private(set) var state: ViewState = .idle
    private(set) var homeFeed: [Post] = []
    private(set) var continueWatching: [Post] = []
    private(set) var creatorRows: [CreatorRow] = []

    /// Post ID → Campaign lookup, populated from the included array.
    private(set) var campaignsByPostID: [String: Campaign] = [:]

    /// Campaign ID → Campaign, merged from feed includes and memberships.
    private var campaignsByID: [String: Campaign] = [:]

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
            indexCampaigns(from: page.included ?? [])
            writeTopShelfSnapshot()
            state = homeFeed.isEmpty ? .empty : .loaded
        } catch {
            log.error("Home feed load failed: \(String(describing: error))")
            state = .error(errorMessage(from: error))
            return
        }

        // Creator rows and Continue Watching both load after the first paint
        // (the hero and merged shelf are already interactive). Run them
        // concurrently so resolving off-feed Continue Watching posts doesn't
        // wait on the per-creator pages.
        async let rows: Void = buildCreatorRows()
        async let continueWatch: Void = rebuildContinueWatching()
        _ = await (rows, continueWatch)
    }

    // MARK: - Per-creator rows

    /// Builds the per-creator shelves: seeds one row per current membership
    /// (so creators appear even when the feed window missed them), fills each
    /// row with the feed posts we already have, then fetches a first direct
    /// page for rows the feed left empty (bounded).
    private func buildCreatorRows() async {
        // 1. Seed from memberships — best source for "creators you support".
        //    Non-fatal if it fails; the feed grouping still yields rows.
        do {
            let doc = try await PatreonClient.shared.members()
            var supported: [String: Campaign] = [:]
            for inc in doc.included ?? [] {
                if case .campaign(let c) = inc { supported[c.id] = c }
            }
            for member in doc.data where member.isCurrentRelationship {
                if let cid = member.relationships?.campaign?.data?.id,
                   let campaign = supported[cid] {
                    campaignsByID[cid] = campaign
                }
            }
        } catch {
            log.error("Membership seed for creator rows failed: \(String(describing: error))")
        }

        // 2. Group the feed by campaign.
        var postsByCampaign: [String: [Post]] = [:]
        for post in homeFeed {
            guard let cid = post.relationships?.campaign?.data?.id else { continue }
            postsByCampaign[cid, default: []].append(post)
        }

        var rows = campaignsByID.values.map { campaign in
            CreatorRow(campaign: campaign, posts: postsByCampaign[campaign.id] ?? [], cursor: nil)
        }

        // 3. Fill empty rows with a first direct page, bounded so a user with
        //    many creators doesn't trigger a request storm.
        let emptyIDs = rows.filter(\.posts.isEmpty).map(\.id).prefix(8)
        if !emptyIDs.isEmpty {
            let pages = await withTaskGroup(of: (String, Page<Post>?).self) { group in
                for cid in emptyIDs {
                    group.addTask {
                        let page = try? await PatreonClient.shared.campaignPosts(campaignID: cid, limit: 12)
                        return (cid, page)
                    }
                }
                var out: [String: Page<Post>] = [:]
                for await (cid, page) in group {
                    if let page { out[cid] = page }
                }
                return out
            }
            for index in rows.indices {
                guard let page = pages[rows[index].id] else { continue }
                rows[index].posts = page.data
                rows[index].cursor = page.nextCursor
                rows[index].didFetchDirect = true
            }
        }

        creatorRows = sortedRows(rows)
    }

    /// Paginate one creator's row when the user nears its end. The first call
    /// swaps the row from feed-derived posts to the direct campaign feed.
    func loadMoreCreatorRow(campaignID: String, current: Post) async {
        guard let index = creatorRows.firstIndex(where: { $0.id == campaignID }) else { return }
        let row = creatorRows[index]
        guard !row.isFetching else { return }
        guard let postIndex = row.posts.firstIndex(where: { $0.id == current.id }),
              postIndex >= row.posts.count - 3
        else { return }
        // Exhausted: already walked the direct feed to its end.
        if row.didFetchDirect, row.cursor == nil { return }

        creatorRows[index].isFetching = true
        defer {
            if let i = creatorRows.firstIndex(where: { $0.id == campaignID }) {
                creatorRows[i].isFetching = false
            }
        }

        do {
            let page = try await PatreonClient.shared.campaignPosts(
                campaignID: campaignID,
                cursor: row.didFetchDirect ? row.cursor : nil,
                limit: 20
            )
            guard let i = creatorRows.firstIndex(where: { $0.id == campaignID }) else { return }
            var merged = creatorRows[i].posts
            let known = Set(merged.map(\.id))
            merged.append(contentsOf: page.data.filter { !known.contains($0.id) })
            merged.sort { ($0.attributes.publishedAt ?? "") > ($1.attributes.publishedAt ?? "") }
            creatorRows[i].posts = merged
            creatorRows[i].cursor = page.nextCursor
            creatorRows[i].didFetchDirect = true
        } catch {
            log.error("Creator row pagination failed for \(campaignID): \(String(describing: error))")
        }
    }

    /// Rows ordered by most recent post; rows still awaiting content sink to
    /// the bottom (the view hides empty ones).
    private func sortedRows(_ rows: [CreatorRow]) -> [CreatorRow] {
        rows.sorted { a, b in
            switch (a.newestPublishedAt, b.newestPublishedAt) {
            case (let x?, let y?): return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil):
                return (a.campaign.attributes.name ?? "") < (b.campaign.attributes.name ?? "")
            }
        }
    }

    /// Rebuild the Continue Watching shelf from the persisted progress store.
    /// Older in-progress posts often aren't in the recent feed, so resolve any
    /// we don't already hold by fetching them individually — otherwise a
    /// half-watched but not-recent video silently vanishes from the shelf.
    private func rebuildContinueWatching() async {
        let entries = PlaybackProgressStore.shared.inProgress()
        guard !entries.isEmpty else {
            continueWatching = []
            return
        }

        // Start from posts we already hold (feed + creator rows).
        var byID = Dictionary(homeFeed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for row in creatorRows {
            for post in row.posts where byID[post.id] == nil { byID[post.id] = post }
        }

        // Fetch the ones we're missing, concurrently.
        let missing = entries.map(\.postID).filter { byID[$0] == nil }
        if !missing.isEmpty {
            let docs = await withTaskGroup(of: SingleResource<Post>?.self) { group in
                for id in missing {
                    group.addTask { try? await PatreonClient.shared.post(id: id) }
                }
                var out: [SingleResource<Post>] = []
                for await doc in group { if let doc { out.append(doc) } }
                return out
            }
            for doc in docs {
                byID[doc.data.id] = doc.data
                // Keep the creator lookup populated so the card shows its name
                // and the NSFW gate can evaluate off-feed posts. Prefer a
                // fuller campaign we already hold (feed includes carry is_nsfw);
                // don't clobber it with the post fetch's leaner copy.
                for inc in doc.included ?? [] {
                    if case .campaign(let campaign) = inc {
                        let resolved = campaignsByID[campaign.id] ?? campaign
                        campaignsByID[campaign.id] = resolved
                        campaignsByPostID[doc.data.id] = resolved
                    }
                }
            }
        }

        continueWatching = entries.compactMap { byID[$0.postID] }
    }

    /// Persist a top-shelf snapshot so the Top Shelf extension can show recent
    /// posts on the Apple TV home screen without making any network calls.
    private func writeTopShelfSnapshot() {
        let items = homeFeed.prefix(10).map { post in
            TopShelfSnapshot.Item(
                postID: post.id,
                title: post.attributes.title ?? "Untitled",
                creator: campaign(for: post)?.attributes.name,
                imageURL: post.attributes.posterImageURL,
                publishedAt: post.attributes.publishedAt
            )
        }
        let snapshot = TopShelfSnapshot(items: Array(items), updatedAt: Date())
        do {
            try snapshot.save()
        } catch {
            log.error("Top shelf snapshot save failed: \(String(describing: error))")
        }
    }

    /// Walk the `included` array, pulling campaigns and mapping them to the
    /// posts that reference them. Cheaper than a per-post lookup by ID because
    /// posts share creators.
    private func indexCampaigns(from included: [Included]) {
        for inc in included {
            if case .campaign(let c) = inc {
                campaignsByID[c.id] = c
            }
        }
        // Now walk the currently-known posts and update the map. This runs
        // after every page, so newly-fetched posts get their campaigns.
        for post in homeFeed {
            if let campaignID = post.relationships?.campaign?.data?.id,
               let campaign = campaignsByID[campaignID] {
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
