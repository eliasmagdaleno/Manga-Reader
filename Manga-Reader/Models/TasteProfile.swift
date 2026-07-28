//
//  TasteProfile.swift
//  Manga-Reader
//
//  A normalized tag-weight vector derived from reading history. Pure value type —
//  no I/O — so it's trivially testable. Built by RecommendationEngine from
//  HistoryStore + LibraryStore + TasteProfileStore.
//

import Foundation

/// A recommendation seed: a manga the user engaged with, plus its engagement weight.
struct SeedManga {
    let manga: Manga
    let weight: Double
}

struct TasteProfile {
    /// One Work's reading history plus the tags to score it by — the **resolved**
    /// input `build` needs. Assembled by the caller (`RecommendationEngine`, which
    /// owns the `WorkStore`) so this file stays a pure value type with no I/O.
    struct WorkSignal {
        let workId: WorkID
        /// Every Listing's entries for this Work, from every source.
        let entries: [ReadingEntry]
        /// The Work's snapshot tags. Empty when the upgrade queue hasn't reached it.
        let tags: [QueryableTag]
    }

    /// tag key → weight in [0, 1] (normalized so the strongest tag is 1).
    let weights: [String: Double]
    /// tag key → display name, for querying mangaByTag and building reason strings.
    let tagName: [String: String]
    /// tag keys sorted by weight descending, ties broken by key so the order can't
    /// depend on dictionary iteration (which is randomized per process).
    let orderedTagKeys: [String]
    /// How many distinct read manga contributed tags — drives the cold-start gate.
    let taggedMangaCount: Int
    /// Top read/saved manga (materialized), highest engagement first — MAL rec seeds.
    let seeds: [SeedManga]
    /// Engagement weight per Work, which the upgrade queue orders on (ADR-0008). Exposed
    /// so there is **one** definition of engagement: a queue computing its own
    /// recency×chapters score would diverge from this one the first time either is tuned.
    ///
    /// Covers every Work with reading history, **tagged or not** (ADR-0009). An untagged
    /// read Work contributes nothing to `weights` but is the highest-value thing the queue
    /// can fetch, so it still has to be orderable. Works with no history are absent, and
    /// the queue sorts them last.
    ///
    /// `var` with a default purely so the memberwise init keeps it optional — the tests
    /// that build a profile from literal weights to isolate *ranking* have no Works at
    /// all, and `[:]` is the honest value there. Never mutated. (`LibraryItem` uses the
    /// same idiom.)
    var workWeights: [WorkID: Double] = [:]

    var isEmpty: Bool { weights.isEmpty }

    /// Genre matters most; format (oneshot, long-strip…) least.
    static func groupWeight(_ group: String) -> Double {
        switch group {
        case "genre":  return 1.0
        case "theme":  return 0.7
        case "format": return 0.3
        case "content": return 0.5
        default:       return 0.5
        }
    }

