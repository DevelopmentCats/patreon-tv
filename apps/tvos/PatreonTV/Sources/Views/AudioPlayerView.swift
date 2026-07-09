//
//  AudioPlayerView.swift
//  PatreonTV
//
//  Full-screen now-playing UI for audio posts (podcasts, audio files). The
//  native AVPlayerViewController is video-shaped — a black rectangle for
//  audio — so this screen gives artwork, transport controls, skip buttons,
//  and playback speed instead.
//
//  tvOS rules honored: transport controls in a .focusSection() row, every
//  icon button labeled, Menu/back dismisses (no focus traps), play/pause on
//  the Siri Remote works via .onPlayPauseCommand + remote commands.
//

import NukeUI
import SwiftUI

struct AudioPlayerView: View {

    let source: MediaPlaybackSource
    let post: Post?
    let campaign: Campaign?
    let resumeSeconds: Double?
    var onPlaybackFailure: ((String) -> Void)? = nil
    var onPlaybackEnded: (() -> Void)? = nil

    @State private var model: AudioPlayerModel
    @FocusState private var focusedControl: Control?

    private enum Control: Hashable {
        case skipBack, playPause, skipForward, speed
    }

    private static let rates: [Float] = [1.0, 1.25, 1.5, 2.0]

    init(
        source: MediaPlaybackSource,
        post: Post?,
        campaign: Campaign?,
        resumeSeconds: Double?,
        onPlaybackFailure: ((String) -> Void)? = nil,
        onPlaybackEnded: (() -> Void)? = nil
    ) {
        self.source = source
        self.post = post
        self.campaign = campaign
        self.resumeSeconds = resumeSeconds
        self.onPlaybackFailure = onPlaybackFailure
        self.onPlaybackEnded = onPlaybackEnded
        _model = State(initialValue: AudioPlayerModel(
            postID: post?.id ?? "",
            title: post?.attributes.title ?? "Audio",
            creator: campaign?.attributes.name,
            artworkURL: post?.attributes.posterImageURL
        ))
    }

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 36) {
                Spacer()

                artwork

                VStack(spacing: 10) {
                    Text(post?.attributes.title ?? "Audio")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if let creator = campaign?.attributes.name {
                        Text(creator)
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 1100)

                progressBar

                transport

                Spacer()
            }
            .padding(.horizontal, 120)
        }
        .task {
            model.onFailure = onPlaybackFailure
            model.onEnded = onPlaybackEnded
            model.start(url: source.url, resumeAt: resumeSeconds)
        }
        .onDisappear { model.teardown() }
        .onPlayPauseCommand { model.togglePlayPause() }
        .defaultFocus($focusedControl, .playPause)
    }

    // MARK: - Pieces

    private var backdrop: some View {
        ZStack {
            Color.black
            if let url = post?.attributes.posterImageURL {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
                .blur(radius: 80)
                .opacity(0.35)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var artwork: some View {
        LazyImage(url: post?.attributes.posterImageURL) { state in
            if let image = state.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    PatreonColors.cardSurface
                    Image(systemName: "waveform")
                        .font(.system(size: 100))
                        .foregroundStyle(PatreonColors.tertiaryText)
                }
            }
        }
        .frame(width: 420, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
        .accessibilityHidden(true)
    }

    private var progressBar: some View {
        VStack(spacing: 10) {
            ProgressView(value: model.duration > 0 ? model.currentTime / model.duration : 0)
                .tint(PatreonColors.brand)

            HStack {
                Text(formatTime(model.currentTime))
                Spacer()
                Text("-" + formatTime(max(model.duration - model.currentTime, 0)))
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: 1100)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Progress: \(formatTime(model.currentTime)) of \(formatTime(model.duration))"
        )
    }

    private var transport: some View {
        HStack(spacing: 40) {
            Button {
                model.skip(-15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title2)
            }
            .focused($focusedControl, equals: .skipBack)
            .accessibilityLabel("Skip back 15 seconds")

            Button {
                model.togglePlayPause()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.largeTitle)
                    .frame(width: 80)
            }
            .focused($focusedControl, equals: .playPause)
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")

            Button {
                model.skip(30)
            } label: {
                Image(systemName: "goforward.30")
                    .font(.title2)
            }
            .focused($focusedControl, equals: .skipForward)
            .accessibilityLabel("Skip forward 30 seconds")

            Menu {
                ForEach(Self.rates, id: \.self) { rate in
                    Button {
                        model.setRate(rate)
                    } label: {
                        if rate == model.preferredRate {
                            Label(rateLabel(rate), systemImage: "checkmark")
                        } else {
                            Text(rateLabel(rate))
                        }
                    }
                }
            } label: {
                Text(rateLabel(model.preferredRate))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            .focused($focusedControl, equals: .speed)
            .accessibilityLabel("Playback speed, currently \(rateLabel(model.preferredRate))")
        }
        .buttonStyle(.bordered)
        .focusSection()
    }

    private func rateLabel(_ rate: Float) -> String {
        rate == rate.rounded()
            ? "\(Int(rate))×"
            : String(format: "%.2g×", rate)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
