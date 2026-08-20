//
//  SimulatorSeed.swift
//  Manga-ReaderTests
//
//  The seeded-simulator fixture, expressed as data plus a builder that drives the **real**
//  stores. Lives in the test target because it is a fixture tool, not app behaviour.
//
//  **Why it drives the stores rather than writing JSON.** `works.json` is written by
//  `WorkStore`'s own encoder. Hand-rolling that file means maintaining a second definition
//  of the on-disk shape, and the day `Work` gains a field the hand-rolled copy keeps
//  decoding — into something quietly wrong. Minting through `WorkStore.mint` and upgrading
//  through `WorkStore.apply` is the same route `MetadataUpgradeQueue` takes in the app, so
//  a shape change breaks the seed loudly, in a test, instead of silently in a fixture.
//

import Foundation
@testable import Manga_Reader

enum SimulatorSeed {

    /// One seeded Work: a Listing to mint from, plus the AniList record that upgrades it.
    ///
    /// `tags` carries AniList's **ranked** axis with real ranks, because the ≥ 60 floor in
    /// `TagPairSeeding` is what decides whether a Work contributes a seed pair at all — a
    /// fixture with plausible names and invented ranks would clear or miss that gate for
    /// reasons unrelated to the app.
    struct Row {
        let title: String
        let sourceId: String
        let mangaId: String
        let malId: Int?
        let anilistId: Int
        let genres: [String]
        let tags: [RankedTag]
        let status: PublicationStatus
        let chapterTotal: Int?
    }

    /// Mints each row's Listing and upgrades it with the row's AniList record, exactly as
    /// the upgrade queue would.
    @MainActor
    static func apply(_ rows: [Row], to store: WorkStore) {
        for row in rows {
            let listing = Manga(id: row.mangaId,
                                sourceId: row.sourceId,
                                title: row.title,
                                description: "",
                                status: row.status == .finished ? "completed" : "ongoing",
                                year: nil,
                                coverURL: nil,
                                malId: row.malId)
            let id = store.mint(from: listing)
            store.apply(AniListWork(anilistId: row.anilistId,
                                    malId: row.malId,
                                    knownTitles: [row.title],
                                    genres: row.genres,
                                    tags: row.tags,
                                    publicationStatus: row.status,
                                    chapterTotal: row.chapterTotal),
                        to: id)
        }
    }

    /// A small hand-written set, used by the builder's own tests. The real fixture is
    /// harvested from AniList into a committed snapshot; this stays small so the unit
    /// tests stay fast and readable.
    static let sampleRows: [Row] = [
        Row(title: "Berserk", sourceId: "mangadex", mangaId: "md-berserk",
            malId: 2, anilistId: 30002,
            genres: ["Action", "Adventure", "Drama"],
            tags: [RankedTag(name: "Male Protagonist", rank: 92),
                   RankedTag(name: "Tragedy", rank: 88),
                   RankedTag(name: "Gore", rank: 85)],
            status: .releasing, chapterTotal: nil),
        Row(title: "Vinland Saga", sourceId: "mangadex", mangaId: "md-vinland",
            malId: 642, anilistId: 30642,
            genres: ["Action", "Adventure", "Drama"],
            tags: [RankedTag(name: "Male Protagonist", rank: 90),
                   RankedTag(name: "Tragedy", rank: 75),
                   RankedTag(name: "Historical", rank: 95)],
            status: .releasing, chapterTotal: nil),
        Row(title: "Vagabond", sourceId: "mangadex", mangaId: "md-vagabond",
            malId: 656, anilistId: 30656,
            genres: ["Action", "Adventure", "Drama"],
            tags: [RankedTag(name: "Male Protagonist", rank: 94),
                   RankedTag(name: "Tragedy", rank: 70),
                   RankedTag(name: "Historical", rank: 90)],
            status: .hiatus, chapterTotal: nil),
    ]
}
