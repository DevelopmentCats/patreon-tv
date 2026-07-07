//
//  CreatorView.swift
//  PatreonTV
//
//  Channel-style page for one creator. Hero cover, name + one-liner, tier
//  badge if the current user supports them, then a shelf of posts.
//

import NukeUI
import SwiftUI
import os

struct CreatorView: View {

    let campaignID: String
    var membership: Membership?

    @State private var vm = CreatorViewModel()

    var body: some View {
        Group {
            switch vm.state {
            case .idle, .loading:
                ProgressView().controlSize(.large)
            case .loaded:
                content
            case .error(let m):
                ErrorView(message: m) { Task { await vm.reload(campaignID: campaignID) } }
            }
        }
        .task { await vm.load(campaignID: campaignID) }
        .background(PatreonColors.background.ignoresSafeArea())
    }

    private let columns = [GridItem(.adaptive(minimum: 400, maximum: 480), spacing: 32)]

    @ViewBuilder
    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // VStack (not Lazy): on tvOS a LazyVStack doesn't render below-the-fold
            // children, so the posts grid under the tall hero wouldn't exist and
            // focus couldn't move down into it. The grid itself stays LazyVGrid.
            VStack(alignment: .leading, spacing: 40) {
                // No .focusSection() on the (non-focusable) hero — it would
                // intercept "up" and dead-end. Focus flows up to the Posts header.
                hero
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let summary = vm.campaign?.attributes.summary, !summary.isEmpty {
                    aboutSection(summary: summary)
                }

                postsHeader
                postsGrid
                    .focusSection()
            }
            .padding(.bottom, 60)
        }
        .scrollClipDisabled()
    }

    private var postsHeader: some View {
        HStack {
            Text("Posts")
                .font(.title2.weight(.semibold))
                .foregroundStyle(PatreonColors.primaryText)
            Spacer()
            // Destination-style link is deliberate here: the payload (the
            // already-loaded posts array) isn't Hashable/Codable, so it can't
            // be a DeepLinkDestination value. This push is never mixed with
            // programmatic path writes, so it's safe.
            NavigationLink {
                CreatorPostSearchView(posts: vm.posts, campaign: vm.campaign)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .padding(14)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Search this creator's posts")
        }
        .padding(.horizontal, 60)
        // Full-width focus target: lets "up" from any grid card (incl. left
        // columns) reliably reach the search button, per Apple's tvOS guidance.
        .focusSection()
    }

    @ViewBuilder
    private var postsGrid: some View {
        LazyVGrid(columns: columns, spacing: 40) {
            ForEach(vm.posts) { post in
                NavigationLink(value: DeepLinkDestination.post(id: post.id, autoplay: false)) {
                    PostCard(post: post, campaign: vm.campaign)
                }
                .buttonStyle(.card)
                .onAppear {
                    // Keep the feed loading forever as you scroll.
                    Task { await vm.loadMore(campaignID: campaignID, current: post) }
                }
            }
        }
        .padding(.horizontal, 60)
    }

    @ViewBuilder
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            heroImage
                .frame(height: 500)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                colors: [Color.black.opacity(0.85), Color.clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 500)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                if let membership, membership.isActivePatron {
                    tierPill
                }

                Text(vm.campaign?.attributes.name ?? " ")
                    .font(.system(size: 80, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)

                if let creation = vm.campaign?.attributes.creationName,
                   !creation.isEmpty {
                    // creation_name is already a full phrase (e.g. "creating
                    // YouTube videos…" / "Creating Drunk Content"); show as-is.
                    Text(creation)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 60)
        }
    }

    @ViewBuilder
    private var heroImage: some View {
        if let url = vm.campaign?.attributes.coverPhotoURL ?? vm.campaign?.attributes.imageURL {
            LazyImage(url: url) { state in
                if let img = state.image {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    PatreonColors.background
                }
            }
        } else {
            LinearGradient(
                colors: [PatreonColors.background, PatreonColors.cardSurface],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var tierPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
            let cents = membership?.attributes.currentlyEntitledAmountCents ?? 0
            Text(cents > 0 ? "Supporting at $\(formatCents(cents))" : "Supporting")
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(PatreonColors.brand.opacity(0.95))
        .foregroundStyle(.white)
        .clipShape(Capsule())
    }

    private func aboutSection(summary: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.title2.weight(.semibold))
                .foregroundStyle(PatreonColors.primaryText)
            Text(HTMLRenderer.stripToPlainText(summary))
                .font(.body)
                .foregroundStyle(PatreonColors.secondaryText)
                .lineLimit(3)
                .frame(maxWidth: 1400, alignment: .leading)
        }
        .padding(.horizontal, 60)
    }

    private func formatCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "%.2f", dollars)
    }
}

