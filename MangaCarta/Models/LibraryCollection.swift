//
//  LibraryCollection.swift
//  MangaCarta
//
//  Represents a system default or user-created custom collection for organizing saved manga.
//

import Foundation

/// A category/collection within the reader's library.
struct LibraryCollection: Codable, Identifiable, Hashable, Equatable {
    let id: String
    var name: String
    let isSystem: Bool
    var isEnabled: Bool
    var sortOrder: Int

    static let readingID = "reading"
    static let onHoldID = "on_hold"
    static let plannedID = "planned"
    static let droppedID = "dropped"

    static let systemReading = LibraryCollection(id: readingID, name: "Reading", isSystem: true, isEnabled: true, sortOrder: 0)
    static let systemOnHold = LibraryCollection(id: onHoldID, name: "On Hold", isSystem: true, isEnabled: true, sortOrder: 1)
    static let systemPlanned = LibraryCollection(id: plannedID, name: "Planned", isSystem: true, isEnabled: true, sortOrder: 2)
    static let systemDropped = LibraryCollection(id: droppedID, name: "Dropped", isSystem: true, isEnabled: true, sortOrder: 3)

    static var defaultCollections: [LibraryCollection] {
        [.systemReading, .systemOnHold, .systemPlanned, .systemDropped]
    }
}
