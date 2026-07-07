//
//  RootView.swift
//  PatreonTV
//
//  Auth gate. Shows SignInView if unauthenticated, HomeShell if authenticated.
//

import SwiftUI

struct RootView: View {

    @Environment(AuthStore.self) private var auth

    var body: some View {
        Group {
            switch auth.state {
            case .unknown:
                SplashView()
            case .signedOut:
                SignInView()
                    .transition(.opacity)
            case .signedIn:
                HomeShell()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: auth.state)
    }
}

/// Brief branded splash shown while we check for a stored session on launch.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image("PTVWordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 180)
                .accessibilityLabel("PatreonTV")
        }
    }
}
