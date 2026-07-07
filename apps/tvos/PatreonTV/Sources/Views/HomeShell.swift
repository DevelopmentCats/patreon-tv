//
//  HomeShell.swift
//  PatreonTV
//
//  Top-level tab-bar shell shown when the user is signed in. Also handles
//  deep-link navigation (from the Top Shelf extension).
//
//  Follows tvOS design rules TAB-01 (top tab bar), TAB-03 (3–7 tabs),
//  TAB-04 (text labels), TAB-06 (persist selection).
//
//  KNOWN LIMITATION: shelves currently use destination-style NavigationLinks
//  (`NavigationLink { PostDetailView(...) }`), while deep-link injection uses
//  value-based NavigationStack path. Migrate all navigation to value-based
//  once we've verified this works on real hardware.
//

import SwiftUI

struct HomeShell: View {

    @Environment(AuthStore.self) private var auth
    @Environment(DeepLinkRouter.self) private var router
    @AppStorage("selected_tab") private var selectedTab: Tab = .home

    /// Path used to push detail views from a deep link. Each tab has its own
    /// NavigationStack; we route deep links to the Home tab and push there.
    @State private var homePath: [DeepLinkDestination] = []

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
            NavigationStack(path: $homePath) {
                HomeView()
                    .navigationDestination(for: DeepLinkDestination.self) { dest in
                        switch dest {
                        case .post(let id, _):
                            PostDetailView(postID: id)
                        case .creator(let id):
                            CreatorView(campaignID: id, membership: nil)
                        }
                    }
            }
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
        .overlay(alignment: .topLeading) {
            Image("PTVMark")
                .resizable()
                .scaledToFit()
                .frame(height: 52)
                .padding(.leading, 60)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        .onChange(of: router.pending) { _, pending in
            guard let pending else { return }
            selectedTab = .home
            switch pending {
            case .post(let id, let autoplay):
                homePath = [.post(id: id, autoplay: autoplay)]
            case .creator(let id):
                homePath = [.creator(id: id)]
            }
            router.consume()
        }
    }
}

/// NavigationDestination values are Codable + Hashable so NavigationStack can
/// persist them across launches.
enum DeepLinkDestination: Hashable, Codable {
    case post(id: String, autoplay: Bool)
    case creator(id: String)
}
