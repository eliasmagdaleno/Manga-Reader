//
//  TasteProfileStore.swift
//  Manga-Reader
//
//  Persists the user's explicit "not interested" / "more like this" feedback.
//  UserDefaults-backed, mirroring HistoryStore / LibraryStore.
//
//  It used to own the taste signal itself — a MangaDex-only tag cache. Tags now
//  live on the Work (ADR-0007), so all that remains of the cache is a **read-only**
//  copy kept alive for one release to migrate existing users. See `legacyTagCache`.
//

import SwiftUI

@MainActor
final class TasteProfileStore: ObservableObject {
    /// Manga the user explicitly dismissed; never recommended again.
    @Published private(set) var notInterested: Set<String> = []
    /// Manga the user explicitly boosted; their tags count double.
    @Published private(set) var moreLikeThis: [String] = []

    /// Pre-slice-3 tags per manga id. **Loaded once and never written.**
    ///
    /// This is a migration, not a cache: `RecommendationEngine.resolveSignals`
    /// copies it onto Works so a user upgrading across this change doesn't lose
    /// their profile. Retiring the write path is the point — the key is a bare
    /// `mangaId` with no `sourceId`, a cross-source collision that was only ever
    /// dormant because tag recording was MangaDex-gated.
    ///
    /// **Delete this, its UserDefaults key, and the seeding branch that reads it
    /// after one release** — by then every active user has been migrated, and
    /// deleting it sooner would strand anyone who skipped a version.
    private(set) var legacyTagCache: [String: [Tag]] = [:]

    private let legacyCacheKey = "taste.tagCache"
    private let notInterestedKey = "taste.notInterested"
    private let moreLikeThisKey = "taste.moreLikeThis"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func markNotInterested(mangaId: String) {
        notInterested.insert(mangaId)
        save()
    }

    func markMoreLikeThis(mangaId: String) {
        if !moreLikeThis.contains(mangaId) { moreLikeThis.append(mangaId) }
        save()
    }

    /// Deliberately does not write `legacyCacheKey`: the legacy cache is read-only,
    /// and rewriting it here would keep resurrecting data this change retires.
    private func save() {
        if let d = try? JSONEncoder().encode(notInterested) { defaults.set(d, forKey: notInterestedKey) }
        if let d = try? JSONEncoder().encode(moreLikeThis) { defaults.set(d, forKey: moreLikeThisKey) }
    }

    private func load() {
        if let d = defaults.data(forKey: legacyCacheKey),
           let v = try? JSONDecoder().decode([String: [Tag]].self, from: d) { legacyTagCache = v }
        if let d = defaults.data(forKey: notInterestedKey),
           let v = try? JSONDecoder().decode(Set<String>.self, from: d) { notInterested = v }
        if let d = defaults.data(forKey: moreLikeThisKey),
           let v = try? JSONDecoder().decode([String].self, from: d) { moreLikeThis = v }
    }
}
