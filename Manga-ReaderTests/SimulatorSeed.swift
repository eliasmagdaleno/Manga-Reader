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
        /// One chapter the seeded user has read, and how far into it they got.
        ///
        /// `pageCount` matters as much as `page`: "finished" is `page == pageCount - 1`,
        /// and Continue Reading, the in-progress badge and the taste signals all read that
        /// comparison rather than a flag. A fixture with every entry parked mid-chapter
        /// would show a home screen the app can never actually reach.
        struct Read {
            let chapterId: String
            let chapterNumber: String
            let page: Int
            let pageCount: Int
        }

        let title: String
        let sourceId: String
        let mangaId: String
        let malId: Int?
        let anilistId: Int
        let genres: [String]
        let tags: [RankedTag]
        let status: PublicationStatus
        let chapterTotal: Int?
        /// Chapters read, oldest first. Empty for a Work the user only saved.
        let reading: [Read]
        /// Whether the Work sits in the library.
        let isSaved: Bool
    }

    /// The defaults keys the seed writes. The suite it writes into also picks up
    /// Foundation's own bookkeeping, and `defaults.json` must carry only what the app
    /// itself would have written — anything else is noise installed into a real domain.
    ///
    /// `taste.notInterested` / `taste.moreLikeThis` are deliberately absent: they hold
    /// explicit user feedback, and a fixture that pre-dismisses titles would silently
    /// subtract from every recommendation run made against it.
    static let seededDefaultsKeys = ["history.entries", "history.readMarks", "library.items"]

    /// The seeded keys as key -> base64, ready for `simctl spawn booted defaults write
    /// <domain> <key> -data <hex>` — the one mechanism verified to round-trip real `Data`
    /// into a simulator app's defaults.
    static func defaultsPayload(from defaults: UserDefaults) -> [String: String] {
        var payload: [String: String] = [:]
        for key in seededDefaultsKeys {
            guard let data = defaults.data(forKey: key) else { continue }
            payload[key] = data.base64EncodedString()
        }
        return payload
    }

    /// Mints each row's Listing, upgrades it with the row's AniList record, then reads and
    /// saves it — each through the store that owns that state, exactly as the app would.
    ///
    /// **Timestamps are "now".** `HistoryStore.record` stamps `Date()` and exposes no way
    /// to backdate, so the seeded history lands as one day's reading rather than spread
    /// across weeks. Ordering is still right — `record` prepends, so applying oldest-first
    /// leaves the newest entry at index 0 — and every consumer this fixture exists for
    /// reads order and position, not age. The History tab will show one date header.
    @MainActor
    static func apply(_ rows: [Row], to store: WorkStore,
                      history: HistoryStore? = nil, library: LibraryStore? = nil) {
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

            // Reading and saving mint on their own (ADR-0007). They are handed the *same*
            // listing, so they resolve to the Work minted above instead of a provisional
            // twin the AniList upgrade never touched.
            for read in row.reading {
                history?.record(manga: listing,
                                chapter: Chapter(id: read.chapterId, number: read.chapterNumber,
                                                 title: nil),
                                position: ReadingPosition(page: read.page),
                                pageCount: read.pageCount)
            }
            if row.isSaved { library?.toggle(listing) }
        }
        // `record` writes through a throttle; without this the last entries of the run
        // would still be unwritten when the payload is read.
        history?.flush()
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
            status: .releasing, chapterTotal: nil,
            reading: [Row.Read(chapterId: "ch-berserk-1", chapterNumber: "1",
                               page: 41, pageCount: 42),
                      Row.Read(chapterId: "ch-berserk-2", chapterNumber: "2",
                               page: 12, pageCount: 40)],
            isSaved: true),
        Row(title: "Vinland Saga", sourceId: "mangadex", mangaId: "md-vinland",
            malId: 642, anilistId: 30642,
            genres: ["Action", "Adventure", "Drama"],
            tags: [RankedTag(name: "Male Protagonist", rank: 90),
                   RankedTag(name: "Tragedy", rank: 75),
                   RankedTag(name: "Historical", rank: 95)],
            status: .releasing, chapterTotal: nil,
            reading: [Row.Read(chapterId: "ch-vinland-1", chapterNumber: "1",
                               page: 53, pageCount: 54)],
            isSaved: true),
        Row(title: "Vagabond", sourceId: "mangadex", mangaId: "md-vagabond",
            malId: 656, anilistId: 30656,
            genres: ["Action", "Adventure", "Drama"],
            tags: [RankedTag(name: "Male Protagonist", rank: 94),
                   RankedTag(name: "Tragedy", rank: 70),
                   RankedTag(name: "Historical", rank: 90)],
            status: .hiatus, chapterTotal: nil,
            reading: [], isSaved: false),
    ]
}
