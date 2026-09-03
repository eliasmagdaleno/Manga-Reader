//
//  UpgradeAttemptMemory.swift
//  MangaCarta
//
//  What the upgrade queue already learned about a Work it could not upgrade (ADR-0008).
//
//  In the queue's own file, not `works.json`, by ADR-0007's test: *can you delete this
//  file and lose nothing but time?* Attempt bookkeeping, yes — worst case is one redundant
//  resolution pass. Work identity, no. Data with different answers must not share a file.
//
//  Not in `EntityResolutionStore` either, despite its existing miss TTL: that cache is
//  keyed `sourceId:mangaId`, and a Work-level answer has no single Listing to key on.
//

import Foundation

/// Why a Work is still provisional. Two providers sit between a Work and its metadata, so
/// a timestamp alone cannot tell the failures apart — and they reopen on different
/// evidence.
enum UpgradeOutcome: Codable, Equatable {
    /// MyAnimeList returned candidates and none cleared the matcher's threshold.
    /// Fingerprinted on the title count, because a miss means "no confident match *given
    /// these titles*" — so a Listing linking or a provider adding synonyms reopens it at
    /// once, with the TTL only as a backstop.
    case unmatched(knownTitlesCount: Int)
    /// Resolution succeeded and AniList has no entry for that id. Only the TTL reopens
    /// this: re-matching produces the same id every time, so more titles cannot help.
    ///
    /// **This exists because the fetch stage would otherwise have no memory at all.** Once
    /// a Work carries `mal:123` it has stopped being a resolution case, and a memory keyed
    /// on title count is about resolution — so without this, a Work whose id AniList 404s
    /// is re-requested on every drain, forever.
    case absentFromProvider(malId: Int)
}

@MainActor
final class UpgradeAttemptMemory {
    /// Mirrors `EntityResolutionStore.missTTL` and `MetadataSnapshot.releasingTTL` — the
    /// same fourteen days, for the same reason: a negative answer is worth re-asking
    /// eventually, a positive one isn't.
    ///
    /// `.absentFromProvider` gets the TTL rather than being terminal because AniList adds
    /// entries over time and the costs are asymmetric: a TTL spends one request per Work
    /// per interval, while terminal strands a Work catalogued next month as provisional
    /// until the user manually links something that isn't actually broken.
    nonisolated static let ttl: TimeInterval = 14 * 24 * 60 * 60

    private struct Attempt: Codable {
        let checkedAt: Date
        let outcome: UpgradeOutcome
    }

    private var attempts: [WorkID: Attempt] = [:]

    private let directory: URL
    private let saveDebounce: TimeInterval
    private var loaded = false
    private var dirty = false
    private var saveTask: Task<Void, Never>?

    /// Application Support rather than `Caches/`: it passes the delete test, but
    /// "disposable" is the argument for a separate *file*, not for an evictable directory.
    /// Eviction here means a burst of redundant network on the next drain, which is the
    /// one cost the whole queue design exists to bound. The file is a few KB.
    nonisolated static func applicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private var fileURL: URL { directory.appendingPathComponent("upgrade-attempts.json") }

    init(directory: URL = UpgradeAttemptMemory.applicationSupportDirectory(),
         saveDebounce: TimeInterval = 1.0) {
        self.directory = directory
        self.saveDebounce = saveDebounce
    }

    // MARK: - Reading

    /// Whether the queue should skip this Work because it already knows the answer.
    ///
    /// Takes the whole `Work` rather than an id and a count so a caller cannot pair the
    /// wrong count with the wrong id.
    func suppresses(_ work: Work, now: Date = Date()) -> Bool {
        loadIfNeeded()
        guard let attempt = attempts[work.id] else { return false }
        guard now.timeIntervalSince(attempt.checkedAt) < Self.ttl else { return false }

        switch attempt.outcome {
        case .unmatched(let count):
            // An authoritative id ends the question this refusal was an answer to
            // (ADR-0018). Checked here rather than folded into the recorded fingerprint
            // because a stored flag would say what was true when the refusal happened,
            // and the question is what is true now. Note this also un-blocks the Work
            // for `tagBlocked` — ADR-0015's notice and the taste profile both read it,
            // and both were making the same false claim.
            if work.externalIds.mal != nil { return false }
            // Compared for *inequality*, not growth. `knownTitles` only appends, so the
            // two are equivalent today — but if that ever stops being true, re-asking is
            // the safe failure and staying silent is not.
            return work.knownTitles.count == count
        case .absentFromProvider:
            return true
        }
    }

    // MARK: - Writing

    /// Records why a Work could not be upgraded. **Transient failures record nothing** —
    /// callers simply don't call this — mirroring the discipline `MALEntityResolver`
    /// already documents: an outage must not poison the memory for the TTL.
    func record(_ outcome: UpgradeOutcome, for id: WorkID, now: Date = Date()) {
        loadIfNeeded()
        attempts[id] = Attempt(checkedAt: now, outcome: outcome)
        markDirty()
    }

    /// Drops a Work's record once it has been upgraded. A fresh snapshot already makes it
    /// ineligible, so this is about not accumulating answers to questions nobody will ask
    /// again.
    func forget(_ id: WorkID) {
        loadIfNeeded()
        guard attempts.removeValue(forKey: id) != nil else { return }
        markDirty()
    }

    // MARK: - Persistence

    /// Writes immediately if anything is pending. Call on backgrounding — a debounced save
    /// that never fires because the app was suspended is a lost write.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard dirty else { return }
        dirty = false

        let payload = attempts.map { Persisted.Entry(workId: $0.key,
                                                     checkedAt: $0.value.checkedAt,
                                                     outcome: $0.value.outcome) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(Persisted(entries: payload)).write(to: fileURL, options: .atomic)
        } catch {
            // Best-effort, matching the rest of the app's stores. Losing this file costs
            // one redundant drain, which is the property that let it live apart from
            // `works.json` in the first place.
            dirty = true
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        for entry in payload.entries {
            attempts[entry.workId] = Attempt(checkedAt: entry.checkedAt, outcome: entry.outcome)
        }
    }

    private func markDirty() {
        dirty = true
        saveTask?.cancel()
        let delay = saveDebounce
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
}

// MARK: - On-disk shape

/// Entries are an array rather than a dictionary because JSON object keys must be strings
/// and a `WorkID` isn't one — the same reason `WorkStore` persists its aliases as pairs.
/// File-scope so `Entry` stays one level deep.
private struct Persisted: Codable {
    struct Entry: Codable {
        let workId: WorkID
        let checkedAt: Date
        let outcome: UpgradeOutcome
    }
    var entries: [Entry]
}
