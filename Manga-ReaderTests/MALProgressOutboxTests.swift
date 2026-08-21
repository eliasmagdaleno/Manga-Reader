//
//  MALProgressOutboxTests.swift
//  Manga-ReaderTests
//
//  Durable, account-bound coalescing of pending MyAnimeList progress.
//

import XCTest
@testable import Manga_Reader

final class MALProgressOutboxTests: XCTestCase {
    private func makeDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MALProgressOutboxTests-\(UUID().uuidString)")
    }

    func testEnqueueCoalescesToTheHighestProgressWithinOneAccountAndTitle() throws {
        let outbox = MALProgressOutbox(directory: makeDirectory())
        let first = Date(timeIntervalSince1970: 100)
        let latest = Date(timeIntervalSince1970: 300)

        try outbox.enqueue(userID: 7, mangaID: 42, desiredProgress: 12, completedAt: first)
        try outbox.enqueue(userID: 7, mangaID: 42, desiredProgress: 10,
                           completedAt: Date(timeIntervalSince1970: 200))
        try outbox.enqueue(userID: 7, mangaID: 42, desiredProgress: 15, completedAt: latest)

        let item = try XCTUnwrap(outbox.nextEligible(userID: 7, at: latest))
        XCTAssertEqual(item.userID, 7)
        XCTAssertEqual(item.mangaID, 42)
        XCTAssertEqual(item.desiredProgress, 15)
        XCTAssertEqual(item.firstCompletedAt, first)
        XCTAssertEqual(item.latestCompletedAt, latest)
        XCTAssertNil(outbox.nextEligible(userID: 8, at: latest))
    }

    func testDeliveredProgressRemovesOnlyTheValueThatWasActuallySent() throws {
        let outbox = MALProgressOutbox(directory: makeDirectory())
        let now = Date(timeIntervalSince1970: 100)
        try outbox.enqueue(userID: 7, mangaID: 42, desiredProgress: 12, completedAt: now)
        let attempted = try XCTUnwrap(outbox.nextEligible(userID: 7, at: now))
        try outbox.enqueue(userID: 7, mangaID: 42, desiredProgress: 15,
                           completedAt: now.addingTimeInterval(1))

        try outbox.markDelivered(attempted)

        XCTAssertEqual(outbox.nextEligible(userID: 7, at: now.addingTimeInterval(1))?.desiredProgress,
                       15)
        try outbox.markDelivered(try XCTUnwrap(
            outbox.nextEligible(userID: 7, at: now.addingTimeInterval(1))))
        XCTAssertNil(outbox.nextEligible(userID: 7, at: now.addingTimeInterval(1)))
    }
}
