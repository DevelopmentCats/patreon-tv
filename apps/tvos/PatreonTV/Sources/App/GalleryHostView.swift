//
//  GalleryHostView.swift
//  PatreonTV
//
//  A "Storybook"-style launch mode for capturing each screen with real data.
//  Activated by environment variables (passed via SIMCTL_CHILD_* by
//  scripts/capture-screens.sh). To match the running app, screens render inside
//  the real HomeShell (tab bar + navigation) — we just pre-select the tab and
//  push detail screens via the deep-link router.
//
//  Env vars:
//    GALLERY_SCREEN      signin | sessionExpired | pairing | home | creators | search | settings | postDetail | creator | player | audioPlayer | upnext
//    PATREON_SESSION_ID  session_id cookie to authenticate with
//    GALLERY_MATURE      "1" to show mature content
//    GALLERY_QUERY       seed term for the search screen
//    GALLERY_POST_ID     optional explicit post id for postDetail / player
//    GALLERY_CAMPAIGN_ID optional explicit campaign id for creator
//

import SwiftUI

enum GalleryConfig {
    private static var env: [String: String] { ProcessInfo.processInfo.environment }
    static var screen: String? { env["GALLERY_SCREEN"] }
    static var sessionID: String? { env["PATREON_SESSION_ID"] }
    static var postID: String? { env["GALLERY_POST_ID"] }
    static var campaignID: String? { env["GALLERY_CAMPAIGN_ID"] }
    static var query: String? { env["GALLERY_QUERY"] }
    static var mature: Bool { env["GALLERY_MATURE"] == "1" }
    static var isActive: Bool { screen?.isEmpty == false }
}

#if DEBUG
struct GalleryHostView: View {

    @Environment(AuthStore.self) private var auth
    @Environment(DeepLinkRouter.self) private var router

    private enum Phase: Equatable { case loading, ready, failed(String) }
    @State private var phase: Phase = .loading
    @State private var deepLink: DeepLinkRouter.Destination?
    @State private var playerSource: MediaPlaybackSource?
    @State private var playerTitle: String = ""
    @State private var playerPostID: String = ""
    @State private var playerPost: Post?
    @State private var playerCampaign: Campaign?
    @State private var upNextPost: Post?

    var body: some View {
        Group {
            switch phase {
            case .loading:
                message("Loading gallery…", systemImage: nil)
            case .failed(let text):
                message(text, systemImage: "exclamationmark.triangle")
            case .ready:
                screen
            }
        }
        .task { await setup() }
    }

    @ViewBuilder
    private var screen: some View {
        switch GalleryConfig.screen {
        case "signin":
            SignInView()
        case "sessionExpired":
            SignInView(sessionExpired: true)
        case "pairing":
            // Live pairing panel — Debug builds point PairingConfig at the
            // local wrangler dev server, so the code + QR are real.
            PatreonPairingSignInView(onSessionIDCaptured: { _ in }, onDismiss: {})
        case "player":
            if let playerSource {
                PlayerView(source: playerSource, title: playerTitle, postID: playerPostID, resumeSeconds: nil)
                    .ignoresSafeArea()
            } else {
                message("Gallery: no playable media", systemImage: "exclamationmark.triangle")
            }
        case "audioPlayer":
            if let playerSource {
                AudioPlayerView(
                    source: playerSource,
                    post: playerPost,
                    campaign: playerCampaign,
                    resumeSeconds: nil
                )
            } else {
                message("Gallery: no audio post found", systemImage: "exclamationmark.triangle")
            }
        case "upnext":
            // Static render of the Up Next overlay over a black "player".
            if let upNextPost {
                ZStack {
                    Color.black.ignoresSafeArea()
                    UpNextOverlayView(
                        post: upNextPost,
                        creatorName: playerCampaign?.attributes.name,
                        countdownSeconds: 10,
                        onPlay: {},
                        onDismiss: {}
                    )
                }
            } else {
                message("Gallery: no post for up-next", systemImage: "exclamationmark.triangle")
            }
        default:
            // Home / Creators / Search / Settings and pushed detail screens all
            // render inside the real shell so the capture includes the tab bar.
            HomeShell()
        }
    }

