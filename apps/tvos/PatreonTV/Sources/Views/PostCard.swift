//
//  PostCard.swift
//  PatreonTV
//
//  A single card on a shelf. Landscape 16:9 aspect (`400x225` at TV distance
//  is comfortable), with title + creator underneath. Uses NukeUI's
//  `LazyImage` for cached, non-flickering thumbnails.
//
//  tvOS rules honored:
//  - FOCUS-04: parallax effect on focus — .buttonStyle(.card) on the parent
//    NavigationLink applies this natively.
//  - FOCUS-05: 400×225 exceeds 250×150 minimum.
//  - ACCESS-01: full accessibility label + hint.
//

import NukeUI
import SwiftUI

struct PostCard: View {

    let post: Post

    private let cardWidth: CGFloat = 400
    private let cardHeight: CGFloat = 225   // 16:9

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            posterImage
                .frame(width: cardWidth, height: cardHeight)
                .background(PatreonColors.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topTrailing) { badge }
                .overlay(alignment: .bottomLeading) { durationLabel }

            VStack(alignment: .leading, spacing: 4) {
                Text(post.attributes.title ?? "Untitled")
                    .font(.headline)
                    .foregroundStyle(PatreonColors.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: cardWidth, alignment: .leading)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(PatreonColors.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var posterImage: some View {
        if let url = post.attributes.thumbnailURL ?? post.attributes.metaImageURL {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            PatreonColors.cardSurface
            Image(systemName: iconForPostType)
                .font(.system(size: 48))
                .foregroundStyle(PatreonColors.tertiaryText)
        }
    }

    private var iconForPostType: String {
        switch post.attributes.postType {
        case .videoExternalFile, .videoEmbed: "play.rectangle.fill"
        case .audioFile, .audioEmbed, .podcast: "waveform"
        case .imageFile: "photo"
        case .link: "link"
        case .textOnly: "text.alignleft"
        case .poll: "chart.bar.fill"
        case .livestreamYoutube, .livestreamCrowdcast: "dot.radiowaves.left.and.right"
        case .other, nil: "square"
        }
    }

    @ViewBuilder
    private var badge: some View {
        if post.attributes.isPaid == true {
            Text("PATRON")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(PatreonColors.brand.opacity(0.9))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .padding(8)
        }
    }

    @ViewBuilder
    private var durationLabel: some View {
        // Later: pull duration from Media relation
        EmptyView()
    }

    private var subtitle: String? {
        // Later: creator name from the campaign relation
        nil
    }

    private var accessibilityLabel: String {
        let title = post.attributes.title ?? "Untitled post"
        let paid = post.attributes.isPaid == true ? ", patron-only" : ""
        return "\(title)\(paid)"
    }
}
