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
                // Highest-weighted tag wins the reason string; equal weights break on name so
                // the reason doesn't depend on which task group task happened to finish first.
                if let best = bestTag[m.id] {
                    if w > best.weight || (w == best.weight && name < best.name) {
                        bestTag[m.id] = (w, name)
                    }
                } else {
                    bestTag[m.id] = (w, name)
                }
            }
        }

        // Secondary sort on id, matching CompositeCandidateProvider: Swift's sort is not stable,
        // so without this two exactly-tied candidates can swap between runs — and a tie
        // straddling `limit` can change which titles are in the pool at all.
        return scores.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .compactMap { id, score in
                guard let m = mangaById[id] else { return nil }
                let reason = bestTag[id].map { "More \($0.name)" } ?? "Recommended"
                return ScoredManga(manga: m, score: score, reason: reason)
            }
    }
}

/// Collaborative candidates: for each of the profile's seeds, fetch MAL "more like this"
/// (already reverse-resolved to openable MangaDex titles) and score each result by
/// position × the seed's engagement weight, summed across seeds. Network-tolerant — an
/// empty seed result just contributes nothing.
struct MALCandidateProvider: CandidateProvider {
    let similar: SimilarTitlesProviding
    var perSeedLimit: Int = 8

    func candidates(for profile: TasteProfile,
                    excluding: Set<String>,
                    limit: Int) async throws -> [ScoredManga] {
        let seeds = profile.seeds
        guard !seeds.isEmpty else { return [] }

        // Per-seed recommendation lists, concurrently (bounded by seed count, ≤5).
        let lists: [(seed: SeedManga, recs: [Manga])] =
            await withTaskGroup(of: (SeedManga, [Manga]).self) { group in
                for seed in seeds {
                    let provider = similar
                    let per = perSeedLimit
                    group.addTask {
                        let recs = await provider.recommendations(for: seed.manga, limit: per)
                        return (seed, recs)
                    }
                }
                var out: [(SeedManga, [Manga])] = []
                for await r in group { out.append(r) }
                return out
            }

        var scores: [String: Double] = [:]
        var mangaById: [String: Manga] = [:]
        var bestSeed: [String: (weight: Double, title: String)] = [:]

        for (seed, recs) in lists {
            for (i, m) in recs.enumerated() where !excluding.contains(m.id) {
                scores[m.id, default: 0] += seed.weight * (1.0 / Double(1 + i))
                if mangaById[m.id] == nil { mangaById[m.id] = m }
                // Same determinism fix as bestTag: equal seed weights break on title.
                let title = seed.manga.title
                if let best = bestSeed[m.id] {
                    if seed.weight > best.weight || (seed.weight == best.weight && title < best.title) {
                        bestSeed[m.id] = (seed.weight, title)
                    }
                } else {
                    bestSeed[m.id] = (seed.weight, title)
                }
            }
        }

        // Secondary sort on id, matching CompositeCandidateProvider: Swift's sort is not stable,
        // so without this two exactly-tied candidates can swap between runs — and a tie
        // straddling `limit` can change which titles are in the pool at all.
        return scores.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .compactMap { id, score in
                guard let m = mangaById[id] else { return nil }
                let reason = bestSeed[id].map { "Because you read \($0.title)" } ?? "Recommended"
                return ScoredManga(manga: m, score: score, reason: reason)
            }
    }
}

