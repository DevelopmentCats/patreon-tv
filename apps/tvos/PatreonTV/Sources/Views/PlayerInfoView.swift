//
//  PlayerInfoView.swift
//  PatreonTV
//
//  "Details" tab inside the player's swipe-down info panel. Shows the full
//  post description so the viewer can read show notes without leaving
//  playback. Height is constrained by AVKit's panel; the text scrolls.
//

import SwiftUI

struct PlayerInfoView: View {

    let post: Post
    let campaign: Campaign?

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 12) {
                Text(post.attributes.title ?? "Untitled")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                if let subtitle {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)

            if let description {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.primary.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .focusable()
            } else {
                Spacer()
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let name = campaign?.attributes.name, !name.isEmpty {
            parts.append(name)
        }
        if let published = formattedDate(post.attributes.publishedAt) {
            parts.append(published)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var description: AttributedString? {
        if let content = post.attributes.content, !content.isEmpty {
            return HTMLRenderer.attributedString(from: content)
        }
        if let teaser = post.attributes.teaser, !teaser.isEmpty {
            return AttributedString(teaser)
        }
        return nil
    }

    private func formattedDate(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return nil
        }
        return date.formatted(date: .long, time: .omitted)
    }
}
