//
//  Shelf.swift
//  PatreonTV
//
//  A horizontal shelf of posts. tvOS design rules FOCUS-02 (predictable
//  spatial movement), FOCUS-05 (minimum 250x150pt cards), FOCUS-09
//  (stable order).
//
//  Uses .focusSection() so vertical swipes move between shelves in the
//  parent VStack, and horizontal swipes move within this shelf.
//

import NukeUI
import SwiftUI

struct Shelf: View {

    let title: String
    let posts: [Post]
    /// Optional lookup: given a post, return its owning Campaign. Enables
    /// creator names in the focused-poster metadata for the hero band.
    var campaignFor: ((Post) -> Campaign?)? = nil
    /// Called when the shelf's data source should page in more items — we pass
    /// the last-visible post so the caller can decide whether to fetch more.
    var onNearEnd: ((Post) -> Void)? = nil
    /// When set, the header becomes a focusable link (creator rows navigate
    /// to the creator's page). Shown with the optional avatar.
    var headerLink: DeepLinkDestination? = nil
    var headerAvatarURL: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 32) {
                    ForEach(posts) { post in
                        NavigationLink(value: DeepLinkDestination.post(id: post.id, autoplay: false)) {
                            PostCard(post: post, campaign: campaignFor?(post))
                        }
                        .buttonStyle(.card)   // Native tvOS focus effect (parallax + lift)
                        .focusedValue(\.focusedPoster, focusedPoster(for: post))
                        .onAppear {
                            // Cheap heuristic: if we're within 5 of the end,
                            // ask for more. Real prefetch policy lives in the
                            // view model.
                            if posts.suffix(5).contains(where: { $0.id == post.id }) {
                                onNearEnd?(post)
                            }
                        }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 30)   // Breathing room for focused-card scale
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }

    @ViewBuilder
    private var header: some View {
        if let headerLink {
            NavigationLink(value: headerLink) {
                HStack(spacing: 16) {
                    if let headerAvatarURL {
                        LazyImage(url: headerAvatarURL) { state in
                            if let image = state.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                PatreonColors.cardSurface
                            }
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                    }
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(PatreonColors.secondaryText)
                }
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 60)
            .accessibilityLabel("\(title), view creator")
        } else {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(PatreonColors.primaryText)
                .padding(.horizontal, 60)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func focusedPoster(for post: Post) -> FocusedPoster {
        let campaign = campaignFor?(post)
        return FocusedPoster(
            postID: post.id,
            title: post.attributes.title,
            heroImageURL: post.attributes.posterImageURL,
            creatorName: campaign?.attributes.name,
            campaignID: campaign?.id ?? post.relationships?.campaign?.data?.id,
            publishedAt: post.attributes.publishedAt,
            isPaid: post.attributes.isPaid ?? false
        )
    }
}