    private func message(_ text: String, systemImage: String?) -> some View {
        VStack(spacing: 16) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 60)).foregroundStyle(.orange)
            }
            Text(text).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PatreonColors.background.ignoresSafeArea())
    }

    private func setup() async {
        ContentPreferences.shared.showMatureContent = GalleryConfig.mature
        let screen = GalleryConfig.screen ?? ""

        if !["signin", "sessionExpired"].contains(screen), let sid = GalleryConfig.sessionID, !sid.isEmpty {
            await auth.completeSignIn(sessionID: sid)
        }

        // Pre-select the shell tab (detail screens live under the Home tab).
        let tab: String
        switch screen {
        case "creators": tab = "creators"
        case "search":   tab = "search"
        case "settings": tab = "settings"
        default:         tab = "home"
        }
        UserDefaults.standard.set(tab, forKey: "selected_tab")

        do {
            switch screen {
            case "player":
                try await resolvePlayer()
            case "audioPlayer":
                try await resolveAudioPlayer()
            case "upnext":
                try await resolveUpNext()
            case "creator":
                if let explicit = GalleryConfig.campaignID {
                    deepLink = .creator(id: explicit)
                } else if let id = try await firstCurrentCampaignID() {
                    deepLink = .creator(id: id)
                }
            case "postDetail":
                if let explicit = GalleryConfig.postID {
                    deepLink = .post(id: explicit, autoplay: false)
                } else if let id = try await PatreonClient.shared.homeFeed(limit: 5).data.first?.id {
                    deepLink = .post(id: id, autoplay: false)
                }
            default:
                break
            }
            phase = .ready
        } catch {
            phase = .failed("Gallery setup failed: \(error.localizedDescription)")
        }

        // After the shell mounts, push the detail screen via the router.
        if let deepLink {
            try? await Task.sleep(for: .milliseconds(500))
            router.pending = deepLink
        }
    }

    private func firstCurrentCampaignID() async throws -> String? {
        let doc = try await PatreonClient.shared.members()
        for member in doc.data where member.isCurrentRelationship {
            if let cid = member.relationships?.campaign?.data?.id { return cid }
        }
        return nil
    }

    /// Resolve a playable post into a MediaPlaybackSource for the player screen.
    private func resolvePlayer() async throws {
        let candidateID: String?
        if let explicit = GalleryConfig.postID {
            candidateID = explicit
        } else {
            candidateID = try await PatreonClient.shared.homeFeed(limit: 20).data.first?.id
        }
        guard let id = candidateID else { return }
        let doc = try await PatreonClient.shared.post(id: id)
        guard let source = MediaPlaybackResolver.resolve(from: doc) else { return }
        playerSource = source
        playerPostID = id
        playerPost = doc.data
        playerCampaign = firstCampaign(in: doc.included)
        playerTitle = doc.data.attributes.title ?? "Playing"
    }

    /// Find an audio post (explicit id, or the first audio-typed feed post)
    /// and resolve it for the AudioPlayerView screen. Falls back to a mock
    /// post so the screen can be captured without a live session.
    private func resolveAudioPlayer() async throws {
        let audioTypes: Set<Post.PostType> = [.audioFile, .audioEmbed, .podcast]
        let candidateID: String?
        if let explicit = GalleryConfig.postID {
            candidateID = explicit
        } else {
            candidateID = try? await PatreonClient.shared.homeFeed(limit: 30).data
                .first { $0.attributes.postType.map(audioTypes.contains) == true }?.id
        }
        if let id = candidateID {
            let doc = try await PatreonClient.shared.post(id: id)
            if let source = MediaPlaybackResolver.resolve(from: doc) {
                playerSource = source
                playerPostID = id
                playerPost = doc.data
                playerCampaign = firstCampaign(in: doc.included)
                playerTitle = doc.data.attributes.title ?? "Playing"
                return
            }
        }
        playerPost = Self.mockPost(type: "podcast", title: "Episode 42 — The Long Answer")
        playerSource = MediaPlaybackSource(
            url: URL(string: "https://example.com/mock-episode.mp3")!,
            kind: .audio
        )
    }

    /// Grab any two feed posts: the second becomes the "up next" suggestion.
    /// Falls back to a mock post for capture without a live session.
    private func resolveUpNext() async throws {
        if let posts = try? await PatreonClient.shared.homeFeed(limit: 10), !posts.data.isEmpty {
            upNextPost = posts.data.dropFirst().first ?? posts.data.first
            if let cid = upNextPost?.relationships?.campaign?.data?.id {
                playerCampaign = firstCampaign(in: posts.included, id: cid)
            }
            return
        }
        upNextPost = Self.mockPost(type: "video_external_file", title: "The Next Episode You Haven't Seen")
    }

    /// Minimal decoded Post for gallery captures without a session.
    private static func mockPost(type: String, title: String) -> Post? {
        let json = """
        {
          "data": {
            "type": "post", "id": "gallery-mock",
            "attributes": {
              "title": "\(title)",
              "post_type": "\(type)",
              "published_at": "2026-07-01T12:00:00.000+00:00",
              "current_user_can_view": true
            }
          }
        }
        """.data(using: .utf8)!
        return try? JSONAPIDecoder.decode(SingleResource<Post>.self, from: json).data
    }

    private func firstCampaign(in included: [Included]?, id: String? = nil) -> Campaign? {
        for inc in included ?? [] {
            if case .campaign(let c) = inc, id == nil || c.id == id {
                return c
            }
        }
        return nil
    }
}
#endif
