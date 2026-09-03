//
//  AniListPool.swift
//  MangaCarta
//
//  Slice 3 of ADR-0011: the pool's data shapes and its **pure core**.
//
//  The core is the "score first" step, and it is total, synchronous and network-free:
//  given the seed pairs and what each pair's query returned, it ranks every candidate.
//  `withinPool` is computable from the AniList response alone, so the whole pool can be
//  ranked for nothing and the expensive half — one live MangaDex title search per
//  unresolved `idMal` — is spent only on the head. **The ordering is the decision**; the
//  constants below are tunable, doing it the other way round is not fixable without
//  restructuring.
//
//  Everything cached here is *raw material*, never a score: `min(rank)` is a frozen
//  property of a title, `pairWeight` is not — engagement is recency-decayed against
//  `Date()`. Membership is expensive to refresh; ordering is free.
//

import Foundation

/// What one seed pair contributed to one candidate: `min(rank_a, rank_b)` **for that
/// candidate**, not for the Work that seeded the pair.
struct PairContribution: Codable, Equatable {
    let pair: TagPair
    /// 0–100. The query floor guarantees >= 60 for both legs, so this is >= 60 in
    /// practice; it is stored rather than recomputed because the AniList response it came
    /// from is thrown away.
    let minimumRank: Int
}

/// A candidate before resolution — still an AniList record.
struct PoolCandidate: Equatable {
    let work: AniListWork
    /// Every seed pair whose query surfaced this title. More than one is the *common*
    /// case, not an edge one: the 2026-08-03 measurement found the top 5 seeds contain a
    /// triangle over three tags.
    let contributions: [PairContribution]
}

/// A candidate after resolution, as cached.
struct PooledCandidate: Codable, Equatable {
    let manga: Manga
    let contributions: [PairContribution]
}

/// One cache entry: a pool, the seeds that define it, and when it was built.
struct AniListPoolRecord: Codable, Equatable {
    /// Fourteen days for a populated pool — the number `MetadataSnapshot.releasingTTL` and
    /// `EntityResolutionStore.missTTL` already use for "a stale answer is worth re-asking
    /// eventually".
    static let ttl: TimeInterval = 14 * 24 * 60 * 60

    /// **Twenty-four hours for an empty one** — the single place the 14-day number does not
    /// apply. An empty pool is a normal outcome under AND semantics *and* is exactly what a
    /// transient AniList hiccup returning HTTP 200 with an empty page looks like, and the
    /// two are indistinguishable. Not caching empties at all would re-issue 5 requests on
    /// every Home appearance forever for a sparse-taste reader; caching them for a
    /// fortnight would eat two weeks of dark rail for a blip.
    static let emptyTTL: TimeInterval = 24 * 60 * 60

    /// The entry's identity. Sorted canonically so two orderings of the same seeds are one
    /// key — a taste shift that changes the seeds invalidates the entry for free.
    let seeds: [TagPair]
    let fetchedAt: Date
    let candidates: [PooledCandidate]

    init(seeds: [TagPair], fetchedAt: Date, candidates: [PooledCandidate]) {
        self.seeds = Self.canonical(seeds)
        self.fetchedAt = fetchedAt
        self.candidates = candidates
    }

    static func canonical(_ seeds: [TagPair]) -> [TagPair] {
        seeds.sorted()
    }

    func matches(seeds other: [TagPair]) -> Bool {
        seeds == Self.canonical(other)
    }

    func isFresh(now: Date = Date()) -> Bool {
        now.timeIntervalSince(fetchedAt) < (candidates.isEmpty ? Self.emptyTTL : Self.ttl)
    }
}

// MARK: - The pure core

/// How many results each pair's query asks AniList for.
let poolPerPairLimit = 12

/// The de-duped ceiling on a pool, matching `RecommendationEngine.poolLimit` so this pool
/// is not structurally larger than the ones beside it.
let poolCandidateCap = 40

/// How many of the ranked candidates get a resolution budget. A title ranked 47th will
/// never reach a rail that shows a handful of cards, and every unresolved `idMal` costs one
/// live MangaDex title search.
let poolResolveLimit = 12

/// `pairWeight(p) × min(rank_a(c), rank_b(c)) / 100`, summed over the pairs that surfaced
/// `c` — ADR-0011's `withinPool`, computed from raw material at read time.
///
/// Summing rather than taking the best contribution is deliberate and knowingly unbounded
/// in the number of contributing pairs: it is the same "multi-signal overlap" property both
/// existing pools have. The 2026-08-04 measurement is what says the redundancy this exposes
/// it to is small in practice (2 of 29 titles in all three triangle edges); the ADR carries
/// the revisit trigger.
func withinPoolScore(_ contributions: [PairContribution],
                     weights: [TagPair: Double]) -> Double {
    contributions.reduce(0) { total, c in
        total + (weights[c.pair] ?? 0) * Double(c.minimumRank) / 100
    }
}

