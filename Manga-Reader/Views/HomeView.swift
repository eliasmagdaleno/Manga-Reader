//
//  HomeView.swift
//  Manga-Reader
//

import SwiftUI

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @ObservedObject private var registry = SourceRegistry.shared
    @AppStorage("settings.showAdultSources") private var showAdultSources = false

    var body: some View {
        // Capture the browse source as a value so the escaping "See all" fetch closures
        // don't reach back into MainActor-isolated state.
        let source = vm.source
        return NavigationStack {
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
                            stamp: yearStamp,
                            fetch: { try await source.popular(limit: 60, offset: 0) })

                    section("02", "Recently Updated", "Fresh chapters",
                            items: vm.latestUpdates.map { $0.manga },
                            stamp: { _ in "NEW" }, tinted: true,
                            fetch: {
                                try await source
                                    .latestUpdates(limitTitles: 60, language: "en")
                                    .map { $0.manga }
                            })

                    section("03", "Newly Added", "Newly Added",
                            items: vm.newTitles,
                            stamp: yearStamp,
                            fetch: { try await source.newTitles(limit: 60, offset: 0) })
                }
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Ink.background)
            .task(id: registry.activeSourceID) { vm.loadHome() }
            .navigationTitle("Read")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(registry.visibleSources(includeAdult: showAdultSources), id: \.id) { source in
                            Button {
                                registry.activeSourceID = source.id
                            } label: {
                                if source.id == registry.activeSourceID {
                                    Label(source.name, systemImage: "checkmark")
                                } else {
                                    Text(source.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(registry.active.name.uppercased())
                                .font(.inkMono(11, weight: .semibold))
                                .tracking(0.5)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Ink.seal)
                    }
                }
            }
        }
    }

    // A titled section: header + rail. Hidden until it has content.
    @ViewBuilder
    private func section(_ eyebrow: String, _ title: String, _ eyebrowLabel: String,
                         items: [Manga],
                         stamp: @escaping (Manga) -> String?,
                         tinted: Bool = false,
                         fetch: (() async throws -> [Manga])? = nil) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                InkSectionHeader(title, eyebrow: eyebrowLabel)
                    .overlay(alignment: .trailing) {
                        NavigationLink {
                            CategoryGridView(title: title, initialItems: items, fetch: fetch)
                        } label: {
                            HStack(spacing: 3) {
                                Text("See all")
                                Image(systemName: "chevron.right")
                            }
                            .font(.inkMono(11, weight: .semibold))
                            .foregroundStyle(Ink.seal)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, Gutter.page)
                    }
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
