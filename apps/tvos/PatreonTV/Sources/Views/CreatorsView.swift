//
//  CreatorsView.swift
//  PatreonTV
//
//  Grid of the creators the user follows. Patreon's internal /current_user does
//  not sideload memberships (the relationship comes back empty with no related
//  link), so we derive the list from the campaigns present in the home stream —
//  the creators whose posts the user actually sees.
//

import NukeUI
import SwiftUI
import os

struct CreatorsView: View {

    @State private var vm = CreatorsViewModel()
    @State private var prefs = ContentPreferences.shared

    /// Entries after applying the mature-content gate.
    private var visibleEntries: [CreatorsViewModel.Entry] {
        prefs.showMatureContent
            ? vm.entries
            : vm.entries.filter { $0.campaign.attributes.isNSFW != true }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch vm.state {
                case .idle, .loading:
                    ProgressView().controlSize(.large)
                case .loaded:
                    if visibleEntries.isEmpty { CreatorsEmptyView() } else { content }
                case .empty:
                    CreatorsEmptyView()
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
                ForEach(visibleEntries) { entry in
                    NavigationLink {
                        CreatorView(campaignID: entry.campaign.id, membership: nil)
                    } label: {
                        CreatorCard(campaign: entry.campaign)
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(60)
        }
        .scrollClipDisabled()
    }
}

struct CreatorsEmptyView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 80))
                .foregroundStyle(PatreonColors.secondaryText)
            Text("No creators yet")
                .font(.title2)
                .foregroundStyle(PatreonColors.primaryText)
            Text("Creators you actively support on Patreon will appear here.")
                .foregroundStyle(PatreonColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CreatorCard: View {

    let campaign: Campaign

    private let cardWidth: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyImage(url: campaign.attributes.bestAvatarURL) { state in
                // Initials placeholder sits underneath so it still shows when a
                // campaign's avatar is a broken/empty image (some return 200 blank).
                ZStack {
                    avatarPlaceholder
                    if let img = state.image {
                        img.resizable().aspectRatio(contentMode: .fill)
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
        .frame(width: cardWidth, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(campaign.attributes.name ?? "Creator"), \(campaign.attributes.creationName ?? "")")
    }

    /// A colored tile with the creator's initial, used when no avatar loads.
    private var avatarPlaceholder: some View {
        let name = campaign.attributes.name ?? "?"
        let hue = Double(name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 360) / 360
        let tint = Color(hue: hue, saturation: 0.45, brightness: 0.5)
        return ZStack {
            LinearGradient(colors: [tint, tint.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(name.first.map { String($0).uppercased() } ?? "?")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

// MARK: - View model

@Observable
@MainActor
final class CreatorsViewModel {

    enum ViewState: Equatable { case idle, loading, loaded, empty, error(String) }

    /// A followed creator's campaign. Wrapped so the view can iterate directly.
    struct Entry: Identifiable {
        let campaign: Campaign
        var id: String { campaign.id }
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
            // The user's current creators, listed directly from /api/members
            // (active patrons + free follows; lapsed excluded), unioned with
            // /api/pledges to catch any paid sub missing from members. NSFW
            // filtering happens in the view so the Settings toggle applies live.
            var byID: [String: Campaign] = [:]
            var order: [String] = []
            func add(_ c: Campaign) {
                if byID[c.id] == nil { byID[c.id] = c; order.append(c.id) }
            }

            // 1) All current relationships (active or free), most-recent first.
            let memberDoc = try await PatreonClient.shared.members()
            var memberCampaigns: [String: Campaign] = [:]
            for inc in memberDoc.included ?? [] {
                if case .campaign(let c) = inc { memberCampaigns[c.id] = c }
            }
            for member in memberDoc.data where member.isCurrentRelationship {
                if let cid = member.relationships?.campaign?.data?.id,
                   let c = memberCampaigns[cid] { add(c) }
            }

            // 2) Union in active paid pledges (a paid sub can be absent from
            //    /members but present here).
            let pledgeDoc = try await PatreonClient.shared.pledges()
            var pledgeCampaigns: [String: Campaign] = [:]
            for inc in pledgeDoc.included ?? [] {
                if case .campaign(let c) = inc { pledgeCampaigns[c.id] = c }
            }
            for pledge in pledgeDoc.data {
                if let cid = pledge.relationships?.campaign?.data?.id,
                   let c = pledgeCampaigns[cid] { add(c) }
            }

            entries = order.compactMap { byID[$0] }.map { Entry(campaign: $0) }
            state = entries.isEmpty ? .empty : .loaded
        } catch {
            log.error("Creators load failed: \(String(describing: error))")
            state = .error((error as? PatreonError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
