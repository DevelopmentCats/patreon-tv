//
//  SettingsView.swift
//  PatreonTV
//
//  Minimal settings — sign out for MVP. Later: playback quality, captions,
//  autoplay next, parental controls.
//

import SwiftUI

struct SettingsView: View {

    @Environment(AuthStore.self) private var auth

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 8) {
                if let user = auth.currentUser {
                    Text(user.attributes.fullName ?? "Signed in")
                        .font(.title2)
                        .foregroundStyle(PatreonColors.primaryText)
                    if let email = user.attributes.email {
                        Text(email)
                            .foregroundStyle(PatreonColors.secondaryText)
                    }
                }
            }
            .padding(.top, 60)

            Button(role: .destructive) {
                auth.signOut()
            } label: {
                Text("Sign Out")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 48)
                    .padding(.vertical, 20)
            }
            .buttonStyle(.bordered)

            Spacer()

            Text("PatreonTV \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.footnote)
                .foregroundStyle(PatreonColors.tertiaryText)
                .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PatreonColors.background.ignoresSafeArea())
    }
}
