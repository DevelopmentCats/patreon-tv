//
//  AudioPlayerModel.swift
//  PatreonTV
//
//  Playback engine for AudioPlayerView. Owns the AVPlayer, publishes
//  time/state for the UI, persists progress via PlaybackProgressStore, and
//  wires Now Playing info + remote commands so the Siri Remote play/pause
//  button and the system audio HUD work.
//

import AVFoundation
import Foundation
import MediaPlayer
import Observation
import UIKit
import os.log

@MainActor
@Observable
final class AudioPlayerModel {

    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var preferredRate: Float = 1.0

    /// Set by the presenter before `start`. Same contract as PlayerView.
    var onEnded: (() -> Void)?
    var onFailure: ((String) -> Void)?

    private let postID: String
    private let title: String
    private let creator: String?
    private let artworkURL: URL?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var artwork: MPMediaItemArtwork?

    private let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "AudioPlayer")

    init(postID: String, title: String, creator: String?, artworkURL: URL?) {
        self.postID = postID
        self.title = title
        self.creator = creator
        self.artworkURL = artworkURL
    }

    // MARK: - Lifecycle

    func start(url: URL, resumeAt: Double?) {
        guard player == nil else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            log.error("Audio session activation failed: \(String(describing: error))")
        }

        // Same rule as video: the URL is self-signed, no cookies attached.
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        let player = AVPlayer(playerItem: item)
        self.player = player

        observe(player: player, item: item)
        configureRemoteCommands()
        loadArtwork()

        if let resumeAt, resumeAt > 5 {
            let target = CMTime(seconds: resumeAt, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .positiveInfinity) { [weak self] _ in
                Task { @MainActor in self?.play() }
            }
        } else {
            play()
        }
    }

    func teardown() {
        recordProgress()
        statusObserver?.invalidate()
        statusObserver = nil
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        for (command, target) in commandTargets {
            command.removeTarget(target)
        }
        commandTargets = []
        player?.pause()
        player = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Transport

    func play() {
        guard let player else { return }
        player.playImmediately(atRate: preferredRate)
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        recordProgress()
        updateNowPlaying()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func skip(_ seconds: Double) {
        guard let player else { return }
        let target = max(0, min(currentTime + seconds, duration > 0 ? duration - 1 : .greatestFiniteMagnitude))
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor in self?.updateNowPlaying() }
        }
        currentTime = target
    }

    func setRate(_ rate: Float) {
        preferredRate = rate
        if isPlaying {
            player?.rate = rate
        }
        updateNowPlaying()
    }

    // MARK: - Observation

    private func observe(player: AVPlayer, item: AVPlayerItem) {
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    let seconds = item.duration.seconds
                    if seconds.isFinite, seconds > 0 { self.duration = seconds }
                    self.updateNowPlaying()
                case .failed:
                    self.log.error("Audio failed for post \(self.postID): \(String(describing: item.error))")
                    self.onFailure?(
                        item.error?.localizedDescription
                            ?? "The audio stopped playing. Its link may have expired — try again."
                    )
                default:
                    break
                }
            }
        }

        // Keep isPlaying honest when the system pauses us (route change, etc).
        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self else { return }
            Task { @MainActor in
                self.isPlaying = player.timeControlStatus != .paused
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = false
                self.markFinished()
                self.onEnded?()
            }
        }

        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            MainActor.assumeIsolated {
                let seconds = time.seconds
                guard seconds.isFinite else { return }
                self.currentTime = seconds
                if let itemDuration = self.player?.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
                // Persist every ~5s, matching the video player's cadence.
                if Int(seconds) % 5 == 0 {
                    self.recordProgress()
                }
            }
        }
    }

    // MARK: - Progress

    private func recordProgress() {
        guard currentTime.isFinite, duration.isFinite, duration > 0 else { return }
        PlaybackProgressStore.shared.record(PlaybackProgress(
            postID: postID,
            positionSeconds: currentTime,
            durationSeconds: duration,
            lastUpdated: Date()
        ))
    }

    private func markFinished() {
        guard duration.isFinite, duration > 0 else { return }
        PlaybackProgressStore.shared.record(PlaybackProgress(
            postID: postID,
            positionSeconds: duration,
            durationSeconds: duration,
            lastUpdated: Date()
        ))
    }

    // MARK: - Now Playing / remote commands

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        func register(_ command: MPRemoteCommand, _ handler: @escaping @MainActor () -> Void) {
            command.isEnabled = true
            let target = command.addTarget { _ in
                MainActor.assumeIsolated { handler() }
                return .success
            }
            commandTargets.append((command, target))
        }

        register(center.playCommand) { [weak self] in self?.play() }
        register(center.pauseCommand) { [weak self] in self?.pause() }
        register(center.togglePlayPauseCommand) { [weak self] in self?.togglePlayPause() }

        center.skipBackwardCommand.preferredIntervals = [15]
        register(center.skipBackwardCommand) { [weak self] in self?.skip(-15) }
        center.skipForwardCommand.preferredIntervals = [30]
        register(center.skipForwardCommand) { [weak self] in self?.skip(30) }
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(preferredRate) : 0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let creator {
            info[MPMediaItemPropertyArtist] = creator
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork() {
        guard let artworkURL else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: artworkURL),
                  let image = UIImage(data: data),
                  let self
            else { return }
            self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.updateNowPlaying()
        }
    }
}
