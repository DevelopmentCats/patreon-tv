//
//  SearchView.swift
//  PatreonTV
//
//  Post search using Patreon's internal /api/search endpoint.
//  Uses SwiftUI's .searchable, which on tvOS provides an on-screen keyboard
//  and Siri dictation support (REMOTE-06 in the tvOS design skill).
//

import SwiftUI
import os

struct SearchView: View {

    @State private var vm = SearchViewModel()
    @State private var query: String = ""

    var body: some View {
        NavigationStack {
            Group {
                switch vm.state {
                case .idle:
                    empty
                case .loading:
                    ProgressView().controlSize(.large)
                case .loaded:
                    if vm.results.isEmpty {
                        noResults
                    } else {
                        resultsGrid
                    }
                case .error(let m):
                    ErrorView(message: m) { Task { await vm.search(query: query) } }
                }
            }
            .searchable(text: $query, prompt: "Search posts")
            .onChange(of: query) { _, newValue in
                Task { await vm.debouncedSearch(query: newValue) }
            }
            .background(PatreonColors.background.ignoresSafeArea())
        }
    }

    private var empty: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 80))
                .foregroundStyle(PatreonColors.secondaryText)
            Text("Search Patreon")
                .font(.title2)
                .foregroundStyle(PatreonColors.primaryText)
            Text("Find posts across your creators and beyond.")
                .foregroundStyle(PatreonColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResults: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(PatreonColors.secondaryText)
            Text("No results for \"\(query)\"")
                .font(.title3)
                .foregroundStyle(PatreonColors.primaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 420, maximum: 480), spacing: 32)],
                spacing: 40
            ) {
                ForEach(vm.results) { post in
                    NavigationLink {
                        PostDetailView(postID: post.id)
                    } label: {
                        PostCard(post: post, campaign: vm.campaign(for: post))
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(60)
        }
        .scrollClipDisabled()
    }
}

@Observable
@MainActor
final class SearchViewModel {

    enum ViewState: Equatable { case idle, loading, loaded, error(String) }

    private(set) var state: ViewState = .idle
    private(set) var results: [Post] = []
    private var campaignsByPostID: [String: Campaign] = [:]
    private var currentQuery: String = ""
    private var debounceTask: Task<Void, Never>?

    private let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "Search")

    func campaign(for post: Post) -> Campaign? {
        campaignsByPostID[post.id]
    }

    func debouncedSearch(query: String) async {
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
            let page = try await PatreonClient.shared.search(query: query, limit: 40)
            results = page.data
            campaignsByPostID.removeAll(keepingCapacity: true)
            var byID: [String: Campaign] = [:]
            for inc in page.included ?? [] {
                if case .campaign(let c) = inc { byID[c.id] = c }
            }
            for post in results {
                if let cid = post.relationships?.campaign?.data?.id {
                    campaignsByPostID[post.id] = byID[cid]
                }
            }
            state = .loaded
        } catch {
            log.error("Search failed: \(String(describing: error))")
            state = .error((error as? PatreonError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
