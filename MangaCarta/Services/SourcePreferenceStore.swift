//
//  SourcePreferenceStore.swift
//  MangaCarta
//
//  Which source a reader wants, at two scopes that compose.
//
//  **Primary source** — "when several sources have a manga, prefer this one." It
//  settles ties in `FulfillmentRouter`; it never overrides completeness, because
//  preferring a source's scans is not a claim it has chapters it lacks.
//
//  **Per-Work choice** — "for *this* manga, read it here." Deliberately switching
//  source on a title is a statement about that title, and it outranks both the
//  ranking and the primary source. Without it the app would silently switch the
//  reader back the next time counts moved, which reads as a bug rather than a
//  preference.
//
//  UserDefaults rather than a file: this is small, flat, and read on the detail
//  page's first paint, so it wants to already be in memory. `EntityResolutionStore`
//  makes the same call for the same reason.
//

import Foundation

@MainActor
final class SourcePreferenceStore: ObservableObject {

    private let defaults: UserDefaults
    private static let primaryKey = "source.primaryID"
    private static let choicesKey = "source.workChoices"

    /// Work id → the Listing the reader pinned for it.
    @Published private var choices: [String: ListingKey] = [:]

    /// The reader's preferred source, or `nil` when they have not chosen one.
    ///
    /// `nil` is the honest answer rather than a guessed default: the router already
    /// falls back to MangaDex, and naming that default here too would put one
    /// decision in two places to drift apart.
    @Published var primarySourceId: String? {
        didSet { defaults.set(primarySourceId, forKey: Self.primaryKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        primarySourceId = defaults.string(forKey: Self.primaryKey)
        if let data = defaults.data(forKey: Self.choicesKey),
           let decoded = try? JSONDecoder().decode([String: ListingKey].self, from: data) {
            choices = decoded
        }
    }

    // MARK: - Per-Work choice

    /// The Listing this Work is pinned to, or `nil` when the ranking still decides.
    func choice(for workID: WorkID) -> ListingKey? {
        choices[workID.raw.uuidString]
    }

    func choose(_ listing: ListingKey, for workID: WorkID) {
        choices[workID.raw.uuidString] = listing
        saveChoices()
    }

    /// Returns the Work to the ranking. Note this **clears** rather than pinning the
    /// ranking's current answer: a reader switching back is saying "stop overriding",
    /// and those two readings diverge the moment a better Listing appears.
    func clearChoice(for workID: WorkID) {
        choices.removeValue(forKey: workID.raw.uuidString)
        saveChoices()
    }

    private func saveChoices() {
        guard let data = try? JSONEncoder().encode(choices) else { return }
        defaults.set(data, forKey: Self.choicesKey)
    }
}
