//
//  SettingsView.swift
//  PatreonTV
//
//  Minimal settings — sign out for MVP. Later: playback quality, captions,
//  autoplay next, parental controls.
//

import NukeUI
import SwiftUI

struct SettingsView: View {

    @Environment(AuthStore.self) private var auth
    @State private var prefs = ContentPreferences.shared

    var body: some View {
        @Bindable var prefs = prefs

        return VStack(spacing: 32) {
            Spacer()

            if let user = auth.currentUser {
                avatar(for: user)

                VStack(spacing: 8) {
                    Text(user.attributes.fullName ?? "Signed in")
                        .font(.title)
                        .foregroundStyle(PatreonColors.primaryText)
                    if let email = user.attributes.email {
                        Text(email)
                            .foregroundStyle(PatreonColors.secondaryText)
                    }
                }
            }

            Toggle(isOn: $prefs.showMatureContent) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show mature content")
                        .foregroundStyle(PatreonColors.primaryText)
                    Text("Reveal creators and posts flagged as NSFW.")
                        .font(.caption)
                        .foregroundStyle(PatreonColors.secondaryText)
                }
            }
            .frame(maxWidth: 700)
            .padding(.top, 8)

            Button {
                auth.signOut()
            } label: {
                Text("Sign Out")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 48)
                    .padding(.vertical, 20)
            }
            .buttonStyle(.borderedProminent)
            .tint(PatreonColors.brand)
            .padding(.top, 16)

            Spacer()

            Text("PatreonTV \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.footnote)
                .foregroundStyle(PatreonColors.tertiaryText)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PatreonColors.background.ignoresSafeArea())
    }

    private func avatar(for user: PatreonUser) -> some View {
        LazyImage(url: user.attributes.imageURL ?? user.attributes.thumbURL) { state in
            if let image = state.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    PatreonColors.cardSurface
                    Image(systemName: "person.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(PatreonColors.tertiaryText)
                }
            }
        }
        .frame(width: 180, height: 180)
        .clipShape(Circle())
    }
}
