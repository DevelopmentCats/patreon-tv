//
//  HomeShell.swift
//  PatreonTV
//
//  Top-level tab-bar shell shown when the user is signed in.
//
//  Follows tvOS design rules TAB-01 (top tab bar), TAB-03 (3–7 tabs),
//  TAB-04 (text labels), TAB-06 (persist selection).
//

import SwiftUI

struct HomeShell: View {

    @Environment(AuthStore.self) private var auth
    @AppStorage("selected_tab") private var selectedTab: Tab = .home

    enum Tab: String, CaseIterable, Identifiable {
        case home, creators, search, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: "Home"
            case .creators: "Creators"
            case .search: "Search"
            case .settings: "Settings"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label(Tab.home.title, systemImage: "house.fill") }
                .tag(Tab.home)

            CreatorsView()
                .tabItem { Label(Tab.creators.title, systemImage: "person.2.fill") }
                .tag(Tab.creators)

            SearchView()
                .tabItem { Label(Tab.search.title, systemImage: "magnifyingglass") }
                .tag(Tab.search)

            SettingsView()
                .tabItem { Label(Tab.settings.title, systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .background(PatreonColors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