/// Rank every candidate the five queries returned, **before any of them is resolved**.
///
/// De-dupes by AniList id across pairs, accumulating one `PairContribution` per pair that
/// surfaced the title. Candidates without an `idMal` are dropped here rather than later:
/// reverse resolution goes through `EntityResolutionStore.reverseResolution(malId:)`, so a
/// title with no MyAnimeList id has no path to an openable MangaDex listing and would only
/// occupy a resolution slot to fail.
func rankPoolCandidates(results: [(pair: SeededTagPair, works: [AniListWork])],
                        cap: Int = poolCandidateCap) -> [PoolCandidate] {

    var byAniListId: [Int: PoolCandidate] = [:]
    var weights: [TagPair: Double] = [:]

    for (seeded, works) in results {
        weights[seeded.pair] = seeded.weight
        for work in works {
            guard work.malId != nil else { continue }
            // The candidate's *own* ranks for the two legs. Absent means the response did
            // not carry the tag: no claim, so no contribution — rather than a zero term,
            // which would look like a scored-and-weak match.
            guard let rankA = work.rank(of: seeded.pair.a),
                  let rankB = work.rank(of: seeded.pair.b) else { continue }
            let contribution = PairContribution(pair: seeded.pair,
                                                minimumRank: min(rankA, rankB))

            if let existing = byAniListId[work.anilistId] {
                byAniListId[work.anilistId] = PoolCandidate(
                    work: existing.work,
                    contributions: existing.contributions + [contribution])
            } else {
                byAniListId[work.anilistId] = PoolCandidate(work: work,
                                                            contributions: [contribution])
            }
        }
    }

    // Score desc, then AniList id — the same total-order discipline as everywhere else in
    // this subsystem. Swift's sort is not stable and ties straddling `cap` would otherwise
    // change which titles are in the pool at all between identical runs.
    //
    // Written as explicit steps rather than one chain: the fused
    // map/sorted/prefix/map defeated the type checker outright.
    var scored: [(candidate: PoolCandidate, score: Double)] = []
    for candidate in byAniListId.values {
        scored.append((candidate, withinPoolScore(candidate.contributions, weights: weights)))
    }
    scored.sort { left, right in
        if left.score != right.score { return left.score > right.score }
        return left.candidate.work.anilistId < right.candidate.work.anilistId
    }

    var out: [PoolCandidate] = []
    for entry in scored.prefix(cap) {
        // Contributions in a fixed order too, so the cached record — and slice 4's golden
        // — does not diff on dictionary iteration order.
        let ordered = entry.candidate.contributions.sorted { $0.pair < $1.pair }
        out.append(PoolCandidate(work: entry.candidate.work, contributions: ordered))
    }
    return out
}

extension AniListWork {
    /// This title's own rank for a tag name, case-insensitively. `nil` when the record does
    /// not carry the tag at all, which is distinct from carrying it at rank 0.
    func rank(of name: String) -> Int? {
        tags.first { $0.name.lowercased() == name.lowercased() }?.rank
    }
}

// MARK: - Reason strings

/// `"More Dungeon + Necromancy"`, in the existing `"More \(name)"` idiom.
///
/// The pair named is the one contributing the **largest term** to this candidate's
/// `withinPool` score, lexicographic tiebreak — so the reason explains the title's actual
/// placement rather than telling a second, unrelated story about it. Naming the
/// highest-weighted *seed* instead would explain a title that scraped in at 61 on the top
/// pair, and dominated on the fourth, by the pair it barely matched.
///
/// **Spoiler suppression degrades the text; it never re-picks the pair.** When the winning
/// pair is `Reincarnation ∧ Magic` the string is `"More Magic"` — falling through to the
/// next clean pair would print a weaker contribution than the one that placed the title,
/// breaking the trace back to the score.
func poolReason(for contributions: [PairContribution],
                weights: [TagPair: Double],
                vocabulary: TagVocabulary) -> String {
    // Spelled out rather than written as a `map` producing an inferred tuple: the tuple
    // form made the dictionary lookup, the `??`, the `Double` conversion, the arithmetic
    // and the destructuring `sorted` closure one expression for the type checker to solve,
    // and it timed out on CI while compiling locally. A named type and an annotated
    // binding solve it in pieces. This is the second such timeout in this file — see
    // ADR-0011's revisit trigger.
    struct RankedPair {
        let pair: TagPair
        let term: Double
    }
    let ranked: [RankedPair] = contributions.map { contribution in
        let weight: Double = weights[contribution.pair] ?? 0
        let rank = Double(contribution.minimumRank) / 100
        return RankedPair(pair: contribution.pair, term: weight * rank)
    }
    .sorted { left, right in
        if left.term != right.term { return left.term > right.term }
        return left.pair < right.pair
    }
    guard let winner = ranked.first?.pair else { return "Recommended" }

    let legs = [winner.a, winner.b].filter { !vocabulary.isGeneralSpoiler($0) }
    switch legs.count {
    case 2: return "More \(legs[0]) + \(legs[1])"
    case 1: return "More \(legs[0])"
    default: return "Recommended"
    }
}
