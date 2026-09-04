//
//  WebKitPartitioningSpikeTests.swift
//  MangaCartaTests
//
//  The S3 spike for Host API design §16 evidence gate 2: does iOS 17.5 offer a WebKit
//  mechanism that gives BOTH persistent Cloudflare clearance AND strong per-Source
//  isolation? `WebViewService` currently answers "no" by construction — it uses one
//  shared `.default()` store precisely so `cf_clearance` survives relaunch.
//
//  It does. `WKWebsiteDataStore(forIdentifier:)` gives both, so the design's fallback is
//  not taken — the decision, the evidence and the two host rules that come with it are
//  ADR-0003 Amendment 3.
//
//  These tests are the experiment. They probe `WKWebsiteDataStore` directly rather than
//  through any app type, because the question is about the framework, not about our code.
//  The cross-process half of the proof lives in `WebKitRelaunchSpikeTests`, which an
//  ordinary test run skips; `scripts/webkit-partitioning-spike.sh` drives it.
//

import XCTest
import WebKit
import CryptoKit
@testable import MangaCarta

/// The three candidate ways to give a Source its own website data.
enum SpikePartitioning {
    /// What `WebViewService` does today: every Source shares one persistent store.
    case sharedDefault
    /// `WKWebsiteDataStore(forIdentifier:)` — persistent, keyed by UUID. iOS 17.0+.
    case identified
    /// The fallback the design names if `identified` had not existed: isolated but
    /// erased at process exit.
    case nonPersistent
}

/// Maps a qualified Source id onto a data store under the given mechanism.
///
/// The identifier is a name-based (version 5) UUID over a fixed namespace, so the same
/// Source resolves to the same store on every launch with no mapping to persist and no
/// migration to write. Version 5 also forces a nonzero version nibble, which sidesteps
/// `dataStoreForIdentifier:`'s documented "throws exception if identifier is 0".
@MainActor
func spikeDataStore(_ mechanism: SpikePartitioning, for sourceId: String) -> WKWebsiteDataStore {
    switch mechanism {
    case .sharedDefault: return .default()
    case .nonPersistent: return .nonPersistent()
    case .identified: return WKWebsiteDataStore(forIdentifier: spikeStoreIdentifier(for: sourceId))
    }
}

/// A fixed namespace for the spike. Production would mint its own and never change it —
/// changing the namespace orphans every reader's clearance.
private let spikeNamespace = UUID(uuidString: "6E8B0F2A-3C4D-4A5E-9B10-2F7C5D8E1A03")!

func spikeStoreIdentifier(for sourceId: String) -> UUID {
    var hasher = Insecure.SHA1()
    withUnsafeBytes(of: spikeNamespace.uuid) { hasher.update(bufferPointer: $0) }
    hasher.update(data: Data(sourceId.utf8))
    var bytes = Array(hasher.finalize().prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50   // version 5
    bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
    return bytes.withUnsafeBufferPointer { NSUUID(uuidBytes: $0.baseAddress) as UUID }
}

// MARK: - Cookie helpers

/// One origin, deliberately: the whole question is whether two Sources reading the SAME
/// site can see each other. Different origins would prove nothing.
let spikeOrigin = "clearance.mangacarta.test"

/// A `cf_clearance`-shaped cookie. The expiry is not cosmetic: a session cookie is never
/// written to disk, so a persistence test built on one would fail for the wrong reason.
func spikeClearanceCookie(value: String, domain: String = spikeOrigin) -> HTTPCookie {
    HTTPCookie(properties: [
        .name: "cf_clearance",
        .value: value,
        .domain: domain,
        .path: "/",
        .secure: "TRUE",
        .expires: Date().addingTimeInterval(3600),
    ])!
}

@MainActor
func spikeSetCookie(_ cookie: HTTPCookie, in store: WKWebsiteDataStore) async {
    await withCheckedContinuation { continuation in
        store.httpCookieStore.setCookie(cookie) { continuation.resume() }
    }
}

@MainActor
func spikeAllCookies(in store: WKWebsiteDataStore) async -> [HTTPCookie] {
    await withCheckedContinuation { continuation in
        store.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
    }
}

@MainActor
func spikeClearance(in store: WKWebsiteDataStore) async -> String? {
    await spikeAllCookies(in: store)
        .first { $0.name == "cf_clearance" && $0.domain.contains(spikeOrigin) }?
        .value
}

/// Forces a freshly opened persistent store to finish loading its on-disk state before
/// anything reads `httpCookieStore`. Without this the first read races the load and comes
/// back empty — silently, which is the trap: a host that believed it would re-present a
/// Cloudflare challenge the reader had already solved.
@MainActor
func spikeWarmUp(_ store: WKWebsiteDataStore) async {
    _ = await withCheckedContinuation { continuation in
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) {
            continuation.resume(returning: $0)
        }
    }
}

