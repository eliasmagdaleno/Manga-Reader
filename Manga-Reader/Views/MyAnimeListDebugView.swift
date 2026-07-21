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
