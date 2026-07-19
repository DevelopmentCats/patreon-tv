//
//  PlayerView.swift
//  PatreonTV
//
//  Full-screen native AVPlayerViewController for tvOS. Handles Mux HLS,
//  Patreon-hosted MP4, and any AVPlayer-compatible URL.
//

import AVKit
import SwiftUI
import os.log

struct PlayerView: UIViewControllerRepresentable {

    let source: MediaPlaybackSource
    let title: String
    let postID: String
    let resumeSeconds: Double?
    /// Optional context for the info panel, chapter markers, and richer
    /// swipe-down metadata. Playback works without them.
    var post: Post? = nil
    var campaign: Campaign? = nil
    var duration: Double? = nil
    /// Called on the main actor when the player item fails (e.g. an expired
    /// Mux token after pausing overnight). The presenter should dismiss the
    /// player and offer a retry, which re-fetches a fresh URL.
    var onPlaybackFailure: ((String) -> Void)? = nil
    /// Called on the main actor when the item plays to its end. The presenter
    /// can show an Up Next overlay or dismiss the player.
    var onPlaybackEnded: (() -> Void)? = nil

    var mediaURL: URL { source.url }

    func makeCoordinator() -> Coordinator {
        Coordinator(postID: postID, onFailure: onPlaybackFailure, onEnded: onPlaybackEnded)
    }

    func makeUIViewController(context: Context) -> PlayerHostViewController {
        let host = PlayerHostViewController()
        host.configure(
            source: source,
            title: title,
            resumeSeconds: resumeSeconds,
            post: post,
            campaign: campaign,
            duration: duration,
            coordinator: context.coordinator
        )
        return host
    }

    func updateUIViewController(_ host: PlayerHostViewController, context: Context) {}

    static func dismantleUIViewController(_ host: PlayerHostViewController, coordinator: Coordinator) {
        coordinator.detach()
        host.playerViewController.player?.pause()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        let postID: String
        private let onFailure: ((String) -> Void)?
        private let onEnded: (() -> Void)?
        private var timeObserver: Any?
        private var statusObserver: NSKeyValueObservation?
        private var endObserver: NSObjectProtocol?
        private weak var player: AVPlayer?
        private let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "Player")

        init(postID: String, onFailure: ((String) -> Void)? = nil, onEnded: (() -> Void)? = nil) {
            self.postID = postID
            self.onFailure = onFailure
            self.onEnded = onEnded
        }

        func attach(player: AVPlayer, item: AVPlayerItem) {
            self.player = player

            statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard let self else { return }
                Task { @MainActor in
                    switch item.status {
                    case .readyToPlay:
                        self.log.info("Player ready for post \(self.postID)")
                    case .failed:
                        self.log.error(
                            "Player failed for post \(self.postID): \(String(describing: item.error))"
                        )
                        // Media URLs are token-signed with ~24h expiry, so a
                        // long pause can kill the stream. Surface it instead of
                        // leaving a silent black screen.
                        self.onFailure?(
                            item.error?.localizedDescription
                                ?? "The video stopped playing. Its link may have expired — try again."
                        )
                    default:
                        break
                    }
                }
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: item,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.log.info("Playback finished for post \(self.postID)")
                    self.markFinished()
                    self.onEnded?()
                }
            }

            let interval = CMTime(seconds: 5, preferredTimescale: 600)
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: interval,
                queue: .main
            ) { [weak self, weak player] time in
                guard let self, let player else { return }
                MainActor.assumeIsolated {
                    self.recordProgress(player: player, time: time)
                }
            }
        }

        func detach() {
            statusObserver?.invalidate()
            statusObserver = nil
            if let obs = endObserver {
                NotificationCenter.default.removeObserver(obs)
                endObserver = nil
            }
            if let obs = timeObserver {
                player?.removeTimeObserver(obs)
                timeObserver = nil
            }
            if let player {
                let position = player.currentTime().seconds
                let duration = player.currentItem?.duration.seconds ?? 0
                if position.isFinite, duration.isFinite, duration > 0 {
                    PlaybackProgressStore.shared.record(PlaybackProgress(
                        postID: postID,
                        positionSeconds: position,
                        durationSeconds: duration,
                        lastUpdated: Date()
                    ))
                }
            }
        }

        /// Record the post at 100% so it counts as finished and drops out of
        /// Continue Watching.
        private func markFinished() {
            guard let duration = player?.currentItem?.duration.seconds,
                  duration.isFinite, duration > 0
            else { return }
            PlaybackProgressStore.shared.record(PlaybackProgress(
                postID: postID,
                positionSeconds: duration,
                durationSeconds: duration,
                lastUpdated: Date()
            ))
        }

        private func recordProgress(player: AVPlayer, time: CMTime) {
            let position = time.seconds
            let duration = player.currentItem?.duration.seconds ?? 0
            guard position.isFinite, duration.isFinite, duration > 0 else { return }
            PlaybackProgressStore.shared.record(PlaybackProgress(
                postID: postID,
                positionSeconds: position,
                durationSeconds: duration,
                lastUpdated: Date()
            ))
        }
    }
}

// MARK: - Host view controller

/// Embeds `AVPlayerViewController` edge-to-edge. SwiftUI `fullScreenCover` +
/// bare `AVPlayerViewController` often lays out at zero width on tvOS.
@MainActor
final class PlayerHostViewController: UIViewController {