@MainActor
func spikeRemoveDataStore(_ identifier: UUID) async {
    await withCheckedContinuation { continuation in
        WKWebsiteDataStore.remove(forIdentifier: identifier) { _ in continuation.resume() }
    }
}

/// True once `identifier` appears in the on-disk listing, waiting up to `timeout` for it.
///
/// Not a sleep dressed up: the listing is **eventually consistent with a store's first
/// use** (see `testIdentifiedStoreIsRegisteredOnDiskOnceItIsUsed`), so the honest
/// assertion is "this becomes true", and a store that never registers still fails.
@MainActor
func spikeAwaitRegistration(of identifier: UUID, timeout: Duration = .seconds(3)) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    repeat {
        if await spikeDataStoreIdentifiers().contains(identifier) { return true }
        try? await Task.sleep(for: .milliseconds(100))
    } while ContinuousClock.now < deadline
    return false
}

@MainActor
func spikeDataStoreIdentifiers() async -> [UUID] {
    await withCheckedContinuation { continuation in
        WKWebsiteDataStore.fetchAllDataStoreIdentifiers { continuation.resume(returning: $0) }
    }
}

// MARK: - Tests

@MainActor
final class WebKitPartitioningSpikeTests: XCTestCase {

    /// Two Sources that would collide if the mechanism does not isolate them.
    private let sourceA = "spike.repo/source-a"
    private let sourceB = "spike.repo/source-b"

    /// Keeps stores alive for the duration of a test. Releasing a `WKWebsiteDataStore`
    /// discards whatever its session held that was not yet durable — see the amendment.
    private var retained: [WKWebsiteDataStore] = []

    override func tearDown() async throws {
        retained.removeAll()
        for id in [sourceA, sourceB] {
            await spikeRemoveDataStore(spikeStoreIdentifier(for: id))
        }
        // The shared-store test writes into the one store the app itself uses. Take it
        // back out — leaving a `cf_clearance` for a fake origin in the real default store
        // is exactly the cross-contamination this spike is about.
        let shared = WKWebsiteDataStore.default()
        for cookie in await spikeAllCookies(in: shared) where cookie.domain.contains(spikeOrigin) {
            await withCheckedContinuation { continuation in
                shared.httpCookieStore.delete(cookie) { continuation.resume() }
            }
        }
    }

    /// The status quo, stated as a test so the reason for changing it is not folklore.
    /// Two `WKWebView`s configured the way `WebViewService` configures its one browser
    /// see each other's clearance completely.
    func testSharedDefaultStoreLeaksClearanceBetweenSources() async {
        let storeA = spikeDataStore(.sharedDefault, for: sourceA)
        let storeB = spikeDataStore(.sharedDefault, for: sourceB)

        await spikeSetCookie(spikeClearanceCookie(value: "earned-by-a"), in: storeA)

        let leaked = await spikeClearance(in: storeB)
        XCTAssertEqual(leaked, "earned-by-a",
                       "the shared default store is expected to leak; if it no longer does, "
                       + "the whole premise of this spike has changed")
    }

