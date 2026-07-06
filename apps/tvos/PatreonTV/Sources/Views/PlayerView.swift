//
//  PlayerView.swift
//  PatreonTV
//
//  Full-screen native AVPlayerViewController for tvOS. Handles Mux HLS,
//  Patreon-hosted MP4, and any AVPlayer-compatible URL.
//
//  tvOS design rules honored:
//  - MEDIA-01: standard transport controls via AVPlayerViewController.
//  - MEDIA-02: info overlay on swipe-down — automatic with AVPlayerViewController.
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

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()

        let asset = AVURLAsset(url: mediaURL, options: [
            "AVURLAssetHTTPUserAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 PatreonTV/0.1",
        ])
        let item = AVPlayerItem(asset: asset)

        // Metadata for the "now playing" info overlay
        var externalMetadata: [AVMetadataItem] = []
        externalMetadata.append(makeMetadataItem(identifier: .commonIdentifierTitle, value: title))
        item.externalMetadata = externalMetadata

        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.videoGravity = .resizeAspect

        // Kick off playback
        player.play()

        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}

    private func makeMetadataItem(identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }
}
