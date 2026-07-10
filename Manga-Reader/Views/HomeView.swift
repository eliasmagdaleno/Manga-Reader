//
//  HomeView.swift
//  Manga-Reader
//

import SwiftUI

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Gutter.section) {

                    if let err = vm.errorMessage {
                        InkNotice(err)
                            .padding(.horizontal, Gutter.page)
                    }

                    if vm.isLoading && vm.popular.isEmpty {
                        loadingRail
                    }

                    section("01", "Popular", "Popular",
                            items: vm.popular,
                            stamp: yearStamp)

                    section("02", "Recently Updated", "Fresh chapters",
                            items: vm.latestUpdates.map { $0.manga },
                            stamp: { _ in "NEW" }, tinted: true)

                    section("03", "Newly Added", "Newly Added",
                            items: vm.newTitles,
                            stamp: yearStamp)
                }
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Ink.background)
            .task { vm.loadHome() }
            .navigationTitle("Read")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // A titled section: header + rail. Hidden until it has content.
    @ViewBuilder
    private func section(_ eyebrow: String, _ title: String, _ eyebrowLabel: String,
                         items: [Manga],
                         stamp: @escaping (Manga) -> String?,
                         tinted: Bool = false) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                InkSectionHeader(title, eyebrow: eyebrowLabel)
                MangaRail(items: items, stampFor: stamp, stampTinted: tinted)
            }
        }
    }

    private func yearStamp(_ manga: Manga) -> String? {
        manga.year.map { String($0) }
    }

    // Skeleton rail shown on first load.
    private var loadingRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            InkSectionHeader("Loading", eyebrow: "Please wait")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Gutter.rail) {
                    ForEach(0..<4, id: \.self) { _ in
                        CoverPlaceholder(showsSpinner: true)
                            .frame(width: Gutter.coverWidth, height: Gutter.coverHeight)
                            .clipShape(RoundedRectangle(cornerRadius: Gutter.cardRadius))
                    }
                }
                .padding(.horizontal, Gutter.page)
            }
        }
    }
}

/// A quiet inline error notice in the app's voice — seal-tinted, not alarming red.
struct InkNotice: View {
    let message: String
    init(_ message: String) { self.message = message }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(Ink.seal)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Ink.sealSoft))
    }
}

#Preview {
    HomeView()
}
