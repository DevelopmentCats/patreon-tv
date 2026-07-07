//
//  SearchView.swift
//  PatreonTV
//
//  Creator search using Patreon's internal /api/search endpoint, which returns
//  `campaign-document` resources (creators). Uses SwiftUI's .searchable, which
//  on tvOS provides an on-screen keyboard and Siri dictation (REMOTE-06).
//

import NukeUI
import SwiftUI
import os

struct SearchView: View {

    /// Optional starting query (used by the capture gallery to show results).
    var initialQuery: String = ""

    @State private var vm = SearchViewModel()
    @State private var prefs = ContentPreferences.shared
    @State private var query: String = ""

    /// Results after applying the mature-content gate.
    private var visibleResults: [CampaignSearchResult] {
        prefs.showMatureContent
            ? vm.results
            : vm.results.filter { $0.attributes.isNSFW != true }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch vm.state {
                case .idle:
                    empty
                case .loading:
                    ProgressView().controlSize(.large)
                case .loaded:
                    if visibleResults.isEmpty {
                        noResults
                    } else {
                        resultsGrid
                    }
                case .error(let m):
                    ErrorView(message: m) { Task { await vm.search(query: query) } }
                }
            }
            .searchable(text: $query, prompt: "Search creators")
            .onChange(of: query) { _, newValue in
                vm.debouncedSearch(query: newValue)
            }
            .task {
                // Seed a query on first appear (capture gallery); triggers search.
                if query.isEmpty {
                    let seed = initialQuery.isEmpty ? (GalleryConfig.query ?? "") : initialQuery
                    if !seed.isEmpty { query = seed }
                }
            }
            .background(PatreonColors.background.ignoresSafeArea())
            .appNavigationDestinations()
        }
    }

    private var empty: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 80))
                .foregroundStyle(PatreonColors.secondaryText)
            Text("Find creators")
                .font(.title2)
                .foregroundStyle(PatreonColors.primaryText)
            Text("Search Patreon for creators to watch.")
                .foregroundStyle(PatreonColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResults: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(PatreonColors.secondaryText)
            Text("No creators for \"\(query)\"")
                .font(.title3)
                .foregroundStyle(PatreonColors.primaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 320, maximum: 380), spacing: 40)],
                spacing: 40
            ) {
                ForEach(visibleResults) { result in
                    NavigationLink(value: DeepLinkDestination.creator(id: result.campaignID)) {
                        SearchCreatorCard(result: result)
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(60)
        }
        .scrollClipDisabled()
    }
}

struct SearchCreatorCard: View {

    let result: CampaignSearchResult

    private let cardWidth: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyImage(url: result.attributes.avatarPhotoURL) { state in
                if let img = state.image {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        PatreonColors.cardSurface
                        Image(systemName: "person.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(PatreonColors.tertiaryText)
                    }
                }
            }
            .frame(width: cardWidth, height: cardWidth)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(result.attributes.name ?? result.attributes.creatorName ?? "Creator")
                    .font(.headline)
                    .foregroundStyle(PatreonColors.primaryText)
                    .lineLimit(1)
                    .frame(width: cardWidth, alignment: .leading)

                if let creation = result.attributes.creationName {
                    Text(creation)
                        .font(.subheadline)
                        .foregroundStyle(PatreonColors.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: cardWidth, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.attributes.name ?? "Creator"), \(result.attributes.creationName ?? "")")
    }
}

@Observable
@MainActor
final class SearchViewModel {

    enum ViewState: Equatable { case idle, loading, loaded, error(String) }

    private(set) var state: ViewState = .idle
    private(set) var results: [CampaignSearchResult] = []
    private var currentQuery: String = ""
    private var debounceTask: Task<Void, Never>?

    private let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "Search")

    /// Schedules a search after a short pause in typing. Synchronous — the
    /// debounce window lives in the internal task, so callers don't need to
    /// wrap this in another Task.
    func debouncedSearch(query: String) {
        debounceTask?.cancel()
        currentQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.count < 2 {
            state = .idle
            results = []
            return
        }

        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, self.currentQuery == query else { return }
            await self.search(query: trimmed)
        }
    }

    func search(query: String) async {
        state = .loading
        do {
            results = try await PatreonClient.shared.searchCreators(query: query, limit: 40)
            state = .loaded
        } catch {
            log.error("Search failed: \(String(describing: error))")
            state = .error((error as? PatreonError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