/// A pushed search screen for one creator's already-loaded posts. Local filter
/// (Patreon's campaign-posts API has no server-side search). Press Menu to go back.
private struct CreatorPostSearchView: View {

    let posts: [Post]
    let campaign: Campaign?

    @State private var query: String = ""

    private let columns = [GridItem(.adaptive(minimum: 400, maximum: 480), spacing: 32)]

    private var results: [Post] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return posts }
        return posts.filter { post in
            (post.attributes.title?.lowercased().contains(q) ?? false)
                || (post.attributes.teaser?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        ScrollView {
            if results.isEmpty {
                Text(query.isEmpty ? "Type to search" : "No posts match \"\(query)\"")
                    .font(.title3)
                    .foregroundStyle(PatreonColors.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 400)
            } else {
                LazyVGrid(columns: columns, spacing: 40) {
                    ForEach(results) { post in
                        NavigationLink(value: DeepLinkDestination.post(id: post.id, autoplay: false)) {
                            PostCard(post: post, campaign: campaign)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(60)
            }
        }
        .scrollClipDisabled()
        .searchable(text: $query, prompt: "Search \(campaign?.attributes.name ?? "posts")")
        .background(PatreonColors.background.ignoresSafeArea())
    }
}

@Observable
@MainActor
final class CreatorViewModel {

    enum ViewState: Equatable { case idle, loading, loaded, error(String) }

    private(set) var state: ViewState = .idle
    private(set) var campaign: Campaign?
    private(set) var posts: [Post] = []
    private var nextCursor: String?
    private var isFetchingMore = false

    private let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "Creator")

    func load(campaignID: String) async {
        guard state == .idle else { return }
        await reload(campaignID: campaignID)
    }

    func reload(campaignID: String) async {
        state = .loading
        do {
            async let campaignTask = PatreonClient.shared.campaign(id: campaignID)
            async let postsTask = PatreonClient.shared.campaignPosts(campaignID: campaignID, limit: 30)
            let (campaignDoc, postsPage) = try await (campaignTask, postsTask)
            self.campaign = campaignDoc.data
            self.posts = postsPage.data
            self.nextCursor = postsPage.nextCursor
            state = .loaded
        } catch {
            log.error("Creator load failed: \(String(describing: error))")
            state = .error((error as? PatreonError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func loadMore(campaignID: String, current: Post) async {
        guard let cursor = nextCursor, !isFetchingMore,
              let idx = posts.firstIndex(where: { $0.id == current.id }),
              idx >= posts.count - 5
        else { return }
        isFetchingMore = true
        defer { isFetchingMore = false }
        do {
            let page = try await PatreonClient.shared.campaignPosts(campaignID: campaignID, cursor: cursor, limit: 30)
            posts.append(contentsOf: page.data)
            nextCursor = page.nextCursor
        } catch {
            log.error("Creator load-more failed: \(String(describing: error))")
        }
    }
}

// (HTMLRenderer moved to Services/HTMLRenderer.swift)

// os.Logger reference cleanup: use plain Logger since we imported os.
