//
//  SearchView.swift
//  PatreonTV
//
//  Placeholder — a real search implementation lands once Home + Creators
//  are polished. Patreon's internal API does have a search endpoint; wire
//  in later.
//

import SwiftUI

struct SearchView: View {
    var body: some View {
        VStack {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 80))
                .foregroundStyle(PatreonColors.secondaryText)
            Text("Search coming soon")
                .font(.title2)
                .foregroundStyle(PatreonColors.primaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PatreonColors.background.ignoresSafeArea())
    }
}
