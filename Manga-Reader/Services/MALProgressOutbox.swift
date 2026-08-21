//
//  MALProgressOutbox.swift
//  Manga-Reader
//
//  Durable, account-bound pending MyAnimeList progress.
//

import Foundation

enum MALProgressFailure: String, Codable, Equatable {
    case transient
    case unknown
    case permanent
}

struct MALProgressOutboxItem: Codable, Equatable {
    let userID: Int
    let mangaID: Int
    var desiredProgress: Int
    var firstCompletedAt: Date
    var latestCompletedAt: Date
    var retryCount: Int
    var nextAttemptAt: Date
    var failure: MALProgressFailure?
}

final class MALProgressOutbox {
    private struct Key: Hashable {
        let userID: Int
        let mangaID: Int
    }

    private struct Envelope: Codable {
        let version: Int
        var ready: [MALProgressOutboxItem]
    }

    private static let version = 1
    private let directory: URL
    private var ready: [Key: MALProgressOutboxItem] = [:]

    private var fileURL: URL { directory.appendingPathComponent("mal-progress-outbox.json") }

    init(directory: URL = WorkStore.applicationSupportDirectory()) {
        self.directory = directory
        load()
    }

    func enqueue(userID: Int, mangaID: Int, desiredProgress: Int,
                 completedAt: Date) throws {
        let key = Key(userID: userID, mangaID: mangaID)
        if var item = ready[key] {
            let increased = desiredProgress > item.desiredProgress
            item.desiredProgress = max(item.desiredProgress, desiredProgress)
            item.firstCompletedAt = min(item.firstCompletedAt, completedAt)
            item.latestCompletedAt = max(item.latestCompletedAt, completedAt)
            if increased {
                item.retryCount = 0
                item.nextAttemptAt = completedAt
                item.failure = nil
            }
            ready[key] = item
        } else {
            ready[key] = MALProgressOutboxItem(
                userID: userID,
                mangaID: mangaID,
                desiredProgress: desiredProgress,
                firstCompletedAt: completedAt,
                latestCompletedAt: completedAt,
                retryCount: 0,
                nextAttemptAt: completedAt,
                failure: nil
            )
        }
        try save()
    }

    func nextEligible(userID: Int, at date: Date) -> MALProgressOutboxItem? {
        ready.values
            .filter { $0.userID == userID && $0.failure != .permanent && $0.nextAttemptAt <= date }
            .sorted {
                ($0.firstCompletedAt, $0.mangaID) < ($1.firstCompletedAt, $1.mangaID)
            }
            .first
    }

    func markDelivered(_ delivered: MALProgressOutboxItem) throws {
        let key = Key(userID: delivered.userID, mangaID: delivered.mangaID)
        guard let current = ready[key],
              current.desiredProgress <= delivered.desiredProgress else { return }
        ready.removeValue(forKey: key)
        try save()
    }

    func flush() throws {
        try save()
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let envelope = Envelope(version: Self.version, ready: Array(ready.values))
        try JSONEncoder().encode(envelope).write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == Self.version else { return }
        ready = Dictionary(uniqueKeysWithValues: envelope.ready.map {
            (Key(userID: $0.userID, mangaID: $0.mangaID), $0)
        })
    }
}
