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
    /// tagId → weight in [0, 1] (normalized so the strongest tag is 1).
    let weights: [String: Double]
    /// tagId → display name, for querying mangaByTag and building reason strings.
    let tagName: [String: String]
    /// tagIds sorted by weight, descending.
    let orderedTagIds: [String]
    /// How many distinct read manga contributed tags — drives the cold-start gate.
    let taggedMangaCount: Int
    /// Top read/saved manga (materialized), highest engagement first — MAL rec seeds.
    let seeds: [SeedManga]

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

    static func build(history: [ReadingEntry],
                      savedIds: Set<String>,
                      tagCache: [String: [Tag]],
                      moreLikeThis: Set<String>,
                      now: Date,
                      libraryItems: [Manga] = [],
                      seedLimit: Int = 5) -> TasteProfile {
        var entriesByManga: [String: [ReadingEntry]] = [:]
        for e in history { entriesByManga[e.mangaId, default: []].append(e) }

        var raw: [String: Double] = [:]
        var names: [String: String] = [:]
        var mangaWeight: [String: Double] = [:]   // per-manga engagement weight, for seeds
        var taggedCount = 0

        for (mangaId, entries) in entriesByManga {
            guard let tags = tagCache[mangaId], !tags.isEmpty else { continue }
            taggedCount += 1

            let distinctChapters = Set(entries.map(\.chapterNumber)).count
            let latest = entries.max { $0.updatedAt < $1.updatedAt }!
            let finished = latest.pageCount > 0 && latest.page >= latest.pageCount - 1
            let days = max(0, now.timeIntervalSince(latest.updatedAt) / 86_400)
            let recency = pow(0.5, days / 30.0)                 // 30-day half-life

            var w = recency * (1.0
                               + log2(1.0 + Double(distinctChapters))
                               + (finished ? 1.5 : 0.0)
                               + (savedIds.contains(mangaId) ? 1.0 : 0.0))
            if moreLikeThis.contains(mangaId) { w *= 2.0 }
            mangaWeight[mangaId] = w

            for t in tags {
                raw[t.id, default: 0] += w * groupWeight(t.group)
                names[t.id] = t.name
            }
        }

        let seeds = makeSeeds(mangaWeight: mangaWeight, entriesByManga: entriesByManga,
                              libraryItems: libraryItems, limit: seedLimit)

        guard let maxW = raw.values.max(), maxW > 0 else {
            return TasteProfile(weights: [:], tagName: [:], orderedTagIds: [],
                                taggedMangaCount: taggedCount, seeds: seeds)
        }
        let normalized = raw.mapValues { $0 / maxW }
        let ordered = normalized.sorted { $0.value > $1.value }.map(\.key)
        return TasteProfile(weights: normalized, tagName: names, orderedTagIds: ordered,
                            taggedMangaCount: taggedCount, seeds: seeds)
    }

    /// Top `limit` manga by engagement weight, materialized to `Manga`: prefer a saved
    /// library entry (carries malId); else synthesize from a history entry (title/cover).
    private static func makeSeeds(mangaWeight: [String: Double],
                                  entriesByManga: [String: [ReadingEntry]],
                                  libraryItems: [Manga],
                                  limit: Int) -> [SeedManga] {
        let libraryById = Dictionary(libraryItems.map { ($0.id, $0) },
                                     uniquingKeysWith: { first, _ in first })
        return mangaWeight.sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { id, weight -> SeedManga? in
                if let saved = libraryById[id] {
                    return SeedManga(manga: saved, weight: weight)
                }
                guard let e = entriesByManga[id]?.first else { return nil }
                let manga = Manga(id: id, sourceId: e.sourceId ?? "mangadex",
                                  title: e.mangaTitle, description: "", status: "unknown",
                                  year: nil, coverURL: e.coverURL, malId: nil)
                return SeedManga(manga: manga, weight: weight)
            }
    }
}