    let playerViewController = AVPlayerViewController()
    private var didConfigure = false
    private let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "Player")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        addChild(playerViewController)
        playerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playerViewController.view)
        NSLayoutConstraint.activate([
            playerViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            playerViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        playerViewController.didMove(toParent: self)
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [playerViewController]
    }

    func configure(
        source: MediaPlaybackSource,
        title: String,
        resumeSeconds: Double?,
        post: Post? = nil,
        campaign: Campaign? = nil,
        duration: Double? = nil,
        coordinator: PlayerView.Coordinator
    ) {
        guard !didConfigure else { return }
        didConfigure = true

        // Both Mux and Patreon media URLs are self-signed with an expiring token
        // in the query string, so a plain asset streams them directly and
        // AVFoundation handles its own efficient byte-range fetching.
        //
        // Mux enforces a *playback restriction* on these assets: a valid,
        // unexpired signed token still 403s unless the request carries a
        // patreon.com Referer/Origin and a browser User-Agent (the old WebView
        // player sent these automatically; native AVPlayer sends none, which
        // silently broke video playback). We still send NO cookie — the session
        // credential must never reach a third-party CDN.
        log.info("Direct playback for \(source.url.absoluteString.prefix(120))")
        let playbackHeaders = [
            "Referer": "https://www.patreon.com/",
            "Origin": "https://www.patreon.com",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
        ]
        let asset = AVURLAsset(
            url: source.url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": playbackHeaders]
        )

        let item = AVPlayerItem(asset: asset)
        item.externalMetadata = makeExternalMetadata(title: title, post: post, campaign: campaign)
        attachArtworkIfAvailable(to: item, post: post)
        attachChapterMarkers(to: item, post: post, duration: duration)

        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        playerViewController.player = player
        playerViewController.allowsPictureInPicturePlayback = true
        playerViewController.videoGravity = .resizeAspect

        configureInfoPanel(post: post, campaign: campaign)

        coordinator.attach(player: player, item: item)

        if let resume = resumeSeconds, resume > 5 {
            let target = CMTime(seconds: resume, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.positiveInfinity) { _ in
                player.play()
            }
        } else {
            player.play()
        }
    }

    // MARK: - Metadata (powers the native swipe-down info panel)

    private func makeExternalMetadata(title: String, post: Post?, campaign: Campaign?) -> [AVMetadataItem] {
        var items = [makeMetadataItem(identifier: .commonIdentifierTitle, value: title)]

        if let creator = campaign?.attributes.name, !creator.isEmpty {
            items.append(makeMetadataItem(identifier: .commonIdentifierArtist, value: creator))
            items.append(makeMetadataItem(identifier: .iTunesMetadataTrackSubTitle, value: creator))
        }

        if let description = playerDescription(for: post) {
            items.append(makeMetadataItem(identifier: .commonIdentifierDescription, value: description))
        }

        return items
    }

    /// Plain-text description for the info panel: teaser preferred (short and
    /// hand-written), else the post body stripped of HTML, capped so AVKit
    /// doesn't choke on essay-length values.
    private func playerDescription(for post: Post?) -> String? {
        guard let post else { return nil }
        let raw = [post.attributes.teaser, post.attributes.content]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        guard let raw else { return nil }
        let text = HTMLRenderer.stripToPlainText(raw)
        guard !text.isEmpty else { return nil }
        return text.count > 600 ? String(text.prefix(600)) + "…" : text
    }

    /// Fetch the poster asynchronously and append it as artwork metadata; the
    /// info panel shows it beside the title. Best-effort — never blocks playback.
    private func attachArtworkIfAvailable(to item: AVPlayerItem, post: Post?) {
        guard let url = post?.attributes.posterImageURL else { return }
        Task { [weak item] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let item
            else { return }
            let artwork = AVMutableMetadataItem()
            artwork.identifier = .commonIdentifierArtwork
            artwork.value = data as NSData
            artwork.dataType = kCMMetadataBaseDataType_JPEG as String
            artwork.extendedLanguageTag = "und"
            item.externalMetadata.append(artwork.copy() as! AVMetadataItem)
        }
    }

    // MARK: - Chapters

    /// Patreon has no chapter API, so we mine the description for a timestamp
    /// list and surface it as native navigation markers (transport-bar chapter
    /// skipping + the Chapters info tab).
    private func attachChapterMarkers(to item: AVPlayerItem, post: Post?, duration: Double?) {
        guard let html = post?.attributes.content else { return }
        let chapters = ChapterParser.chapters(fromHTML: html, duration: duration)
        guard !chapters.isEmpty else { return }

        log.info("Parsed \(chapters.count) chapters from post content")

        var groups: [AVTimedMetadataGroup] = []
        for (index, chapter) in chapters.enumerated() {
            let start = CMTime(seconds: chapter.startSeconds, preferredTimescale: 600)
            let endSeconds = index + 1 < chapters.count
                ? chapters[index + 1].startSeconds
                : (duration ?? chapter.startSeconds + 3600)
            let end = CMTime(seconds: max(endSeconds, chapter.startSeconds + 1), preferredTimescale: 600)
            let titleItem = makeMetadataItem(identifier: .commonIdentifierTitle, value: chapter.title)
            groups.append(AVTimedMetadataGroup(
                items: [titleItem],
                timeRange: CMTimeRange(start: start, end: end)
            ))
        }
        item.navigationMarkerGroups = [
            AVNavigationMarkersGroup(title: "Chapters", timedNavigationMarkers: groups)
        ]
    }

    // MARK: - Custom info panel

    /// "Details" tab in the swipe-down panel: full description without leaving
    /// playback.
    private func configureInfoPanel(post: Post?, campaign: Campaign?) {
        guard let post else { return }
        let details = UIHostingController(rootView: PlayerInfoView(post: post, campaign: campaign))
        details.title = "Details"
        playerViewController.customInfoViewControllers = [details]
    }

    private func makeMetadataItem(identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }
}
