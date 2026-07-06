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
            RootView()
                .environment(authStore)
                .environment(router)
                .task {
                    await authStore.restoreSession()
                }
                .onOpenURL { url in
                    router.handle(url: url)
                }
        }
    }
}
