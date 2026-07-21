//
//  TasteProfileStore.swift
//  Manga-Reader
//
//  Persists the raw signal the recommendation engine learns from: the tags of
//  manga the user has read (captured when a MangaDex detail loads, or back-filled),
//  plus explicit "not interested" / "more like this" feedback. UserDefaults-backed,
//  mirroring HistoryStore / LibraryStore.
//

import SwiftUI

@MainActor
final class TasteProfileStore: ObservableObject {
    /// MangaDex tags per read manga id — the taste signal.
    @Published private(set) var tagCache: [String: [Tag]] = [:]
    /// Manga the user explicitly dismissed; never recommended again.
    @Published private(set) var notInterested: Set<String> = []
    /// Manga the user explicitly boosted; their tags count double.
    @Published private(set) var moreLikeThis: [String] = []

    private let cacheKey = "taste.tagCache"
    private let notInterestedKey = "taste.notInterested"
    private let moreLikeThisKey = "taste.moreLikeThis"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Cache a read manga's tags. No-op for an empty tag list so a failed/partial
    /// fetch never overwrites good data with nothing.
    func recordTags(mangaId: String, tags: [Tag]) {
        guard !tags.isEmpty else { return }
        tagCache[mangaId] = tags
        save()
    }

    func markNotInterested(mangaId: String) {
        notInterested.insert(mangaId)
        save()
    }

    func markMoreLikeThis(mangaId: String) {
        if !moreLikeThis.contains(mangaId) { moreLikeThis.append(mangaId) }
        save()
    }

    /// Read manga ids with no cached tags — the backfill queue. Deduped, order preserved.
    func mangaIdsMissingTags(readIds: [String]) -> [String] {
        var seen = Set<String>()
        return readIds.filter { seen.insert($0).inserted && tagCache[$0] == nil }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(tagCache) { defaults.set(d, forKey: cacheKey) }
        if let d = try? JSONEncoder().encode(notInterested) { defaults.set(d, forKey: notInterestedKey) }
        if let d = try? JSONEncoder().encode(moreLikeThis) { defaults.set(d, forKey: moreLikeThisKey) }
    }

    private func load() {
        if let d = defaults.data(forKey: cacheKey),
           let v = try? JSONDecoder().decode([String: [Tag]].self, from: d) { tagCache = v }
        if let d = defaults.data(forKey: notInterestedKey),
           let v = try? JSONDecoder().decode(Set<String>.self, from: d) { notInterested = v }
        if let d = defaults.data(forKey: moreLikeThisKey),
           let v = try? JSONDecoder().decode([String].self, from: d) { moreLikeThis = v }
    }
}
