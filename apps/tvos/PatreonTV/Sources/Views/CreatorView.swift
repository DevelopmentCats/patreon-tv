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

    @ViewBuilder
    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 40) {
                hero
                    .padding(.bottom, -80)

                if !vm.posts.isEmpty {
                    Shelf(
                        title: "Latest",
                        posts: vm.posts,
                        campaignFor: { _ in vm.campaign },
                        onNearEnd: { post in
                            Task { await vm.loadMore(campaignID: campaignID, current: post) }
                        }
                    )
                }

                if let summary = vm.campaign?.attributes.summary, !summary.isEmpty {
                    aboutSection(summary: summary)
                }

                Spacer(minLength: 60)
            }
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            heroImage
                .frame(height: 640)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                colors: [Color.black.opacity(0.85), Color.clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 640)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                if let membership, membership.isActivePatron {
                    tierPill
                }

                Text(vm.campaign?.attributes.name ?? " ")
                    .font(.system(size: 80, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)

                if let creation = vm.campaign?.attributes.creationName {
                    Text("Is creating \(creation)")
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
                .frame(maxWidth: 1400, alignment: .leading)
        }
        .padding(.horizontal, 60)
    }

    private func formatCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "%.2f", dollars)
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

// Split out for testability + reuse.
enum HTMLRenderer {
    /// Trivial tag-stripper for MVP. A proper AttributedString renderer lives
    /// in HTMLRenderer.markdown(from:) below.
    static func stripToPlainText(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "<br>", with: "\n")
        s = s.replacingOccurrences(of: "<br/>", with: "\n")
        s = s.replacingOccurrences(of: "<br />", with: "\n")
        s = s.replacingOccurrences(of: "</p>", with: "\n\n")
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&#39;", with: "'")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// os.Logger reference cleanup: use plain Logger since we imported os.
