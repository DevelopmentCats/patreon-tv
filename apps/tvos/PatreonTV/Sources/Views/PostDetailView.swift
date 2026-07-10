//
//  PostDetailView.swift
//  PatreonTV
//
//  Full detail for a single post. Fetches by ID (which returns the media
//  relationship with the Mux HLS URL if the current session can view it).
//

import NukeUI
import SwiftUI
import os.log

struct PostDetailView: View {

    let postID: String
    /// When true (Top Shelf "Play", the featured hero button, deep links with
    /// /play), playback starts as soon as the post loads.
    var autoplay: Bool = false

    init(postID: String, autoplay: Bool = false) {
        self.postID = postID
        self.autoplay = autoplay
        _currentPostID = State(initialValue: postID)
    }

    /// The post currently shown/playing. Starts as `postID` and advances when
    /// the user accepts an Up Next suggestion.
    @State private var currentPostID: String
    /// The next post queued by the Up Next overlay after playback finishes.
    @State private var upNext: Post?
    @State private var post: Post?
    @State private var campaign: Campaign?
    @State private var videoDuration: Double?
    @State private var heroImageURL: URL?
    @State private var mediaURL: URL?
    @State private var errorMessage: String?
    @State private var playbackErrorMessage: String?
    /// Set while the player cover is still on screen; promoted to
    /// `playbackErrorMessage` in the cover's `onDismiss` so the alert never
    /// tries to present on top of the (still-dismissing) full-screen cover.
    @State private var pendingPlaybackError: String?
    @State private var isLoading = true
    @State private var playbackSource: MediaPlaybackSource?
    @State private var isPreparingPlayback = false
    @State private var didAutoplay = false
    /// Bumped to force a re-read of PlaybackProgressStore after we clear it.
    @State private var resumeProgressStamp = UUID()

