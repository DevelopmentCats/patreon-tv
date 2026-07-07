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
//  Navigation is value-based throughout: every post/creator link pushes a
//  DeepLinkDestination, and each tab's NavigationStack registers the shared
//  destination table via .appNavigationDestinations(). Deep links inject into
//  the Home tab's path.
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
                    .appNavigationDestinations()
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

/// Shared destination table. Every NavigationStack in the app registers this
/// so value-based links resolve identically in all tabs.
struct AppNavigationDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: DeepLinkDestination.self) { dest in
            switch dest {
            case .post(let id, let autoplay):
                PostDetailView(postID: id, autoplay: autoplay)
            case .creator(let id):
                CreatorView(campaignID: id, membership: nil)
            }
        }
    }
}

extension View {
    func appNavigationDestinations() -> some View {
        modifier(AppNavigationDestinations())
    }
}
