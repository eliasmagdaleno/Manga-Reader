//
//  CandidateProvider.swift
//  Manga-Reader
//
//  Turns a TasteProfile into ranked recommendation candidates. The seam a future
//  MyAnimeList/Jikan provider slips behind. v1 scores by *query provenance*: a title
//  surfaced by several of the user's top-tag feeds sums several contributions, so
//  multi-tag overlap falls out without ever fetching a candidate's detail.
//

import Foundation

/// A ranked recommendation: the manga, its score, and a human reason ("More Action").
struct ScoredManga: Identifiable {
    let manga: Manga
    let score: Double
    let reason: String
    var id: String { manga.id }
}

protocol CandidateProvider {
    /// Ranked candidates for a profile, already excluding `excluding`, capped at `limit`.
    func candidates(for profile: TasteProfile,
                    excluding: Set<String>,
                    limit: Int) async throws -> [ScoredManga]
}

/// v1 provider: fetch the top-K tag feeds and score by provenance.
struct TagCandidateProvider: CandidateProvider {
    let source: MangaSource
    var topK: Int = 6
    var perTagLimit: Int = 20

    func candidates(for profile: TasteProfile,
                    excluding: Set<String>,
                    limit: Int) async throws -> [ScoredManga] {
        let tagIds = Array(profile.orderedTagIds.prefix(topK))
        guard !tagIds.isEmpty else { return [] }

        // Fetch each tag feed concurrently; a failing feed is skipped, not fatal.
        let lists: [(tagId: String, manga: [Manga])] =
            await withTaskGroup(of: (String, [Manga]).self) { group in
                for tid in tagIds {
                    let name = profile.tagName[tid] ?? ""
                    let src = source
                    let per = perTagLimit
                    group.addTask {
                        guard !name.isEmpty else { return (tid, []) }
                        let res = try? await src.mangaByTag(tag: name, limit: per, offset: 0)
                        return (tid, res ?? [])
                    }
                }
                var out: [(String, [Manga])] = []
                for await r in group { out.append(r) }
                return out
            }

        var scores: [String: Double] = [:]
        var mangaById: [String: Manga] = [:]
        var bestTag: [String: (weight: Double, name: String)] = [:]

        for (tid, list) in lists {
            let w = profile.weights[tid] ?? 0
            let name = profile.tagName[tid] ?? ""
            for (i, m) in list.enumerated() where !excluding.contains(m.id) {
                scores[m.id, default: 0] += w * (1.0 / Double(1 + i))   // rating-desc: earlier = better
                if mangaById[m.id] == nil { mangaById[m.id] = m }
                if (bestTag[m.id]?.weight ?? -1) < w { bestTag[m.id] = (w, name) }
            }
        }

        return scores.sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { id, score in
                guard let m = mangaById[id] else { return nil }
                let reason = bestTag[id].map { "More \($0.name)" } ?? "Recommended"
                return ScoredManga(manga: m, score: score, reason: reason)
            }
    }
}
