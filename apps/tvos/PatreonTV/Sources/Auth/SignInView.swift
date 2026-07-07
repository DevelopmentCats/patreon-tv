//
//  SignInView.swift
//  PatreonTV
//
//  First-launch (and re-auth) sign-in flow. Presents a pitch, then opens
//  the device-link pairing panel. User completes login on patreontv.app;
//  the TV polls until the session_id is ready.
//

import SwiftUI

struct SignInView: View {

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

            VStack(spacing: 12) {
                Text("Watch your Patreon creators on the big screen.")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.85))
                Text("Sign in with your Patreon account to get started.")
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
