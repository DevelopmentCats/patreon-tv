//
//  PlayerView.swift
//  PatreonTV
//
//  Full-screen native AVPlayerViewController for tvOS. Handles Mux HLS,
//  Patreon-hosted MP4, and any AVPlayer-compatible URL.
//
//  Reports playback position to PlaybackProgressStore so Continue Watching
//  works across launches.
//
//  tvOS design rules honored:
//  - MEDIA-01: standard transport controls via AVPlayerViewController.
//  - MEDIA-02: info overlay on swipe-down — automatic.
//  - MEDIA-03: touch-surface scrubbing — automatic.
//  - MEDIA-04: subtitle/audio track selection — automatic with HLS.
//  - MEDIA-05: PiP where appropriate — enabled by default.
//  - MEDIA-06: playback position — persisted via PlaybackProgressStore.
//  - MEDIA-07: interruptions — AVPlayerViewController handles cleanly.
//

import AVKit
import SwiftUI
import os.log

struct PlayerView: UIViewControllerRepresentable {

    let mediaURL: URL
    let title: String
    let postID: String
    /// Optional resume point in seconds. If provided, we seek before playing.
    let resumeSeconds: Double?

    func makeCoordinator() -> Coordinator {
        Coordinator(postID: postID)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()

        let asset = AVURLAsset(url: mediaURL, options: [
            "AVURLAssetHTTPUserAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 PatreonTV/0.1",
        ])
        let item = AVPlayerItem(asset: asset)

        var externalMetadata: [AVMetadataItem] = []
        externalMetadata.append(makeMetadataItem(identifier: .commonIdentifierTitle, value: title))
        item.externalMetadata = externalMetadata

        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.videoGravity = .resizeAspect

        if let resume = resumeSeconds, resume > 5 {
            let target = CMTime(seconds: resume, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
        }

        context.coordinator.attach(player: player)
        player.play()
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.detach()
        vc.player?.pause()
    }

    private func makeMetadataItem(identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        let postID: String
        private var timeObserver: Any?
        private weak var player: AVPlayer?
        private let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "Player")

        init(postID: String) {
            self.postID = postID
        }

        func attach(player: AVPlayer) {
            self.player = player
            // Sample every 5 seconds — enough for Continue Watching accuracy,
            // negligible CPU/battery.
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
            if let obs = timeObserver {
                player?.removeTimeObserver(obs)
                timeObserver = nil
            }
            // Record final position on dismiss.
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
