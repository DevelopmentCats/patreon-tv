//
//  CreatorsView.swift
//  PatreonTV
//
//  Grid of creators the user supports. Sourced from /current_user/memberships
//  which returns member records with campaign includes. Free-follow
//  memberships are hidden by default.
//

import NukeUI
import SwiftUI
import os

struct CreatorsView: View {

    @State private var vm = CreatorsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch vm.state {
                case .idle, .loading:
                    ProgressView().controlSize(.large)
                case .loaded:
                    content
                case .empty:
                    EmptyFeedView()
                case .error(let m):
                    ErrorView(message: m) { Task { await vm.reload() } }
                }
            }
            .task { await vm.load() }
            .background(PatreonColors.background.ignoresSafeArea())
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 320, maximum: 380), spacing: 40)],
                spacing: 40
            ) {
                ForEach(vm.entries, id: \.membership.id) { entry in
                    NavigationLink {
                        CreatorView(campaignID: entry.campaign.id, membership: entry.membership)
                    } label: {
                        CreatorCard(campaign: entry.campaign, membership: entry.membership)
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(60)
        }
        .scrollClipDisabled()
    }
}

struct CreatorCard: View {

    let campaign: Campaign
    let membership: Membership

    private let cardWidth: CGFloat = 340
    private let cardHeight: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyImage(url: campaign.attributes.imageURL) { state in
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
                Text(campaign.attributes.name ?? "Unknown creator")
                    .font(.headline)
                    .foregroundStyle(PatreonColors.primaryText)
                    .lineLimit(1)
                    .frame(width: cardWidth, alignment: .leading)

                if let creation = campaign.attributes.creationName {
                    Text(creation)
                        .font(.subheadline)
                        .foregroundStyle(PatreonColors.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(campaign.attributes.name ?? "Creator"), \(campaign.attributes.creationName ?? "")")
    }
}

// MARK: - View model

@Observable
@MainActor
final class CreatorsViewModel {

    enum ViewState: Equatable { case idle, loading, loaded, empty, error(String) }

    /// A membership + its resolved campaign. Pre-joined so the view can just iterate.
    struct Entry: Identifiable {
        let membership: Membership
        let campaign: Campaign
        var id: String { membership.id }
    }

    private(set) var state: ViewState = .idle
    private(set) var entries: [Entry] = []

    private let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "Creators")

    func load() async {
        guard state == .idle else { return }
        await reload()
    }

    func reload() async {
        state = .loading
        do {
            let doc = try await PatreonClient.shared.memberships()
            var campaignByID: [String: Campaign] = [:]
            for inc in doc.included ?? [] {
                if case .campaign(let c) = inc {
                    campaignByID[c.id] = c
                }
            }

            var joined: [Entry] = []
            for m in doc.data {
                guard let cid = m.relationships?.campaign?.data?.id,
                      let c = campaignByID[cid]
                else { continue }
                // Filter NSFW campaigns per App Store guidance.
                if c.attributes.isNSFW == true { continue }
                joined.append(Entry(membership: m, campaign: c))
            }

            // Sort: active patrons first, then by patron_count desc.
            joined.sort { a, b in
                let aActive = a.membership.isActivePatron ? 0 : 1
                let bActive = b.membership.isActivePatron ? 0 : 1
                if aActive != bActive { return aActive < bActive }
                return (a.campaign.attributes.patronCount ?? 0) > (b.campaign.attributes.patronCount ?? 0)
            }

            entries = joined
            state = entries.isEmpty ? .empty : .loaded
        } catch {
            log.error("Memberships load failed: \(String(describing: error))")
            state = .error((error as? PatreonError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