/// Blends two candidate pools (tag + MAL). Each pool is normalized to [0, 1] (÷ its own
/// max) so the two signals are comparable, then combined `W_TAG·tag + W_MAL·mal` plus an
/// agreement bonus of `AGREEMENT_BONUS · √(tag · mal)`. Empty MAL pool ⇒ exactly the tag
/// ranking (graceful degradation).
///
/// The agreement term is the geometric mean of the two normalized scores, which tracks the
/// **weaker** of the two signals: two pools agreeing at the top of both earns close to the
/// full bonus, while incidental co-occurrence deep in both earns almost nothing. It is also
/// zero whenever either pool omits the title, so non-overlap needs no special case — the
/// loop below runs over the intersection purely as an optimization.
///
/// This replaced a flat `+0.25` for any overlap at all. Under the flat bonus a title ranked
/// ~40% of top strength in *both* pools outranked the single best recommendation either
/// signal had, because 0.25 is large against scores that live in [0, 1]. The two rules are
/// both defensible — "agreement wins" vs "strength wins, agreement breaks ties" — but they
/// are different products, and the second is the one chosen. See
/// Manga-ReaderTests/__Goldens__/foryou-ranking.txt for the effect on a worked example.
struct CompositeCandidateProvider: CandidateProvider {
    let tag: CandidateProvider
    let mal: CandidateProvider

    // Tuning constants. Non-private and injectable (the memberwise init defaults them, so
    // `CompositeCandidateProvider(tag:mal:)` still reads the same) for two reasons: the golden
    // harness in RecommendationGoldenTests reads them so its per-column breakdown stays correct
    // when they change, and an alternative weighting can be compared in a test without editing
    // this file. Defaults are the shipping values.
    var wTag = 1.0
    var wMal = 0.85
    /// Scales the geometric-mean agreement term. Deliberately left at the flat bonus's old
    /// value so the formula change could be evaluated on its own — note the geometric bonus is
    /// always ≤ the flat one it replaced, reaching 0.25 only when a title tops both pools, so
    /// this constant is a candidate for retuning *after* the shape change has been judged.
    var agreementBonus = 0.25

    func candidates(for profile: TasteProfile,
                    excluding: Set<String>,
                    limit: Int) async throws -> [ScoredManga] {
        async let tagPool = tag.candidates(for: profile, excluding: excluding, limit: limit)
        async let malPool = mal.candidates(for: profile, excluding: excluding, limit: limit)
        // Either pool failing degrades to empty (MAL failing ⇒ tag-only rail).
        let tags = (try? await tagPool) ?? []
        let mals = (try? await malPool) ?? []

        let tagNorm = Self.normalized(tags)
        let malNorm = Self.normalized(mals)

        var score: [String: Double] = [:]
        var manga: [String: Manga] = [:]
        var reason: [String: String] = [:]

        for c in tags {
            manga[c.manga.id] = c.manga
            reason[c.manga.id] = c.reason
            score[c.manga.id, default: 0] += wTag * (tagNorm[c.manga.id] ?? 0)
        }
        for c in mals {
            if manga[c.manga.id] == nil { manga[c.manga.id] = c.manga }
            reason[c.manga.id] = c.reason      // MAL reason preferred when MAL contributed
            score[c.manga.id, default: 0] += wMal * (malNorm[c.manga.id] ?? 0)
        }
        // Agreement: proportional to the geometric mean of the two normalized scores.
        for id in Set(tagNorm.keys).intersection(malNorm.keys) {
            let agreement = ((tagNorm[id] ?? 0) * (malNorm[id] ?? 0)).squareRoot()
            score[id, default: 0] += agreementBonus * agreement
        }

        // Secondary sort on id keeps the order stable for exactly-tied scores, so the
        // "See all" grid (which uses the straight ranking) doesn't reshuffle between opens.
        return score.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .compactMap { id, value in
                guard let m = manga[id] else { return nil }
                return ScoredManga(manga: m, score: value, reason: reason[id] ?? "Recommended")
            }
    }

    /// id → score ÷ pool max, in [0, 1]. Empty/all-zero pool → empty map.
    private static func normalized(_ pool: [ScoredManga]) -> [String: Double] {
        guard let max = pool.map(\.score).max(), max > 0 else { return [:] }
        return Dictionary(pool.map { ($0.manga.id, $0.score / max) },
                          uniquingKeysWith: { first, _ in first })
    }
}
