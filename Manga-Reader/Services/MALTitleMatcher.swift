//
//  MALTitleMatcher.swift
//  Manga-Reader
//
//  Pure title-matching core for cross-source entity resolution: given a source manga's
//  title and MAL search candidates (each with its full title set), decide which MAL id
//  it is — or that there's no confident match. No network, no persistence; fully unit-
//  tested. Precision-biased: a high threshold plus an ambiguity guard, and any doubt
//  resolves to `.noMatch` rather than a wrong id.
//

import Foundation

/// A MAL search result reduced to what matching needs: its id and every title it goes by.
struct MALCandidate: Equatable {
    let malId: Int
    let titles: [String]
}

enum MALMatchDecision: Equatable {
    case matched(malId: Int)
    case noMatch
}

struct MALTitleMatcher {
    /// Minimum normalized similarity (0...1) required to accept a fuzzy match.
    var acceptanceThreshold: Double = 0.90
    /// The best candidate must beat the runner-up by at least this margin, else the
    /// match is treated as ambiguous and rejected.
    var ambiguityMargin: Double = 0.05

    /// Tokens dropped during normalization — structural noise, not identity.
    private static let noiseTokens: Set<String> = ["manga", "season", "part", "cour"]

    /// Lowercase, strip diacritics, replace every non-alphanumeric with a space, drop
    /// noise tokens, and collapse/trim whitespace.
    static func normalize(_ title: String) -> String {
        let folded = title.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX")).lowercased()
        let spacedScalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(spacedScalars)
            .split(separator: " ")
            .map(String.init)
            .filter { !noiseTokens.contains($0) }
            .joined(separator: " ")
    }

    /// Normalized Levenshtein similarity in [0, 1]; 1.0 iff the strings are equal.
    /// Callers pass already-normalized strings.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }
        let distance = levenshtein(Array(a), Array(b))
        let maxLen = max(a.count, b.count)
        return 1.0 - Double(distance) / Double(maxLen)
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1,        // deletion
                                 current[j - 1] + 1,     // insertion
                                 previous[j - 1] + cost) // substitution
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// Best MAL match for `sourceTitle` among `candidates`, or `.noMatch`.
    func decide(sourceTitle: String, candidates: [MALCandidate]) -> MALMatchDecision {
        let normSource = Self.normalize(sourceTitle)
        guard !normSource.isEmpty, !candidates.isEmpty else { return .noMatch }

        let scored = candidates
            .map { candidate -> (malId: Int, score: Double) in
                let best = candidate.titles
                    .map { Self.similarity(normSource, Self.normalize($0)) }
                    .max() ?? 0
                return (candidate.malId, best)
            }
            .sorted { $0.score > $1.score }

        guard let best = scored.first, best.score >= acceptanceThreshold else { return .noMatch }
        // Ambiguity guard rejects even exact matches (1.0) if the runner-up is too close.
        if scored.count >= 2, best.score - scored[1].score < ambiguityMargin {
            return .noMatch   // too close to call — precision over recall
        }
        return .matched(malId: best.malId)
    }
}