    /// Criterion 6, cookie half. Source A earns clearance; Source B must not be able to
    /// see it — not in the cookie jar, and not in the data records either.
    func testIdentifiedStoresIsolateClearance() async {
        let storeA = spikeDataStore(.identified, for: sourceA)
        let storeB = spikeDataStore(.identified, for: sourceB)
        retained = [storeA, storeB]

        await spikeSetCookie(spikeClearanceCookie(value: "earned-by-a"), in: storeA)

        let mine = await spikeClearance(in: storeA)
        XCTAssertEqual(mine, "earned-by-a", "Source A cannot read back its own clearance")

        let theirs = await spikeClearance(in: storeB)
        XCTAssertNil(theirs, "Source B read Source A's clearance cookie")

        // Adversarial second look: not just the cookie API, but whether B's store admits
        // to holding any data for the origin at all.
        let records = await withCheckedContinuation { continuation in
            storeB.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) {
                continuation.resume(returning: $0)
            }
        }
        XCTAssertFalse(records.contains { $0.displayName.contains("mangacarta.test") },
                       "Source B holds a website data record for Source A's origin")
    }

    /// Distinct Sources must get distinct identifiers, and the same Source must get the
    /// same one every time — otherwise isolation above is an accident of a random UUID
    /// and persistence below can never work.
    func testStoreIdentifierIsStablePerSourceAndDistinctBetweenSources() {
        XCTAssertEqual(spikeStoreIdentifier(for: sourceA), spikeStoreIdentifier(for: sourceA))
        XCTAssertNotEqual(spikeStoreIdentifier(for: sourceA), spikeStoreIdentifier(for: sourceB))
    }

    /// Where the durability proof does NOT come from. `WKWebsiteDataStore(forIdentifier:)`
    /// hands back the *same object* for an identifier already live in this process
    /// (measured: `second === first`), so a same-process "close and reopen" reads the
    /// live session, not the disk, and would pass even for a store that persists nothing.
    /// What a single process can honestly assert is that the store reaches disk at all;
    /// `WebKitRelaunchSpikeTests` supplies the rest.
    ///
    /// **Constructing the store is not enough to put it on disk.** The object is created
    /// eagerly and its directory lazily, on first use — so `fetchAllDataStoreIdentifiers`
    /// does not list a store that has only been constructed. On an idle machine the
    /// directory usually lands before the next call and the distinction is invisible;
    /// inside the full bundle it does not, and an earlier version of this test failed
    /// there while passing alone. Instrumented, it read `false, n=2` and then `true, n=3`
    /// 250 ms later. Awaiting one operation on the store — the same warm-up the amendment
    /// requires before reading a cookie jar — closed it in three consecutive full-bundle
    /// runs, because that round-trip is what materialises the session.
    func testIdentifiedStoreIsRegisteredOnDiskOnceItIsUsed() async {
        let identifier = spikeStoreIdentifier(for: sourceA)
        let store = spikeDataStore(.identified, for: sourceA)
        retained = [store]
        XCTAssertTrue(store.isPersistent)
        XCTAssertEqual(store.identifier, identifier)

        await spikeWarmUp(store)

        let registered = await spikeAwaitRegistration(of: identifier)
        XCTAssertTrue(registered, "the store never reached disk under its identifier")

        XCTAssertTrue(WKWebsiteDataStore(forIdentifier: identifier) === store,
                      "WebKit stopped vending the identical live object; a same-process "
                      + "reopen may now be a real durability check, so revisit this test")
    }

    /// The fallback's cost, at the API level: every `nonPersistent()` call is a different
    /// store, so nothing written into one is visible from the next — within a launch or
    /// across one.
    func testNonPersistentStoresShareNothingWithEachOther() async {
        await spikeSetCookie(spikeClearanceCookie(value: "ephemeral"),
                             in: spikeDataStore(.nonPersistent, for: sourceA))

        let recovered = await spikeClearance(in: spikeDataStore(.nonPersistent, for: sourceA))
        XCTAssertNil(recovered, "a nonpersistent store handed back another one's cookie")
    }

    /// A nonpersistent store has no identifier, so it cannot even be addressed across a
    /// launch. This is the fallback's cost restated at the API level.
    func testNonPersistentStoreHasNoIdentifier() {
        XCTAssertNil(WKWebsiteDataStore.nonPersistent().identifier)
        XCTAssertNil(WKWebsiteDataStore.default().identifier)
        XCTAssertNotNil(spikeDataStore(.identified, for: sourceA).identifier)
    }
}

/// The half of evidence gate 2 that a single process cannot answer: does clearance
/// written under one launch come back under the next, and is it still the launching
/// Source's alone?
///
/// `WKWebsiteDataStore(forIdentifier:)` hands back the *same object* for an identifier
/// already live in this process, so a same-process "reopen" proves nothing about disk.
/// Only two launches do. Each phase is therefore skipped unless
/// `scripts/webkit-partitioning-spike.sh` selects it with `WEBKIT_SPIKE_PHASE`, so an
/// ordinary `xcodebuild test` — and CI — runs none of them.
@MainActor
final class WebKitRelaunchSpikeTests: XCTestCase {

    /// Fixed on purpose: both launches must address the same store.
    static let relaunchSourceId = "spike.repo/relaunch"
    static let relaunchToken = "clearance-token-that-must-survive"