    /// The tag key space. A Work's snapshot carries a name and an optional group but
    /// **no id**, so names are the only key both MangaDex and AniList can supply —
    /// and normalizing means two sources naming the same genre are one signal.
    static func tagKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Aggregates by **Work**, not by Listing. Two Listings of one manga are one thing
    /// the user reads, so they yield a single engagement weight and a single seed.
    ///
    /// `savedIds` and `moreLikeThis` stay Listing-keyed (ADR-0007 keeps the edges that
    /// way), so a Work counts as saved or boosted when *any* of its Listings is.
    static func build(signals: [WorkSignal],
                      savedIds: Set<String>,
                      moreLikeThis: Set<String>,
                      now: Date,
                      libraryItems: [Manga] = [],
                      seedLimit: Int = 5) -> TasteProfile {
        var raw: [String: Double] = [:]
        var names: [String: String] = [:]
        var weighted: [(signal: WorkSignal, weight: Double)] = []
        var workWeights: [WorkID: Double] = [:]
        var taggedCount = 0

        for signal in signals where !signal.entries.isEmpty {
            let entries = signal.entries
            // Chapter numbering is per-source (ADR-0004 accepts this), so merging
            // across Listings can under-count. Accepted: this is a heuristic weight.
            let distinctChapters = Set(entries.map(\.chapterNumber)).count
            let latest = entries.max { $0.updatedAt < $1.updatedAt }!
            let finished = latest.pageCount > 0 && latest.page >= latest.pageCount - 1
            let days = max(0, now.timeIntervalSince(latest.updatedAt) / 86_400)
            let recency = pow(0.5, days / 30.0)                 // 30-day half-life
            let isSaved = entries.contains { savedIds.contains($0.mangaId) }

            var w = recency * (1.0
                               + log2(1.0 + Double(distinctChapters))
                               + (finished ? 1.5 : 0.0)
                               + (isSaved ? 1.0 : 0.0))
            if entries.contains(where: { moreLikeThis.contains($0.mangaId) }) { w *= 2.0 }
            // Every read Work is orderable for the upgrade queue, tagged or not (ADR-0009).
            workWeights[signal.workId] = w

            // A Work the upgrade queue hasn't reached has no tags yet, so it contributes
            // nothing to the tag vector and is not a seed — seeds are catalog queries, and
            // an untagged Work is a worse question to ask. It still has a weight above.
            guard !signal.tags.isEmpty else { continue }
            taggedCount += 1
            weighted.append((signal, w))

            for t in signal.tags {
                let key = tagKey(t.name)
                // A nil group is an AniList genre, which ADR-0007 says is genre-level.
                // Letting it fall through to `default: 0.5` would quietly halve the
                // signal from every AniList-resolved Work.
                raw[key, default: 0] += w * groupWeight(t.group ?? "genre")
                names[key] = t.name
            }
        }

        let seeds = makeSeeds(weighted: weighted, libraryItems: libraryItems, limit: seedLimit)

        guard let maxW = raw.values.max(), maxW > 0 else {
            return TasteProfile(weights: [:], tagName: [:], orderedTagKeys: [],
                                taggedMangaCount: taggedCount, seeds: seeds,
                                workWeights: workWeights)
        }
        let normalized = raw.mapValues { $0 / maxW }
        // Ties break on the key: without it, equally-weighted tags come out in
        // dictionary order, which is randomized per process.
        let ordered = normalized
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map(\.key)
        return TasteProfile(weights: normalized, tagName: names, orderedTagKeys: ordered,
                            taggedMangaCount: taggedCount, seeds: seeds,
                            workWeights: workWeights)
    }

    /// Top `limit` Works by engagement weight, each materialized to one representative
    /// `Manga`: prefer a saved library entry among its Listings (that one carries
    /// `malId`), else the most recently read entry.
    private static func makeSeeds(weighted: [(signal: WorkSignal, weight: Double)],
                                  libraryItems: [Manga],
                                  limit: Int) -> [SeedManga] {
        let libraryById = Dictionary(libraryItems.map { ($0.id, $0) },
                                     uniquingKeysWith: { first, _ in first })
        return weighted
            .sorted {
                guard $0.weight == $1.weight else { return $0.weight > $1.weight }
                return ($0.signal.entries.first?.mangaId ?? "") < ($1.signal.entries.first?.mangaId ?? "")
            }
            .prefix(limit)
            .compactMap { item -> SeedManga? in
                if let saved = item.signal.entries.compactMap({ libraryById[$0.mangaId] }).first {
                    return SeedManga(manga: saved, weight: item.weight)
                }
                guard let e = item.signal.entries.max(by: { $0.updatedAt < $1.updatedAt })
                        ?? item.signal.entries.first else { return nil }
                let manga = Manga(id: e.mangaId, sourceId: e.sourceId ?? "mangadex",
                                  title: e.mangaTitle, description: "", status: "unknown",
                                  year: nil, coverURL: e.coverURL, malId: nil)
                return SeedManga(manga: manga, weight: item.weight)
            }
    }
}