    private let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "PostDetail")

    var body: some View {
        Group {
            if isLoading {
                ProgressView().controlSize(.large)
            } else if let post {
                loaded(post: post)
            } else if let errorMessage {
                ErrorView(message: errorMessage) { Task { await load() } }
            }
        }
        .task { await load() }
        .background(PatreonColors.background.ignoresSafeArea())
        .fullScreenCover(item: $playbackSource, onDismiss: {
            // The cover is fully gone now — safe to raise a deferred error alert.
            if let pending = pendingPlaybackError {
                pendingPlaybackError = nil
                playbackErrorMessage = pending
            }
        }) { source in
            ZStack {
                player(for: source)
                    // Changing the source must rebuild the player — the host VC
                    // configures its AVPlayer exactly once.
                    .id(source.id)
                    .ignoresSafeArea()

                if let next = upNext {
                    UpNextOverlayView(
                        post: next,
                        creatorName: campaign?.attributes.name,
                        countdownSeconds: ContentPreferences.shared.autoplayNext ? 10 : nil,
                        onPlay: { Task { await playNext(next) } },
                        onDismiss: {
                            upNext = nil
                            playbackSource = nil
                        }
                    )
                }
            }
        }
        .alert(
            "Playback Problem",
            isPresented: Binding(
                get: { playbackErrorMessage != nil },
                set: { if !$0 { playbackErrorMessage = nil } }
            )
        ) {
            Button("Try Again") { Task { await prepareAndPlay() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(playbackErrorMessage ?? "")
        }
    }

    /// Audio posts get the custom now-playing screen; video uses the native
    /// AVPlayerViewController wrapper.
    @ViewBuilder
    private func player(for source: MediaPlaybackSource) -> some View {
        switch source.kind {
        case .audio:
            AudioPlayerView(
                source: source,
                post: post,
                campaign: campaign,
                resumeSeconds: PlaybackProgressStore.shared.progress(for: currentPostID)?.positionSeconds,
                onPlaybackFailure: { message in
                    presentPlaybackError(message)
                },
                onPlaybackEnded: {
                    Task { await handlePlaybackEnded() }
                }
            )
        case .video:
            PlayerView(
                source: source,
                title: post?.attributes.title ?? "",
                postID: currentPostID,
                resumeSeconds: PlaybackProgressStore.shared.progress(for: currentPostID)?.positionSeconds,
                post: post,
                campaign: campaign,
                duration: videoDuration,
                onPlaybackFailure: { message in
                    presentPlaybackError(message)
                },
                onPlaybackEnded: {
                    Task { await handlePlaybackEnded() }
                }
            )
        }
    }

    @ViewBuilder
    private func loaded(post: Post) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 40) {
                hero(post: post)
                    .padding(.bottom, -40)

                metadataSection(post: post)

                playbackSection(post: post)

                descriptionSection(post: post)

                Spacer(minLength: 60)
            }
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func hero(post: Post) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let heroImageURL {
                    LazyImage(url: heroImageURL) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            heroPlaceholder(post: post)
                        }
                    }
                } else {
                    heroPlaceholder(post: post)
                }
            }
            .frame(height: 640)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [Color.black.opacity(0.9), Color.black.opacity(0.35), Color.clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 640)
            .frame(maxWidth: .infinity)

            // Horizontal scrim: darkens the left ~two-thirds where the title/creator
            // sit so busy thumbnails (e.g. baked-in chapter lists) recede on the right.
            LinearGradient(
                colors: [Color.black.opacity(0.92), Color.black.opacity(0.6), Color.black.opacity(0.15)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 640)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                if post.attributes.isPaid == true {
                    Text("PATRON")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(PatreonColors.brand.opacity(0.95))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                Text(post.attributes.title ?? "Untitled")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)

                if let subtitle = heroSubtitle(post: post) {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 60)
            .frame(maxWidth: 1200, alignment: .leading)
        }
    }

    private func heroPlaceholder(post: Post) -> some View {
        ZStack {
            LinearGradient(
                colors: [PatreonColors.background, PatreonColors.cardSurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: post.attributes.postType.iconName)
                .font(.system(size: 80))
                .foregroundStyle(PatreonColors.tertiaryText)
        }
    }

    @ViewBuilder
    private func metadataSection(post: Post) -> some View {
        HStack(spacing: 24) {
            if let campaign {
                NavigationLink(value: DeepLinkDestination.creator(id: campaign.id)) {
                    Label(campaign.attributes.name ?? "Creator", systemImage: "person.circle.fill")
                        .font(.title3.weight(.medium))
                }
                .buttonStyle(.bordered)
            }

            if let published = formattedPublishedDate(post.attributes.publishedAt) {
                Label(published, systemImage: "calendar")
                    .font(.title3)
                    .foregroundStyle(PatreonColors.secondaryText)
            }

            if let duration = videoDuration, duration > 0 {
                Label(formatTime(duration), systemImage: "clock")
                    .font(.title3)
                    .foregroundStyle(PatreonColors.secondaryText)
            }

            if let likes = post.attributes.likeCount, likes > 0 {
                Label("\(likes)", systemImage: "heart")
                    .font(.title3)
                    .foregroundStyle(PatreonColors.secondaryText)
            }

            if let comments = post.attributes.commentCount, comments > 0 {
                Label("\(comments)", systemImage: "bubble.left")
                    .font(.title3)
                    .foregroundStyle(PatreonColors.secondaryText)
            }
        }
        .padding(.horizontal, 60)
    }

    @ViewBuilder
    private func playbackSection(post: Post) -> some View {
        if playbackSource != nil || mediaURL != nil {
            VStack(alignment: .leading, spacing: 20) {
                if let progress = resumeProgress, progress.durationSeconds > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: progress.positionSeconds / progress.durationSeconds)
                            .tint(PatreonColors.brand)
                        Text("Watched \(formatTime(progress.positionSeconds)) of \(formatTime(progress.durationSeconds))")
                            .font(.subheadline)
                            .foregroundStyle(PatreonColors.secondaryText)
                    }
                }

                HStack(spacing: 16) {
                    Button {
                        Task { await prepareAndPlay() }
                    } label: {
                        Label(playButtonLabel, systemImage: "play.fill")
                            .font(.title3.weight(.semibold))
                            .padding(.horizontal, 48)
                            .padding(.vertical, 20)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PatreonColors.brand)
                    .disabled(isPreparingPlayback)

                    if resumeProgress != nil {
                        Button {
                            PlaybackProgressStore.shared.clear(postID: currentPostID)
                            resumeProgressStamp = UUID()
                            Task { await prepareAndPlay() }
                        } label: {
                            Text("Start Over")
                                .font(.title3.weight(.medium))
                                .padding(.horizontal, 32)
                                .padding(.vertical, 20)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isPreparingPlayback)
                    }
                }

                if isPreparingPlayback {
                    ProgressView("Loading video…")
                }
            }
            .padding(.horizontal, 60)
        } else if post.attributes.currentUserCanView == false {
            lockedNotice
        }
    }

    @ViewBuilder
    private func descriptionSection(post: Post) -> some View {
        if let teaser = post.attributes.teaser, !teaser.isEmpty {
            Text(teaser)
                .font(.title3)
                .foregroundStyle(PatreonColors.secondaryText)
                .padding(.horizontal, 60)
                .frame(maxWidth: 1400, alignment: .leading)
        }

        if let content = post.attributes.content, !content.isEmpty {
            Text(HTMLRenderer.attributedString(from: content))
                .font(.body)
                .foregroundStyle(PatreonColors.primaryText.opacity(0.9))
                .padding(.horizontal, 60)
                .frame(maxWidth: 1400, alignment: .leading)
        }
        // No filler when both teaser and content are empty — many video posts
        // have no description text, and "Video from <creator>" added nothing.
    }

    private func heroSubtitle(post: Post) -> String? {
        var parts: [String] = []
        if let name = campaign?.attributes.name {
            parts.append(name)
        }
        if let type = postTypeLabel(post.attributes.postType) {
            parts.append(type)
        }
        if let duration = videoDuration, duration > 0 {
            parts.append(formatTime(duration))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func postTypeLabel(_ type: Post.PostType?) -> String? {
        switch type {
        case .videoExternalFile, .videoEmbed: "Video"
        case .audioFile, .audioEmbed, .podcast: "Audio"
        case .imageFile: "Image"
        case .textOnly: "Post"
        case .link: "Link"
        case .poll: "Poll"
        case .livestreamYoutube, .livestreamCrowdcast: "Livestream"
        case .other, nil: nil
        }
    }

    private func formattedPublishedDate(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return nil
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private var resumeProgress: PlaybackProgress? {
        _ = resumeProgressStamp
        guard let p = PlaybackProgressStore.shared.progress(for: currentPostID),
              !p.isFinished,
              p.positionSeconds > 5
        else { return nil }
        return p
    }

    private var playButtonLabel: String {
        if let p = resumeProgress {
            return "Resume from \(formatTime(p.positionSeconds))"
        }
        return "Play"
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    private var lockedNotice: some View {
        HStack(spacing: 16) {
            Image(systemName: "lock.fill")
            Text("This post is only available to patrons at a higher tier.")
        }
        .font(.title3)
        .foregroundStyle(PatreonColors.secondaryText)
        .padding(.horizontal, 60)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let doc = try await PatreonClient.shared.post(id: currentPostID)
            apply(document: doc)
        } catch {
            errorMessage = (error as? PatreonError)?.errorDescription
                ?? error.localizedDescription
        }
        isLoading = false

        // Honor the autoplay flag from Top Shelf / deep links / featured Play,
        // exactly once per presentation.
        if autoplay, !didAutoplay, post != nil, mediaURL != nil {
            didAutoplay = true
            await prepareAndPlay()
        }
    }

    private func apply(document doc: SingleResource<Post>) {
        post = doc.data
        mediaURL = MediaPlaybackResolver.resolve(from: doc)?.url

        var resolvedCampaign: Campaign?
        var resolvedDuration: Double?
        var resolvedHero: URL?

        for inc in doc.included ?? [] {
            switch inc {
            case .campaign(let c):
                resolvedCampaign = c
            case .media(let m):
                if resolvedDuration == nil {
                    resolvedDuration = m.attributes.display?.duration
                }
                if resolvedHero == nil {
                    resolvedHero = m.attributes.display?.defaultThumbnail?.url
                }
            default:
                break
            }
        }

        campaign = resolvedCampaign
        videoDuration = resolvedDuration
        heroImageURL = resolvedHero
            ?? doc.data.attributes.posterImageURL
    }

    // MARK: - Up Next

    /// Playback finished: queue the creator's next post if one exists,
    /// otherwise just close the player.
    private func handlePlaybackEnded() async {
        resumeProgressStamp = UUID()   // finished — re-read progress
        guard let campaignID = campaign?.id,
              let next = await UpNextResolver.next(after: currentPostID, campaignID: campaignID)
        else {
            playbackSource = nil
            return
        }
        upNext = next
    }

    /// Advance to the queued post: swap the detail view's subject and start
    /// playback with a freshly fetched URL (Mux tokens are ephemeral).
    private func playNext(_ next: Post) async {
        upNext = nil
        currentPostID = next.id
        post = next            // provisional; prepareAndPlay refreshes the full doc
        heroImageURL = next.attributes.posterImageURL
        videoDuration = nil
        resumeProgressStamp = UUID()

        await prepareAndPlay()
    }

    /// Surface a playback error via the alert. If the player cover is still on
    /// screen, dismiss it first and defer the alert to the cover's `onDismiss`
    /// — presenting an alert over a live full-screen cover is rejected by UIKit.
    private func presentPlaybackError(_ message: String) {
        if playbackSource != nil {
            pendingPlaybackError = message
            playbackSource = nil
        } else {
            playbackErrorMessage = message
        }
    }

    /// Re-fetch post on play so Mux HLS tokens are fresh (~24h expiry).
    private func prepareAndPlay() async {
        isPreparingPlayback = true
        defer { isPreparingPlayback = false }

        do {
            let doc = try await PatreonClient.shared.post(id: currentPostID)
            apply(document: doc)
            guard let source = MediaPlaybackResolver.resolve(from: doc) else {
                // The detail view is still showing (post != nil), so surface
                // this via the playback alert rather than errorMessage, which
                // only renders when the whole page failed to load.
                presentPlaybackError("No playable media URL was returned for this post.")
                mediaURL = nil
                return
            }
            mediaURL = source.url
            log.info("Starting playback host=\(source.url.host() ?? "?") ext=\(source.url.pathExtension)")
            playbackSource = source
        } catch {
            presentPlaybackError(
                (error as? PatreonError)?.errorDescription ?? error.localizedDescription
            )
        }
    }
}
