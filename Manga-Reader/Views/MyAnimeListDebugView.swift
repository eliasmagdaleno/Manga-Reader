//
//  MyAnimeListDebugView.swift
//  Manga-Reader
//
//  Throwaway verification screen for the read-only MAL client. Delete once the real
//  "More Like This" UI (a later spec) ships.
//

import SwiftUI

struct MyAnimeListDebugView: View {
    @State private var query = ""
    @State private var results: [MyAnimeListManga] = []
    @State private var detail: MyAnimeListMangaDetail?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var resolveQuery = ""
    @State private var resolvedText: String?
    @State private var mltQuery = ""
    @State private var mltResults: [Manga] = []

    var body: some View {
        List {
            Section("Search") {
                TextField("Title", text: $query)
                    .accessibilityIdentifier("malSearchField")
                    .onSubmit { search() }
                Button("Search") { search() }
                    .accessibilityIdentifier("malSearchButton")
                    .disabled(query.isEmpty || isLoading)
            }

            Section("Resolve source title") {
                TextField("Scraped-source title", text: $resolveQuery)
                    .accessibilityIdentifier("malResolveField")
                    .onSubmit { resolve() }
                Button("Resolve") { resolve() }
                    .accessibilityIdentifier("malResolveButton")
                    .disabled(resolveQuery.isEmpty || isLoading)
                if let resolvedText {
                    Text(resolvedText)
                        .accessibilityIdentifier("malResolveResult")
                }
            }

            Section("More Like This") {
                TextField("Title", text: $mltQuery)
                    .accessibilityIdentifier("mltField")
                    .onSubmit { moreLikeThis() }
                Button("Find similar") { moreLikeThis() }
                    .accessibilityIdentifier("mltButton")
                    .disabled(mltQuery.isEmpty || isLoading)
                ForEach(mltResults, id: \.id) { manga in
                    Text(manga.title)
                        .accessibilityIdentifier("mltResultRow_\(manga.id)")
                }
            }

            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("malErrorMessage")
                }
            }

            if !results.isEmpty {
                Section("Results") {
                    ForEach(results, id: \.id) { manga in
                        Button(manga.title) { loadDetail(id: manga.id) }
                            .accessibilityIdentifier("malResultRow_\(manga.id)")
                    }
                }
            }

            if let detail {
                // Identifiers are on individual rows, not the Section itself: a
                // `.accessibilityIdentifier` applied to a `Section` inside a `List`
                // does not surface as a queryable XCUIElement (verified against the
                // live API while writing this screen's UI test — the Section-level
                // identifier was silently unreachable even though the data had loaded).
                Section("Detail") {
                    Text(detail.title)
                        .font(.headline)
                        .accessibilityIdentifier("malDetailTitle")
                    if let synopsis = detail.synopsis {
                        Text(synopsis).font(.footnote)
                    }
                    if let genres = detail.genres, !genres.isEmpty {
                        Text("Genres: " + genres.map(\.name).joined(separator: ", "))
                            .font(.footnote)
                    }
                    if let related = detail.relatedManga, !related.isEmpty {
                        Text("Related").font(.subheadline.bold())
                            .accessibilityIdentifier("malRelatedHeader")
                        ForEach(related, id: \.node.id) { rel in
                            Text("\(rel.relationTypeFormatted): \(rel.node.title)")
                                .font(.footnote)
                        }
                    }
                    if let recs = detail.recommendations, !recs.isEmpty {
                        Text("Recommendations").font(.subheadline.bold())
                            .accessibilityIdentifier("malRecommendationsHeader")
                        ForEach(recs, id: \.node.id) { rec in
                            Text("\(rec.node.title) (\(rec.numRecommendations))")
                                .font(.footnote)
                        }
                    }
                }
            }
        }
        .navigationTitle("MAL Debug")
    }

    private func search() {
        errorMessage = nil
        detail = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                results = try await MyAnimeListAPI.searchManga(title: query)
            } catch {
                errorMessage = error.localizedDescription
                results = []
            }
        }
    }

    /// Runs a synthetic scraped-source manga (no malId) through the entity resolver so
    /// the live fuzzy path can be verified end-to-end against the real MAL API.
    private func resolve() {
        resolvedText = nil
        isLoading = true
        let manga = Manga(id: "debug-\(UUID().uuidString)", sourceId: "weebcentral",
                          title: resolveQuery, description: "", status: "unknown",
                          year: nil, coverURL: nil, malId: nil)
        // `.shared`, not a fresh instance: `EntityResolutionStore` reads UserDefaults once
        // in `init` and never reloads, so a private one is frozen at its own construction
        // and writes into a cache nothing else reads (ADR-0010). For a debug view that
        // meant every resolve re-ran the live fuzzy path — the opposite of what this
        // screen is for, since it could never show a cache hit.
        let resolver = MALEntityResolver(store: .shared)
        Task {
            defer { isLoading = false }
            if let id = await resolver.malId(for: manga) {
                let title = (try? await MyAnimeListAPI.mangaDetail(id: id))?.title ?? "?"
                resolvedText = "Resolved to MAL id \(id): \(title)"
            } else {
                resolvedText = "No confident match"
            }
        }
    }

    /// Runs a synthetic MangaDex manga (no malId) through the full More Like This pipeline
    /// — forward-resolve the typed title → MAL id, MAL recommendations, reverse-resolve
    /// each back to MangaDex — so the end-to-end path can be verified against the live APIs.
    private func moreLikeThis() {
        mltResults = []
        isLoading = true
        let manga = Manga(id: "mlt-\(UUID().uuidString)", sourceId: "mangadex",
                          title: mltQuery, description: "", status: "unknown",
                          year: nil, coverURL: nil, malId: nil)
        Task {
            defer { isLoading = false }
            mltResults = await MoreLikeThisProvider().recommendations(for: manga)
        }
    }

    private func loadDetail(id: Int) {
        errorMessage = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                detail = try await MyAnimeListAPI.mangaDetail(id: id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack { MyAnimeListDebugView() }
}
