//
//  PostTypeIcon.swift
//  PatreonTV
//
//  Single source of truth for the SF Symbol representing each post type.
//  Used by PostCard placeholders and the PostDetailView hero placeholder.
//

extension Post.PostType? {
    /// SF Symbol name for a post-type placeholder.
    var iconName: String {
        switch self {
        case .videoExternalFile, .videoEmbed: "play.rectangle.fill"
        case .audioFile, .audioEmbed, .podcast: "waveform"
        case .imageFile: "photo"
        case .link: "link"
        case .textOnly: "text.alignleft"
        case .poll: "chart.bar.fill"
        case .livestreamYoutube, .livestreamCrowdcast: "dot.radiowaves.left.and.right"
        case .other, nil: "square.stack.fill"
        }
    }
}
