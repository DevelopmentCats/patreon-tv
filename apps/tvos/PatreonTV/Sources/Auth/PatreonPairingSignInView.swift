//
//  PatreonPairingSignInView.swift
//  PatreonTV
//
//  Device-link sign-in: TV shows a code + QR, user completes login on
//  patreontv.app/link/<code>, TV polls until the session is ready.
//

import CoreImage.CIFilterBuiltins
import SwiftUI

struct PatreonPairingSignInView: View {

    let onSessionIDCaptured: (String) -> Void
    let onDismiss: () -> Void

    @State private var phase: Phase = .starting
    @State private var pairingSession: PairingSession?
    @State private var pollTask: Task<Void, Never>?

    private enum Phase: Equatable {
        case starting
        case waiting
        case connecting
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 40) {
            header

            switch phase {
            case .starting:
                ProgressView("Starting…")
                    .font(.title3)
            case .waiting, .connecting:
                if let pairingSession {
                    waitingContent(pairingSession)
                }
            case .failed(let message):
                failedContent(message)
            }

            Button("Back", action: cancel)
                .buttonStyle(.bordered)
        }
        .padding(80)
        .frame(maxWidth: 1400)
        .task { await startPairing() }
        .onDisappear { pollTask?.cancel() }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text("Sign in with Patreon")
                .font(.largeTitle.weight(.semibold))
            Text("On your phone or computer, open the link below and sign in.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func waitingContent(_ session: PairingSession) -> some View {
        HStack(alignment: .top, spacing: 64) {
            VStack(spacing: 16) {
                if let qr = QRCodeImage.make(from: session.linkURL.absoluteString, side: 280) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 280, height: 280)
                        .padding(24)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20))
                }

                Text(session.linkURL.host ?? "patreontv.com")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pairing code")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.65))
                    Text(session.displayCode)
                        .font(.system(size: 72, weight: .bold, design: .monospaced))
                        .tracking(8)
                }

                if phase == .connecting {
                    ProgressView("Connecting…")
                        .font(.title3)
                } else {
                    Text("Waiting for you to sign in…")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.75))
                }

                Text("Visit the link or scan the code, then sign in with Patreon.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: 560, alignment: .leading)
        }
    }

    @ViewBuilder
    private func failedContent(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 800)

            Button("Try again") {
                Task { await startPairing() }
            }
            .buttonStyle(.borderedProminent)
            .tint(PatreonColors.brand)
        }
    }

    private func startPairing() async {
        pollTask?.cancel()
        phase = .starting
        pairingSession = nil

        do {
            let session = try await PairingClient.shared.createSession()
            pairingSession = session
            phase = .waiting

            pollTask = Task {
                let result = await PairingClient.shared.waitForSession(
                    code: session.code,
                    expiresAt: session.expiresAt
                )
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    switch result {
                    case .complete(let sessionID):
                        phase = .connecting
                        onSessionIDCaptured(sessionID)
                    case .expired:
                        phase = .failed("This code expired. Tap Try again to get a new one.")
                    case .pending:
                        phase = .failed("Pairing timed out. Tap Try again.")
                    case .failed(let message):
                        phase = .failed(message)
                    }
                }
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func cancel() {
        pollTask?.cancel()
        onDismiss()
    }
}

private enum QRCodeImage {
    static func make(from string: String, side: CGFloat) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let scale = side / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
