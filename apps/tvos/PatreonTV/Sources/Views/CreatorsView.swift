//
//  CreatorsView.swift
//  PatreonTV
//
//  Grid of creators the user supports. Placeholder for MVP — real
//  implementation coming after Home is polished.
//

import SwiftUI

struct CreatorsView: View {
    @State private var memberships: [Membership] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().controlSize(.large)
                } else if !memberships.isEmpty {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 320), spacing: 32)], spacing: 32) {
                            ForEach(memberships) { m in
                                Text(m.attributes.patronStatus ?? "?")
                                    .padding()
                            }
                        }
                        .padding(60)
                    }
                } else if let errorMessage {
                    ErrorView(message: errorMessage) { Task { await load() } }
                } else {
                    EmptyFeedView()
                }
            }
            .task { await load() }
            .background(PatreonColors.background.ignoresSafeArea())
        }
    }

    private func load() async {
        do {
            memberships = try await PatreonClient.shared.memberships()
        } catch {
            errorMessage = (error as? PatreonError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}
