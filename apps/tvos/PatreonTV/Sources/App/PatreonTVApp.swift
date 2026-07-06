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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authStore)
                .task {
                    await authStore.restoreSession()
                }
        }
    }
}
