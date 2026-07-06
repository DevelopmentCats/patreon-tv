//
//  SignInView.swift
//  PatreonTV
//
//  First-launch (and re-auth) sign-in flow. Presents a large, clear pitch,
//  then opens a WKWebView on `patreon.com/login`. When the user has
//  successfully logged in, we detect the `session_id` cookie on the shared
//  cookie store and hand it to AuthStore.
//
//  tvOS considerations:
//  - The WKWebView must be given focus so the user can interact with the
//    on-screen keyboard and Patreon's form.
//  - Siri dictation works on tvOS for text fields — users can *speak* their
//    email address into the mic on the Siri Remote.
//  - iCloud Keychain sync fills passwords for known sites, including
//    patreon.com, if the user has a stored credential.
//  - iPhone-nearby text entry: when a tvOS text field is focused, a
//    notification pops on the user's iPhone allowing them to type on their
//    phone's keyboard.
//

import SwiftUI

struct SignInView: View {

    @Environment(AuthStore.self) private var auth
    @State private var showWebView = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.05, green: 0, blue: 0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if showWebView {
                PatreonLoginWebView(
                    onCookieCaptured: { sessionID in
                        Task { await auth.completeSignIn(sessionID: sessionID) }
                    },
                    onDismiss: {
                        withAnimation { showWebView = false }
                    }
                )
                .transition(.opacity)
            } else {
                pitch
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showWebView)
    }

    private var pitch: some View {
        VStack(spacing: 40) {
            Spacer()

            Text("PatreonTV")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

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
                withAnimation { showWebView = true }
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
