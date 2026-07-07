//
//  PatreonTVApp.swift
//  PatreonTV
//
//  App entry point. Owns the AuthStore so the auth gate can decide whether
//  to show the sign-in flow or the main app.
//

import SwiftUI

@main
struct PatreonTVApp: App {

    @State private var authStore = AuthStore()
    @State private var router = DeepLinkRouter()

    var body: some Scene {
        WindowGroup {
            content
                .environment(authStore)
                .environment(router)
                .onOpenURL { url in
                    router.handle(url: url)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        if GalleryConfig.isActive {
            // Storybook-style capture mode (see GalleryHostView / capture-screens.sh).
            GalleryHostView()
        } else {
            RootView().task { await authStore.restoreSession() }
        }
        #else
        RootView().task { await authStore.restoreSession() }
        #endif
    }
}