    /// Holds the launch's store and browser open, which is what a live Source does. An
    /// identified store that no `WKWebView` ever attached to never becomes durable —
    /// that is the finding, not an accident of the harness.
    private static var retainedStore: WKWebsiteDataStore?
    private static var retainedWebView: WKWebView?

    private var phase: String? { ProcessInfo.processInfo.environment["WEBKIT_SPIKE_PHASE"] }

    /// Builds the store the way a Source would hold it: a store, and a browser bound to it.
    private func openSourceBrowser(for sourceId: String) -> WKWebsiteDataStore {
        let store = WKWebsiteDataStore(forIdentifier: spikeStoreIdentifier(for: sourceId))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        Self.retainedStore = store
        Self.retainedWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844),
                                         configuration: configuration)
        return store
    }

    func testSeedClearanceForRelaunch() async throws {
        try XCTSkipUnless(phase == "seed", "driven by scripts/webkit-partitioning-spike.sh")
        let store = openSourceBrowser(for: Self.relaunchSourceId)
        await spikeSetCookie(spikeClearanceCookie(value: Self.relaunchToken), in: store)

        let readBack = await spikeClearance(in: store)
        XCTAssertEqual(readBack, Self.relaunchToken, "the seeding launch could not read its own cookie")
        print("SPIKE seeded \(spikeStoreIdentifier(for: Self.relaunchSourceId))")
    }

    /// Criterion 6's cookie half and the persistence half of gate 2, in one launch:
    /// the clearance is back, and it is still only in the Source that earned it.
    /// Criterion 6's cookie half and the persistence half of gate 2, in one launch: the
    /// clearance is back, and it is still only in the Source that earned it.
    ///
    /// `warmUp()` before the first read is not ceremony. A freshly opened identified store
    /// loads its cookies from disk asynchronously, and `getAllCookies` issued before that
    /// finishes returns an EMPTY jar with no error — measured, and the reason an earlier
    /// draft of this test reported "clearance did not survive" against a store that had it.
    func testClearanceSurvivesProcessRelaunchAndStaysIsolated() async throws {
        try XCTSkipUnless(phase == "verify", "driven by scripts/webkit-partitioning-spike.sh")
        let identifier = spikeStoreIdentifier(for: Self.relaunchSourceId)
        // No wait needed here, unlike the in-process test above: this store's directory was
        // written by the seeding launch, so it is pre-existing disk state, not a store being
        // materialised right now. Step 1 of the script depends on this failing immediately.
        let registered = await spikeDataStoreIdentifiers()
        XCTAssertTrue(registered.contains(identifier), "the store is not on disk at all")

        let store = openSourceBrowser(for: Self.relaunchSourceId)
        await spikeWarmUp(store)
        let recovered = await spikeClearance(in: store)
        print("SPIKE recovered=\(String(describing: recovered))")
        XCTAssertEqual(recovered, Self.relaunchToken, "clearance did not survive the process relaunch")

        // A second Source, same origin, next launch: still nothing. Warmed up too, so a
        // pass here cannot be the race above wearing isolation's clothes.
        let neighbourId = spikeStoreIdentifier(for: "spike.repo/relaunch-neighbour")
        let neighbour = WKWebsiteDataStore(forIdentifier: neighbourId)
        await spikeWarmUp(neighbour)
        let neighbourClearance = await spikeClearance(in: neighbour)
        XCTAssertNil(neighbourClearance, "a second Source read the first Source's recovered clearance")
        await spikeRemoveDataStore(neighbourId)
    }

    /// Leaves the simulator as it was found. Nothing else in this app creates an
    /// *identified* store — the app's own browser uses `.default()`, which has no
    /// identifier and is never touched here — so every identified store on the device is
    /// spike residue, and a run that leaves some behind makes the next run's step 1 pass
    /// when it should fail.
    func testRemoveEverySpikeDataStore() async throws {
        try XCTSkipUnless(phase == "cleanup", "driven by scripts/webkit-partitioning-spike.sh")
        Self.retainedWebView = nil
        Self.retainedStore = nil
        for identifier in await spikeDataStoreIdentifiers() {
            await spikeRemoveDataStore(identifier)
        }
        let remaining = await spikeDataStoreIdentifiers()
        XCTAssertTrue(remaining.isEmpty, "\(remaining.count) data store(s) survived cleanup")
        print("SPIKE cleaned up")
    }
}
