//
//  SignInView.swift
//  PatreonTV
//
//  First-launch (and re-auth) sign-in flow. Presents a pitch, then opens
//  the device-link pairing panel. User completes login on patreontv.com;
//  the TV polls until the session_id is ready.
//

import SwiftUI

struct SignInView: View {

    /// True when the user's stored session was rejected mid-use — shows a
    /// "session expired" banner so it's clear why they're back here.
    var sessionExpired: Bool = false

    @Environment(AuthStore.self) private var auth
    @State private var showPairing = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.05, green: 0, blue: 0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if showPairing {
                PatreonPairingSignInView(
                    onSessionIDCaptured: { sessionID in
                        Task { await auth.completeSignIn(sessionID: sessionID) }
                    },
                    onDismiss: {
                        withAnimation { showPairing = false }
                    }
                )
                .transition(.opacity)
            } else {
                pitch
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showPairing)
    }

    private var pitch: some View {
        VStack(spacing: 40) {
            Spacer()

            Image("PTVWordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 160)
                .accessibilityLabel("PatreonTV")

            if sessionExpired {
                HStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Your Patreon session expired. Link your TV again to keep watching.")
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .font(.title3.weight(.medium))
                .padding(.horizontal, 32)
                .padding(.vertical, 18)
                .frame(maxWidth: 900)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .combine)
            }

            VStack(spacing: 12) {
                Text("Watch your Patreon creators on the big screen.")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.85))
                Text(
                    sessionExpired
                        ? "Sign in with Patreon again to reconnect this TV."
                        : "Sign in with your Patreon account to get started."
                )
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
            }
            .multilineTextAlignment(.center)

            Spacer()

            Button {
                withAnimation { showPairing = true }
            } label: {
                Text("Sign in with Patreon")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 48)
                    .padding(.vertical, 20)
            }
            .buttonStyle(.borderedProminent)
            .tint(PatreonColors.brand)

            Text("PatreonTV is not affiliated with Patreon.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.bottom, 60)
        }
        .frame(maxWidth: 1200)
    }
}
