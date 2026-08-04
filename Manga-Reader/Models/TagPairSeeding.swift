//
//  TagPairSeeding.swift
//  Manga-Reader
//
//  Slice 2 of ADR-0011: the tag pairs that seed the AniList pool.
//
//  A pure function over Works plus the cached vocabulary — no store, no network. It is
//  handed `TasteProfile.workWeights` rather than the profile itself, so that it *cannot*
//  compute a second definition of engagement (ADR-0009: one definition, never a second
//  one computed by whoever needs it).
//
//  Why pairs at all: AniList's `tag_in` is **AND**, so a single tag is just a popularity
//  list while a conjunction is expressive. Both legs must come from one Work — a pair
//  assembled across two Works is a claim nobody made.
//

import Foundation

/// Two ranked tags that co-occur in one Work. **Canonical**: the two names are sorted on
/// init, so `Dungeon AND Revenge` and `Revenge AND Dungeon` are the same value and the same
/// hash. Without that, two Works listing their tags in different orders would split one
/// pair's weight across two dictionary keys and silently shorten the top N.
struct TagPair: Hashable, Codable {
    let a: String
    let b: String

    init(_ x: String, _ y: String) {
        // Case-insensitive so the canonical form does not depend on a provider's casing,
        // but the original spelling is what gets kept -- it goes back to AniList as a query.
        if x.lowercased() <= y.lowercased() {
            (a, b) = (x, y)
        } else {
            (a, b) = (y, x)
        }
    }
}

/// One definition of the pair ordering, because there are now four places that need it —
/// the seeding tiebreak, the cache key's canonical form, the ordering of a candidate's
/// contributions, and the reason-string tiebreak. Each is load-bearing for the same reason:
/// Swift's sort is not guaranteed stable, so without a *total* order these all diff between
/// runs on identical data. Four hand-spelled copies of a comparator that must agree is how
/// they stop agreeing.
extension TagPair: Comparable {
    static func < (lhs: TagPair, rhs: TagPair) -> Bool {
        lhs.a != rhs.a ? lhs.a < rhs.a : lhs.b < rhs.b
    }
}

/// A pair and the strength of the claim behind it. The weight travels with the pair
/// deliberately: the provider weights its results by it, and a golden diff is far more
/// readable with the number visible than with five bare names.
struct SeededTagPair: Equatable {
    let pair: TagPair
    let weight: Double
    /// The Works that carried **both** legs at rank >= 60 and therefore contributed a term
    /// to `weight`. This is what the >= 3 Works gate counts, and it must come from here
    /// rather than from a separate `contributingWorks(...)` helper: a second walk of the
    /// admission logic is a second definition of "contributing", and the two would
    /// eventually disagree — which is the exact failure the gate exists to prevent.
    ///
    /// Per-pair rather than one summary union, for the same reason `weight` travels with
    /// the pair: it makes overlapping pairs visibly draw on the same Work ids instead of
    /// leaving that to be inferred.
    let contributingWorks: Set<WorkID>
}

/// AniList's per-tag floor, applied to **every** leg of a conjunction. 60 excludes noise;
/// it does not rank. Higher thins a pair fast -- `Dungeon AND Iyashikei` is empty at 80.
let minimumSeedTagRank = 60

/// Excluded from **seeding only** -- these tags stay available for scoring. `Technical` is
/// format facts (Full Color, Four-koma) and `Cast-Main Cast` is near-universal traits (Male
/// Protagonist); as query legs they describe everything and select nothing.
///
/// `Demographic` (Shounen, Seinen, …) widens ADR-0011's original two on evidence: the real
/// store seeds four demographic pairs in its top 20. Same argument -- a demographic label
/// covers an enormous slice of the catalogue, so as a leg it barely narrows the AND. It is
/// a *weaker* case than the other two, because `Seinen AND Tragedy` is at least a coherent
/// question where `Full Color AND Tragedy` is not; the deciding point is that none of the
/// four reached the cut anyway, so excluding them costs nothing observable today and stops
/// a near-tautology from displacing a real pair once the store grows.
let seedExcludedTagCategories: Set<String> = ["Technical", "Cast-Main Cast", "Demographic"]

/// The top `limit` tag pairs, heaviest first.
///
///     pairWeight(a,b) = Σ over Works w carrying both at rank >= 60:
///                          engagement(w) × min(rank_a, rank_b) / 100
///
/// - Parameters:
///   - weights: `TasteProfile.workWeights`. A Work absent from it has no reading history
///     and therefore no vote; the seeder never invents an engagement value.
///   - excludeAdultTags: a property of *which branch this is*, not of the domain, so it is
///     a parameter rather than a constant -- the private branch flips it at the call site
///     instead of carrying a body diff that every merge from `main` must re-resolve.
func seedPairs(works: [Work],
               weights: [WorkID: Double],
               vocabulary: TagVocabulary,
               limit: Int = 5,
               excludeAdultTags: Bool = true) -> [SeededTagPair] {

    var accumulated: [TagPair: Double] = [:]
    var provenance: [TagPair: Set<WorkID>] = [:]

    for work in works {
        guard let engagement = weights[work.id], let tags = work.snapshot?.tags else { continue }

        let admissible: [(name: String, rank: Int)] = tags.compactMap { tag in
            guard let rank = tag.rank, rank >= minimumSeedTagRank else { return nil }
            // A deny list, not a permit list. `category(of:)` is `nil` for a tag the
            // vocabulary has never heard of, and a vocabulary up to 30 days behind is the
            // designed steady state -- so an unknown tag stays seedable. Rewriting this as
            // `guard let category = ... else { continue }` would drop every tag AniList has
            // added since the cache was written.
            if let category = vocabulary.category(of: tag.name),
               seedExcludedTagCategories.contains(category) { return nil }
            if excludeAdultTags, vocabulary.isAdult(tag.name) { return nil }
            // `isGeneralSpoiler` is deliberately not consulted: it suppresses reason
            // strings, never seeding.
            return (tag.name, rank)
        }

        for i in admissible.indices {
            for j in admissible.index(after: i)..<admissible.endIndex {
                let pair = TagPair(admissible[i].name, admissible[j].name)
                let weaker = min(admissible[i].rank, admissible[j].rank)
                accumulated[pair, default: 0] += engagement * Double(weaker) / 100
                // Recorded in the same step that adds the term, so provenance cannot
                // drift from the weight it explains.
                provenance[pair, default: []].insert(work.id)
            }
        }
    }

    // Weight desc, then lexicographic. The tiebreak is not decoration: every pair inside
    // one Work shares that Work's engagement, and the multiplier band is only [0.60, 1.00],
    // so large exact-tie blocks are the common case and the top-N cut runs straight through
    // one. Swift's sort is not guaranteed stable, so without a *total* order the cut is
    // arbitrary and slice 4's golden file would diff on re-sorts rather than on rankings.
    // Accepted cost: alphabetical order is meaningless -- when a tie block spans the cut,
    // which pairs survive carries no signal and must not be read as any.
    return accumulated
        .map { SeededTagPair(pair: $0.key, weight: $0.value,
                             contributingWorks: provenance[$0.key] ?? []) }
        .sorted {
            $0.weight != $1.weight ? $0.weight > $1.weight : $0.pair < $1.pair
        }
        .prefix(limit)
        .map { $0 }
}
