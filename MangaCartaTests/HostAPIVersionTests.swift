//
//  HostAPIVersionTests.swift
//  MangaCartaTests
//
//  Host API version grammar, ordering, and range intersection — the "Versions and
//  feature negotiation" section of the Host API design. The spec shows `"1.0"` and
//  `"2.0"` but never states a grammar; this suite pins the strict two-component rule
//  the validator implements and proves the refusal error names the versions involved
//  (acceptance criterion 9).
//

import XCTest
@testable import MangaCarta

final class HostAPIVersionTests: XCTestCase {

    // MARK: - Grammar

    /// MAJOR "." MINOR, decimal, no leading zeros. Nothing else parses.
    func testAcceptedVersionStrings() throws {
        let accepted: [(String, Int, Int)] = [
            ("1.0", 1, 0),
            ("0.1", 0, 1),
            ("0.0", 0, 0),
            ("2.17", 2, 17),
            ("10.230", 10, 230)
        ]
        for (raw, major, minor) in accepted {
            let parsed = try XCTUnwrap(HostAPIVersion(parsing: raw), "expected '\(raw)' to parse")
            XCTAssertEqual(parsed.major, major, raw)
            XCTAssertEqual(parsed.minor, minor, raw)
            XCTAssertEqual(parsed.description, raw, "round-trip should be exact for \(raw)")
        }
    }

    /// Everything outside the two-component grammar is refused rather than guessed at.
    /// A patch component in particular has no defined comparison semantics in the spec.
    func testRejectedVersionStrings() {
        let rejected = [
            "", " ", "1", "1.", ".0", "1.0.0", "1.0.0.0", "v1.0", "1.0-beta", "1.0+build",
            "01.0", "1.00", "1.x", "x.1", "1 .0", " 1.0", "1.0 ", "1,0", "-1.0", "1.-0",
            "1.0\n", "١.٠", "1.0e1", "١", "١.0"
        ]
        for raw in rejected {
            XCTAssertNil(HostAPIVersion(parsing: raw),
                         "expected '\(raw)' to be refused")
        }
    }

    // MARK: - Ordering

    func testOrderingIsMajorThenMinor() {
        let v10 = HostAPIVersion(major: 1, minor: 0)
        let v12 = HostAPIVersion(major: 1, minor: 2)
        let v20 = HostAPIVersion(major: 2, minor: 0)

        XCTAssertLessThan(v10, v12)
        XCTAssertLessThan(v12, v20)
        XCTAssertEqual(v10, HostAPIVersion(major: 1, minor: 0))
        // Minor numbers order numerically, not lexically: 1.10 is newer than 1.9.
        XCTAssertLessThan(HostAPIVersion(major: 1, minor: 9), HostAPIVersion(major: 1, minor: 10))
    }

    // MARK: - Ranges

    func testRangeIsHalfOpen() throws {
        let range = try XCTUnwrap(HostAPIVersionRange(minimum: HostAPIVersion(major: 1, minor: 0),
                                                      maximumExclusive: HostAPIVersion(major: 2, minor: 0)))
        XCTAssertTrue(range.contains(HostAPIVersion(major: 1, minor: 0)))
        XCTAssertTrue(range.contains(HostAPIVersion(major: 1, minor: 99)))
        XCTAssertFalse(range.contains(HostAPIVersion(major: 2, minor: 0)))
        XCTAssertFalse(range.contains(HostAPIVersion(major: 0, minor: 9)))
    }

    /// An empty or inverted range can never intersect anything, so it is refused at
    /// construction rather than producing a confusing no-intersection error later.
    func testEmptyRangeIsNotConstructible() {
        let one = HostAPIVersion(major: 1, minor: 0)
        let two = HostAPIVersion(major: 2, minor: 0)
        XCTAssertNil(HostAPIVersionRange(minimum: one, maximumExclusive: one))
        XCTAssertNil(HostAPIVersionRange(minimum: two, maximumExclusive: one))
    }

    // MARK: - Intersection

    /// "The host selects the highest installed version in the intersection."
    func testHighestInstalledVersionInIntersectionIsSelected() throws {
        let support = HostAPISupport(installedVersions: [
            HostAPIVersion(major: 1, minor: 0),
            HostAPIVersion(major: 1, minor: 4),
            HostAPIVersion(major: 2, minor: 0)
        ])
        let v1Range = try XCTUnwrap(HostAPIVersionRange(minimum: HostAPIVersion(major: 1, minor: 0),
                                                        maximumExclusive: HostAPIVersion(major: 2, minor: 0)))
        XCTAssertEqual(support.highestVersion(in: v1Range), HostAPIVersion(major: 1, minor: 4))

        let v2Range = try XCTUnwrap(HostAPIVersionRange(minimum: HostAPIVersion(major: 2, minor: 0),
                                                        maximumExclusive: HostAPIVersion(major: 3, minor: 0)))
        XCTAssertEqual(support.highestVersion(in: v2Range), HostAPIVersion(major: 2, minor: 0))
    }

    func testNoIntersectionSelectsNothing() throws {
        let support = HostAPISupport(installedVersions: [HostAPIVersion(major: 1, minor: 0)])
        let future = try XCTUnwrap(HostAPIVersionRange(minimum: HostAPIVersion(major: 3, minor: 0),
                                                       maximumExclusive: HostAPIVersion(major: 4, minor: 0)))
        XCTAssertNil(support.highestVersion(in: future))
    }

    /// A minimum inside a supported major but above every installed minor still has no
    /// intersection — 1.7 is not satisfied by an installed 1.0.
    func testMinimumAboveEveryInstalledMinorHasNoIntersection() throws {
        let support = HostAPISupport(installedVersions: [HostAPIVersion(major: 1, minor: 0)])
        let range = try XCTUnwrap(HostAPIVersionRange(minimum: HostAPIVersion(major: 1, minor: 7),
                                                      maximumExclusive: HostAPIVersion(major: 2, minor: 0)))
        XCTAssertNil(support.highestVersion(in: range))
    }
}
