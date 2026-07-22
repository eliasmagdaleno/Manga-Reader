//
//  MoreLikeThis.swift
//  Manga-Reader
//
//  Pure, network-free core of "More Like This" reverse resolution: turn one MAL
//  recommendation (its id + title) plus the MangaDex search results for that title into
//  the confident MangaDex `Manga` — or nil. Precision-biased, fully unit-tested. The
//  networking that produces `candidates` and consumes the result lives in
//  MoreLikeThisProvider.
//

import Foundation

enum MoreLikeThis {
    /// Reverse-resolve one MAL recommendation to a MangaDex `Manga` among `candidates`
    /// (the MangaDex search results for `malTitle`). Precise first: a candidate whose
    /// `malId` equals `targetMalId` is a confirmed match. Otherwise fall back to fuzzy
    /// title matching via `matcher`. nil = no confident match (omit downstream).
    static func pickMatch(targetMalId: Int,
                          malTitle: String,
                          candidates: [Manga],
                          matcher: MALTitleMatcher = .init()) -> Manga? {
        if let exact = candidates.first(where: { $0.malId == targetMalId }) { return exact }
        let byTitle = matcher.bestMatch(
            sourceTitle: malTitle,
            candidates: candidates.map { (id: $0.id, titles: [$0.title]) })
        return byTitle.flatMap { id in candidates.first { $0.id == id } }
    }
}
