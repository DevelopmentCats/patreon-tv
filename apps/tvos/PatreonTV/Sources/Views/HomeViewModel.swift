//
//  HomeViewModel.swift
//  PatreonTV
//
//  Data source for HomeView. Fetches the home feed and a "new from your
//  creators" cut of it.
//

import Foundation
import Observation
import os.log

@Observable
@MainActor
final class HomeViewModel {

    enum ViewState: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var state: ViewState = .idle
    private(set) var homeFeed: [Post] = []
    private(set) var newFromCreators: [Post] = []
    private var nextCursor: String?

    private let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "Home")

    func load() async {
        guard state == .idle else { return }
        await reload()
    }

    func reload() async {
        state = .loading
        do {
            let page = try await PatreonClient.shared.homeFeed(limit: 30)
            homeFeed = page.data
            nextCursor = page.nextCursor
            // "New" cut = first 12, newest first (feed is already ordered by
            // Patreon).
            newFromCreators = Array(page.data.prefix(12))
            state = homeFeed.isEmpty ? .empty : .loaded
        } catch {
            log.error("Home feed load failed: \(String(describing: error))")
            state = .error(errorMessage(from: error))
        }
    }

    func loadMoreIfNeeded(current: Post) async {
        guard let cursor = nextCursor,
              let index = homeFeed.firstIndex(where: { $0.id == current.id }),
              index >= homeFeed.count - 5
        else { return }

        do {
            let page = try await PatreonClient.shared.homeFeed(cursor: cursor, limit: 30)
            homeFeed.append(contentsOf: page.data)
            nextCursor = page.nextCursor
        } catch {
            log.error("Home feed pagination failed: \(String(describing: error))")
        }
    }

    private func errorMessage(from error: Error) -> String {
        if let pe = error as? PatreonError {
            return pe.errorDescription ?? "Something went wrong."
        }
        return error.localizedDescription
    }
}
