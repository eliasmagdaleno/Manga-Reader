//
//  HomeView.swift
//  Manga-Reader
//

import SwiftUI

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @ObservedObject private var registry = SourceRegistry.shared
    @EnvironmentObject private var engine: RecommendationEngine
    @AppStorage("settings.showAdultSources") private var showAdultSources = false

    var body: some View {
        // Capture the browse source as a value so the escaping "See all" fetch closures
        // don't reach back into MainActor-isolated state.
        let source = vm.source
        return NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Gutter.section) {

                    // Source switcher — every visible source, one tap away.
                    SourceChipBar(
                        sources: registry.visibleSources(includeAdult: showAdultSources),
                        activeID: registry.activeSourceID
                    ) { id in
                        withAnimation(.snappy(duration: 0.2)) {
                            registry.activeSourceID = id
                        }
                    }

                    if let err = vm.errorMessage {
                        InkNotice(err)
                            .padding(.horizontal, Gutter.page)
                    }

                    if vm.isLoading && vm.popular.isEmpty {
                        loadingRail
                    }

                    // Personalized rail #0 — hidden until there's enough reading signal.
                    if !engine.recommendations.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            InkSectionHeader("For You", eyebrow: "Based on your reading")
                                .overlay(alignment: .trailing) {
                                    NavigationLink {
                                        // Recommendations are a bounded ranked list, so the
                                        // grid loads the full pool once then ends (offset > 0
                                        // → empty page → PagedMangaLoader stops).
                                        CategoryGridView(
                                            title: "For You",
                                            initialItems: engine.recommendations.map(\.manga),
                                            pagedFetch: { _, offset in
                                                offset == 0 ? await engine.rankedRecommendations() : []
                                            })
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
                            RecommendationRail(
                                items: engine.recommendations,
                                onNotInterested: { engine.markNotInterested($0) },
                                onMoreLikeThis: { engine.markMoreLikeThis($0) }
                            )
                        }
                    }

                    let titles = source.homeRailTitles.count >= 3 ? source.homeRailTitles : ["Popular", "Recently Updated", "Newly Added"]
                    // Eyebrows describe each feed's true ordering; sources that
                    // don't provide them just show the plain serif title.
                    let eyebrows = source.homeRailEyebrows

                    section(titles[0], eyebrow: eyebrows.count > 0 ? eyebrows[0] : nil,
                            items: vm.popular,
                            stamp: yearStamp,
                            pagedFetch: { limit, offset in
                                try await source.popular(limit: limit, offset: offset)
                            })

                    section(titles[1], eyebrow: eyebrows.count > 1 ? eyebrows[1] : nil,
                            items: vm.latestUpdates.map { $0.manga },
                            stamp: source.latestRailShowsNewBadge ? { _ in "NEW" } : yearStamp,
                            tinted: source.latestRailShowsNewBadge,
                            // Pages the underlying chapter feed, which dedupes down to far
                            // fewer manga — so ask for a bigger page to still fill a screen.
                            pageSize: 48,
                            pagedFetch: { limit, offset in
                                try await source
                                    .latestUpdates(limitTitles: limit, language: "en", offset: offset)
                                    .map { $0.manga }
                            })

                    section(titles[2], eyebrow: eyebrows.count > 2 ? eyebrows[2] : nil,
                            items: vm.newTitles,
                            stamp: yearStamp,
                            pagedFetch: { limit, offset in
                                try await source.newTitles(limit: limit, offset: offset)
                            })
                }
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Ink.background)
            .task(id: registry.activeSourceID) { vm.loadHome() }
            .task { engine.load() }
            // Pull-to-refresh reseeds the exploration mix and rebuilds from the latest
            // reading signal — the only way a cold-start rail surfaces (or reshuffles)
            // without relaunching, since the Home tab stays alive so `.task` fires once.
            .refreshable { await engine.refresh() }
            .navigationTitle("Read")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // A titled section: header + rail. Hidden until it has content.
    @ViewBuilder
    private func section(_ title: String, eyebrow: String?,
                         items: [Manga],
                         stamp: @escaping (Manga) -> String?,
                         tinted: Bool = false,
                         pageSize: Int = 24,
                         pagedFetch: @escaping (_ limit: Int, _ offset: Int) async throws -> [Manga]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                InkSectionHeader(title, eyebrow: eyebrow)
                    .overlay(alignment: .trailing) {
                        NavigationLink {
                            CategoryGridView(title: title, initialItems: items,
                                             pageSize: pageSize, pagedFetch: pagedFetch)
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
            InkSectionHeader("Loading", eyebrow: vm.source.name)
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
    let library = LibraryStore()
    let history = HistoryStore()
    let taste = TasteProfileStore()
    let works = WorkStore()
    return HomeView()
        .environmentObject(library)
        .environmentObject(history)
        .environmentObject(taste)
        .environmentObject(works)
        .environmentObject(RecommendationEngine(history: history, library: library,
                                                profileStore: taste, workStore: works))
}
