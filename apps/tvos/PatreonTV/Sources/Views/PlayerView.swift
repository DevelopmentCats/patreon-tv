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

    var mediaURL: URL { source.url }

    func makeCoordinator() -> Coordinator {
        Coordinator(postID: postID)
    }

    func makeUIViewController(context: Context) -> PlayerHostViewController {
        let host = PlayerHostViewController()
        host.configure(
            source: source,
            title: title,
            resumeSeconds: resumeSeconds,
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
        private var timeObserver: Any?
        private var statusObserver: NSKeyValueObservation?
        private weak var player: AVPlayer?
        private let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "Player")

        init(postID: String) {
            self.postID = postID
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
                    default:
                        break
                    }
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
        coordinator: PlayerView.Coordinator
    ) {
        guard !didConfigure else { return }
        didConfigure = true

        var headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 PatreonTV/0.1",
            "Referer": "https://www.patreon.com/",
        ]
        if let sessionID = PatreonClient.shared.sessionID {
            headers["Cookie"] = "session_id=\(sessionID)"
        }

        // Both Mux and Patreon media URLs are self-signed with an expiring token,
        // so a plain asset streams them directly and AVFoundation handles its own
        // efficient byte-range fetching. The header fields are applied to the
        // initial request only, as harmless insurance (User-Agent / Referer).
        log.info("Direct playback for \(source.url.absoluteString.prefix(120))")
        let asset = AVURLAsset(url: source.url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": headers,
        ])

        let item = AVPlayerItem(asset: asset)
        item.externalMetadata = [makeMetadataItem(identifier: .commonIdentifierTitle, value: title)]

        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        playerViewController.player = player
        playerViewController.allowsPictureInPicturePlayback = true
        playerViewController.videoGravity = .resizeAspect

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

    private func makeMetadataItem(identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }
}
