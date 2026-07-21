# Cross-Source Entity Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Given a `Manga` from any source, resolve it to a canonical MyAnimeList (MAL) id — free for MangaDex (via `links.mal`), fuzzy-matched by title for scraped sources — caching the outcome.

**Architecture:** Add `Manga.malId` (MangaDex fills it from `attributes.links.mal`; other sources leave it nil) as a zero-network fast path. When nil, a `MALEntityResolver` searches MAL by title and runs a pure `MALTitleMatcher` (normalized-Levenshtein, exact-match-wins, high threshold + ambiguity guard) over candidates built from each result's full title set (main + `alternative_titles`). Outcomes persist in an `EntityResolutionStore` (hits forever; misses re-attempted after a 14-day TTL). No production UI — verification via the existing throwaway MAL debug screen.

**Tech Stack:** Swift, SwiftUI, Foundation, XCTest. No third-party dependencies. Xcode project (synchronized `Models/`+`Services/` groups; `Views/` is NOT synchronized).

## Global Constraints

- **Deployment target iOS 17.5.** No API newer than that without an `#available` guard.
- **No third-party dependencies.** Pure Swift + Foundation only.
- **Bridge-friendly `Manga`:** only `Int`/`String`/value/Codable fields. `malId` is `Int?` — conforms.
- **Precision over recall:** never guess. Any doubt → no match → resolver returns `nil`.
- **Persistence pattern:** stores are `@MainActor final class ... : ObservableObject`, UserDefaults + Codable, `init(defaults: UserDefaults = .standard)`, mirroring `Services/TasteProfileStore.swift`.
- **New files:** `Services/` is a synchronized group — new files there compile automatically, NO `project.pbxproj` edits. `Views/` is NOT synchronized, but `MyAnimeListDebugView.swift` already exists in it (Task 6 only edits it).
- **Test command (always):** `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:Manga-ReaderTests/Manga_ReaderTests/<method>` — iPhone 17 sim (no iPhone 16 on this machine), parallel testing OFF.
- Unit tests live in `Manga-ReaderTests/Manga_ReaderTests.swift` (`@testable import Manga_Reader`, XCTest). Live/UI verification lives in `Manga-ReaderUITests/Manga_ReaderUITests.swift`.

---

### Task 1: `MyAnimeListManga.alternativeTitles` + `allTitles`

Widen the existing MAL search DTO to carry alternative titles (already requested via
`fields=alternative_titles` but currently discarded), and expose the flattened title set
that entity resolution matches against.

**Files:**
- Modify: `Manga-Reader/Models/MyAnimeListAPI.swift:33-42` (the `MyAnimeListManga` struct)
- Test: `Manga-ReaderTests/Manga_ReaderTests.swift` (add near the existing MAL DTO tests, ~line 1629)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `MyAnimeListManga.AlternativeTitles` — `Decodable`, fields `synonyms: [String]?`, `en: String?`, `ja: String?`.
  - `MyAnimeListManga.alternativeTitles: AlternativeTitles?` (decoded from `alternative_titles`).
  - `var MyAnimeListManga.allTitles: [String]` — `title` + `en` + `ja` + `synonyms`, dropping empty/blank, de-duplicated, order: main, en, ja, synonyms.

- [ ] **Step 1: Write the failing test**

```swift
func testMyAnimeListMangaDecodesAlternativeTitlesAndAllTitles() throws {
    let json = """
    {
      "id": 25,
      "title": "Shingeki no Kyojin",
      "alternative_titles": {
        "synonyms": ["AoT"],
        "en": "Attack on Titan",
        "ja": "進撃の巨人"
      }
    }
    """.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let manga = try decoder.decode(MyAnimeListManga.self, from: json)

    XCTAssertEqual(manga.alternativeTitles?.en, "Attack on Titan")
    XCTAssertEqual(manga.alternativeTitles?.ja, "進撃の巨人")
    XCTAssertEqual(manga.alternativeTitles?.synonyms, ["AoT"])
    // allTitles: main first, then en, ja, synonyms — no empties, deduped.
    XCTAssertEqual(manga.allTitles,
                   ["Shingeki no Kyojin", "Attack on Titan", "進撃の巨人", "AoT"])
}

func testMyAnimeListMangaAllTitlesWithoutAlternatives() throws {
    let json = #"{ "id": 1, "title": "Solo Leveling" }"#.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let manga = try decoder.decode(MyAnimeListManga.self, from: json)
    XCTAssertNil(manga.alternativeTitles)
    XCTAssertEqual(manga.allTitles, ["Solo Leveling"])
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMyAnimeListMangaDecodesAlternativeTitlesAndAllTitles`
Expected: FAIL — `value of type 'MyAnimeListManga' has no member 'alternativeTitles'` (compile error).

- [ ] **Step 3: Add the fields and `allTitles` to `MyAnimeListManga`**

In `Manga-Reader/Models/MyAnimeListAPI.swift`, replace the `MyAnimeListManga` struct (lines 33-42) with:

```swift
struct MyAnimeListManga: Decodable {
    let id: Int
    let title: String
    let mainPicture: MainPicture?
    let alternativeTitles: AlternativeTitles?

    struct MainPicture: Decodable {
        let medium: String?
        let large: String?
    }

    struct AlternativeTitles: Decodable {
        let synonyms: [String]?
        let en: String?
        let ja: String?
    }

    /// Every title this manga goes by, for entity-resolution matching: main title
    /// first, then the English and Japanese alternates, then synonyms. Blank entries
    /// dropped, order-preserving de-dup — so a scraped source that uses the English
    /// title still matches even when MAL's main title is the romaji one.
    var allTitles: [String] {
        var seen = Set<String>()
        return ([title, alternativeTitles?.en, alternativeTitles?.ja]
                    .compactMap { $0 } + (alternativeTitles?.synonyms ?? []))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMyAnimeListMangaDecodesAlternativeTitlesAndAllTitles -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMyAnimeListMangaAllTitlesWithoutAlternatives`
Expected: PASS. (The existing `testMyAnimeListSearchResponseDecodesAndUnwrapsNode` and detail tests still pass — `alternativeTitles` is optional and additive.)

- [ ] **Step 5: Commit**

```bash
git add Manga-Reader/Models/MyAnimeListAPI.swift Manga-ReaderTests/Manga_ReaderTests.swift
git commit -m "Decode MAL alternative_titles + add allTitles for entity resolution

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `Manga.malId` + MangaDex `links.mal` decode

Add the cross-source identity field to `Manga` and populate it for MangaDex from the
`links` object already present in every `/manga` payload. Non-MangaDex construction sites
pass `nil`.

**Files:**
- Modify: `Manga-Reader/Models/MangaDexAPI.swift` — `Manga` struct (lines 13-21), `MangaAttributes` (lines 70-104, add `links` + set `malId` in `toManga`)
- Modify: `Manga-Reader/Models/WeebCentralSource.swift:103-106` (pass `malId: nil`)
- Modify: `Manga-Reader/Views/BookmarksView.swift:69-70` (pass `malId: nil`)
- Modify: `Manga-Reader/Views/HistoryView.swift:109` (pass `malId: nil`)
- Test: `Manga-ReaderTests/Manga_ReaderTests.swift`
- Modify (tests, to keep them compiling): `Manga-ReaderTests/Manga_ReaderTests.swift` — the `sampleManga` helper (line 45-47) and the two literal `Manga(id:...)` inits (the registry test ~line 375 and any other flagged by the compiler)

**Interfaces:**
- Consumes: nothing new.
- Produces: `Manga.malId: Int?` (stored `let`, last field). `MangaAttributes.links: [String: String]?`. `toManga` sets `malId` from `links?["mal"]`.

> **Note (deliberate scope tightening vs. spec §1):** only `MangaAttributes` (the list/search
> path that builds `Manga` via `toManga`) gets `links`. `MangaDetailAttributes` is left
> untouched: the detail path produces a `MangaDetail`, never a `Manga`, so a `Manga` reaching
> the resolver always originated from a list and already carries `malId`. Adding `links` there
> would decode a field nothing reads (YAGNI).

- [ ] **Step 1: Write the failing tests**

```swift
func testMangaAttributesToMangaExtractsMalIdFromLinks() throws {
    let json = """
    {
      "title": {"en": "Berserk"},
      "links": {"mal": "2", "al": "30002"}
    }
    """.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let attrs = try decoder.decode(MangaAttributes.self, from: json)
    let manga = attrs.toManga(id: "abc", relationships: nil)
    XCTAssertEqual(manga.malId, 2)
}

func testMangaAttributesToMangaMalIdNilWhenAbsentOrNonNumeric() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let noLinks = #"{ "title": {"en": "X"} }"#.data(using: .utf8)!
    let a = try decoder.decode(MangaAttributes.self, from: noLinks)
    XCTAssertNil(a.toManga(id: "1", relationships: nil).malId)

    // MangaDex occasionally stores a non-numeric mal link — must not crash, must be nil.
    let badLink = #"{ "title": {"en": "X"}, "links": {"mal": "not-a-number"} }"#.data(using: .utf8)!
    let b = try decoder.decode(MangaAttributes.self, from: badLink)
    XCTAssertNil(b.toManga(id: "1", relationships: nil).malId)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMangaAttributesToMangaExtractsMalIdFromLinks`
Expected: FAIL — `value of type 'Manga' has no member 'malId'` (compile error).

- [ ] **Step 3: Add `malId` to `Manga`, `links` to `MangaAttributes`, set it in `toManga`**

In `Manga-Reader/Models/MangaDexAPI.swift`, add the field to `Manga` (after `coverURL`, line 20):

```swift
    let coverURL: URL?                              // ✅ Pre-built cover URL (nil if none).
    let malId: Int?                                 // Canonical MyAnimeList id, if known (nil for sources without one).
```

Add `links` to `MangaAttributes` (after `year`, line 74):

```swift
    let year: Int?                                  // Optional publication year.
    let links: [String: String]?                    // External-site ids (e.g. ["mal": "25"]); values may be slugs.
```

In `toManga` (lines 94-102), pass `malId`:

```swift
        return Manga(
            id: id,
            sourceId: MangaDexSource.sourceID,          // Everything from this API belongs to the MangaDex source.
            title: resolvedTitle,
            description: resolvedDescription,
            status: resolvedStatus,
            year: year,
            coverURL: cover,
            malId: links?["mal"].flatMap(Int.init)      // Free cross-source identity when MangaDex provides it.
        )
```

- [ ] **Step 4: Update the other `Manga(...)` construction sites to pass `malId: nil`**

`Manga-Reader/Models/WeebCentralSource.swift:104` →

```swift
        Manga(id: id, sourceId: Self.sourceID, title: title, description: "",
              status: "unknown", year: nil, coverURL: cover.flatMap(URL.init(string:)), malId: nil)
```

`Manga-Reader/Views/BookmarksView.swift:69-70` →

```swift
        Manga(id: id, sourceId: sourceId ?? MangaDexSource.sourceID, title: title,
              description: "", status: "unknown", year: nil, coverURL: coverURL, malId: nil)
```

`Manga-Reader/Views/HistoryView.swift:109` →

```swift
        Manga(id: mangaId, sourceId: sourceId ?? MangaDexSource.sourceID, title: mangaTitle, description: "", status: "unknown", year: nil, coverURL: coverURL, malId: nil)
```

- [ ] **Step 5: Update test construction sites to keep the suite compiling**

`Manga-ReaderTests/Manga_ReaderTests.swift`, `sampleManga` helper (line 46) →

```swift
        Manga(id: id, sourceId: sourceId, title: "Title \(id)", description: "", status: "ongoing", year: nil, coverURL: nil, malId: nil)
```

The literal init in `testRegistrySourceForMangaUsesSourceId` (line 372) →

```swift
        let manga = Manga(id: "x", sourceId: "b", title: "T", description: "", status: "ongoing", year: nil, coverURL: nil, malId: nil)
```

These are the only two literal `Manga(...)` inits in the unit-test file (the third `Manga(id:` grep hit, ~line 456, is a `toManga(id:...)` method call — leave it). Build the test target afterward; if the compiler flags any other `Manga(...)` site, append `malId: nil` to it.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMangaAttributesToMangaExtractsMalIdFromLinks -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMangaAttributesToMangaMalIdNilWhenAbsentOrNonNumeric`
Expected: PASS, and the full suite compiles (no other `Manga(...)` site left un-updated).

- [ ] **Step 7: Commit**

```bash
git add Manga-Reader Manga-ReaderTests
git commit -m "Add Manga.malId; MangaDex populates it from attributes.links.mal

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `MALTitleMatcher` — pure matching core

The one piece with non-trivial logic and the piece that carries the heavy unit tests. No
network, no store — a source title + candidates in, a decision out.

**Files:**
- Create: `Manga-Reader/Services/MALTitleMatcher.swift`
- Test: `Manga-ReaderTests/Manga_ReaderTests.swift`

**Interfaces:**
- Consumes: nothing (self-contained).
- Produces:
  - `struct MALCandidate: Equatable { let malId: Int; let titles: [String] }`
  - `enum MALMatchDecision: Equatable { case matched(malId: Int); case noMatch }`
  - `struct MALTitleMatcher { var acceptanceThreshold: Double = 0.90; var ambiguityMargin: Double = 0.05; static func normalize(_:) -> String; static func similarity(_:_:) -> Double; func decide(sourceTitle:candidates:) -> MALMatchDecision }`

- [ ] **Step 1: Write the failing tests**

```swift
// MARK: - MALTitleMatcher

func testMALNormalizeStripsCaseDiacriticsPunctuationAndNoise() {
    XCTAssertEqual(MALTitleMatcher.normalize("Attack on Titan (Manga)"), "attack on titan")
    XCTAssertEqual(MALTitleMatcher.normalize("Ōkami!!  Shōnen"), "okami shonen")
    XCTAssertEqual(MALTitleMatcher.normalize("  Berserk  "), "berserk")
}

func testMALSimilarityExactAfterNormalizationIsOne() {
    XCTAssertEqual(MALTitleMatcher.similarity("attack on titan", "attack on titan"), 1.0, accuracy: 0.0001)
    XCTAssertEqual(MALTitleMatcher.similarity("", "berserk"), 0.0, accuracy: 0.0001)
}

func testMALDecideMatchesViaAlternativeTitle() {
    // Source uses the English title; MAL's main title is the romaji one — the match
    // must come from the alternate title in the candidate's title set.
    let matcher = MALTitleMatcher()
    let candidates = [
        MALCandidate(malId: 25, titles: ["Shingeki no Kyojin", "Attack on Titan"]),
        MALCandidate(malId: 99, titles: ["Some Unrelated Manga"]),
    ]
    XCTAssertEqual(matcher.decide(sourceTitle: "Attack on Titan", candidates: candidates),
                   .matched(malId: 25))
}

func testMALDecideRejectsBelowThreshold() {
    let matcher = MALTitleMatcher()
    let candidates = [MALCandidate(malId: 1, titles: ["Completely Different Story"])]
    XCTAssertEqual(matcher.decide(sourceTitle: "Berserk", candidates: candidates), .noMatch)
}

func testMALDecideAmbiguityGuardRejectsNearTiedCandidates() {
    // Two distinct MAL entries share the exact title — genuinely ambiguous, reject.
    let matcher = MALTitleMatcher()
    let candidates = [
        MALCandidate(malId: 1, titles: ["Hero"]),
        MALCandidate(malId: 2, titles: ["Hero"]),
    ]
    XCTAssertEqual(matcher.decide(sourceTitle: "Hero", candidates: candidates), .noMatch)
}

func testMALDecideAcceptsClearWinnerOverWeakRunnerUp() {
    let matcher = MALTitleMatcher()
    let candidates = [
        MALCandidate(malId: 1, titles: ["Vinland Saga"]),
        MALCandidate(malId: 2, titles: ["Totally Other Thing"]),
    ]
    XCTAssertEqual(matcher.decide(sourceTitle: "Vinland Saga", candidates: candidates),
                   .matched(malId: 1))
}

func testMALDecideEmptyInputsAreNoMatch() {
    let matcher = MALTitleMatcher()
    XCTAssertEqual(matcher.decide(sourceTitle: "", candidates: [MALCandidate(malId: 1, titles: ["X"])]), .noMatch)
    XCTAssertEqual(matcher.decide(sourceTitle: "X", candidates: []), .noMatch)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMALDecideMatchesViaAlternativeTitle`
Expected: FAIL — `cannot find 'MALTitleMatcher' in scope` (compile error).

- [ ] **Step 3: Implement `MALTitleMatcher.swift`**

Create `Manga-Reader/Services/MALTitleMatcher.swift`:

```swift
//
//  MALTitleMatcher.swift
//  Manga-Reader
//
//  Pure title-matching core for cross-source entity resolution: given a source manga's
//  title and MAL search candidates (each with its full title set), decide which MAL id
//  it is — or that there's no confident match. No network, no persistence; fully unit-
//  tested. Precision-biased: a high threshold plus an ambiguity guard, and any doubt
//  resolves to `.noMatch` rather than a wrong id.
//

import Foundation

/// A MAL search result reduced to what matching needs: its id and every title it goes by.
struct MALCandidate: Equatable {
    let malId: Int
    let titles: [String]
}

enum MALMatchDecision: Equatable {
    case matched(malId: Int)
    case noMatch
}

struct MALTitleMatcher {
    /// Minimum normalized similarity (0...1) required to accept a fuzzy match.
    var acceptanceThreshold: Double = 0.90
    /// The best candidate must beat the runner-up by at least this margin, else the
    /// match is treated as ambiguous and rejected.
    var ambiguityMargin: Double = 0.05

    /// Tokens dropped during normalization — structural noise, not identity.
    private static let noiseTokens: Set<String> = ["manga", "season", "part", "cour"]

    /// Lowercase, strip diacritics, replace every non-alphanumeric with a space, drop
    /// noise tokens, and collapse/trim whitespace.
    static func normalize(_ title: String) -> String {
        let folded = title.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let spacedScalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(spacedScalars)
            .split(separator: " ")
            .map(String.init)
            .filter { !noiseTokens.contains($0) }
            .joined(separator: " ")
    }

    /// Normalized Levenshtein similarity in [0, 1]; 1.0 iff the strings are equal.
    /// Callers pass already-normalized strings.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }
        let distance = levenshtein(Array(a), Array(b))
        let maxLen = max(a.count, b.count)
        return 1.0 - Double(distance) / Double(maxLen)
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1,        // deletion
                                 current[j - 1] + 1,     // insertion
                                 previous[j - 1] + cost) // substitution
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// Best MAL match for `sourceTitle` among `candidates`, or `.noMatch`.
    func decide(sourceTitle: String, candidates: [MALCandidate]) -> MALMatchDecision {
        let normSource = Self.normalize(sourceTitle)
        guard !normSource.isEmpty, !candidates.isEmpty else { return .noMatch }

        let scored = candidates
            .map { candidate -> (malId: Int, score: Double) in
                let best = candidate.titles
                    .map { Self.similarity(normSource, Self.normalize($0)) }
                    .max() ?? 0
                return (candidate.malId, best)
            }
            .sorted { $0.score > $1.score }

        guard let best = scored.first, best.score >= acceptanceThreshold else { return .noMatch }
        if scored.count >= 2, best.score - scored[1].score < ambiguityMargin {
            return .noMatch   // too close to call — precision over recall
        }
        return .matched(malId: best.malId)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMALNormalizeStripsCaseDiacriticsPunctuationAndNoise -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMALSimilarityExactAfterNormalizationIsOne -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMALDecideMatchesViaAlternativeTitle -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMALDecideRejectsBelowThreshold -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMALDecideAmbiguityGuardRejectsNearTiedCandidates -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMALDecideAcceptsClearWinnerOverWeakRunnerUp -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMALDecideEmptyInputsAreNoMatch`
Expected: PASS (all 7).

- [ ] **Step 5: Commit**

```bash
git add Manga-Reader/Services/MALTitleMatcher.swift Manga-ReaderTests/Manga_ReaderTests.swift
git commit -m "Add pure MALTitleMatcher (normalize + Levenshtein + ambiguity guard)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `EntityResolutionStore` — cache with miss TTL

Persist resolution outcomes across launches. Hits are cached forever; misses carry a
timestamp and are re-attempted after 14 days.

**Files:**
- Create: `Manga-Reader/Services/EntityResolutionStore.swift`
- Test: `Manga-ReaderTests/Manga_ReaderTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum MALResolution: Codable, Equatable { case resolved(malId: Int); case unresolved(checkedAt: Date); func isFresh(now: Date = Date()) -> Bool }`
  - `@MainActor final class EntityResolutionStore: ObservableObject` with `static let missTTL: TimeInterval`, `init(defaults:)`, `func resolution(sourceId:mangaId:) -> MALResolution?`, `func record(sourceId:mangaId:_:)`.

- [ ] **Step 1: Write the failing tests**

```swift
// MARK: - EntityResolutionStore

@MainActor func testEntityResolutionRecordsAndReadsBack() {
    let defaults = UserDefaults(suiteName: "test.entityres.\(UUID().uuidString)")!
    let store = EntityResolutionStore(defaults: defaults)
    store.record(sourceId: "weebcentral", mangaId: "abc", .resolved(malId: 42))
    XCTAssertEqual(store.resolution(sourceId: "weebcentral", mangaId: "abc"), .resolved(malId: 42))
    XCTAssertNil(store.resolution(sourceId: "weebcentral", mangaId: "other"))
}

@MainActor func testEntityResolutionKeysAreSourceQualified() {
    let defaults = UserDefaults(suiteName: "test.entityres.\(UUID().uuidString)")!
    let store = EntityResolutionStore(defaults: defaults)
    store.record(sourceId: "weebcentral", mangaId: "x", .resolved(malId: 1))
    store.record(sourceId: "mangadex", mangaId: "x", .resolved(malId: 2))
    XCTAssertEqual(store.resolution(sourceId: "weebcentral", mangaId: "x"), .resolved(malId: 1))
    XCTAssertEqual(store.resolution(sourceId: "mangadex", mangaId: "x"), .resolved(malId: 2))
}

func testMALResolutionFreshness() {
    XCTAssertTrue(MALResolution.resolved(malId: 1).isFresh())            // hits never expire
    let now = Date()
    let justMissed = MALResolution.unresolved(checkedAt: now)
    XCTAssertTrue(justMissed.isFresh(now: now))
    let old = MALResolution.unresolved(checkedAt: now.addingTimeInterval(-EntityResolutionStore.missTTL - 1))
    XCTAssertFalse(old.isFresh(now: now))                               // past TTL → stale
}

@MainActor func testEntityResolutionPersistsAcrossInstances() {
    let suite = "test.entityres.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    EntityResolutionStore(defaults: defaults).record(sourceId: "s", mangaId: "m", .resolved(malId: 7))
    let reloaded = EntityResolutionStore(defaults: defaults)
    XCTAssertEqual(reloaded.resolution(sourceId: "s", mangaId: "m"), .resolved(malId: 7))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMALResolutionFreshness`
Expected: FAIL — `cannot find 'MALResolution' in scope` (compile error).

- [ ] **Step 3: Implement `EntityResolutionStore.swift`**

Create `Manga-Reader/Services/EntityResolutionStore.swift`:

```swift
//
//  EntityResolutionStore.swift
//  Manga-Reader
//
//  Caches cross-source → MyAnimeList id resolutions so we don't re-run the fuzzy match
//  (or re-hit MAL) every time a detail page opens. Hits are cached indefinitely — a
//  manga's MAL id is stable; misses carry a timestamp and are re-attempted after a TTL,
//  so a title MAL adds later, or an improved matcher, eventually gets another chance.
//  UserDefaults-backed, mirroring HistoryStore / LibraryStore / TasteProfileStore.
//

import SwiftUI

/// The cached outcome of resolving one source manga to a MAL id.
enum MALResolution: Codable, Equatable {
    case resolved(malId: Int)          // Cached indefinitely.
    case unresolved(checkedAt: Date)   // A miss; re-attempt once older than `missTTL`.

    /// Whether this entry should still be trusted (vs. re-attempted). Hits are always
    /// fresh; a miss is fresh until it passes the TTL. `now` is injectable for tests.
    func isFresh(now: Date = Date()) -> Bool {
        switch self {
        case .resolved:
            return true
        case .unresolved(let checkedAt):
            return now.timeIntervalSince(checkedAt) < EntityResolutionStore.missTTL
        }
    }
}

@MainActor
final class EntityResolutionStore: ObservableObject {
    /// Source-qualified key ("{sourceId}:{mangaId}") → outcome.
    @Published private(set) var cache: [String: MALResolution] = [:]

    /// How long a miss is trusted before it's re-attempted.
    static let missTTL: TimeInterval = 14 * 24 * 60 * 60   // 14 days

    private let cacheKey = "entityResolution.cache"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func resolution(sourceId: String, mangaId: String) -> MALResolution? {
        cache[Self.key(sourceId, mangaId)]
    }

    func record(sourceId: String, mangaId: String, _ resolution: MALResolution) {
        cache[Self.key(sourceId, mangaId)] = resolution
        save()
    }

    private static func key(_ sourceId: String, _ mangaId: String) -> String {
        "\(sourceId):\(mangaId)"
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cache) { defaults.set(data, forKey: cacheKey) }
    }

    private func load() {
        if let data = defaults.data(forKey: cacheKey),
           let value = try? JSONDecoder().decode([String: MALResolution].self, from: data) {
            cache = value
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:Manga-ReaderTests/Manga_ReaderTests/testEntityResolutionRecordsAndReadsBack -only-testing:Manga-ReaderTests/Manga_ReaderTests/testEntityResolutionKeysAreSourceQualified -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMALResolutionFreshness -only-testing:Manga-ReaderTests/Manga_ReaderTests/testEntityResolutionPersistsAcrossInstances`
Expected: PASS (all 4).

- [ ] **Step 5: Commit**

```bash
git add Manga-Reader/Services/EntityResolutionStore.swift Manga-ReaderTests/Manga_ReaderTests.swift
git commit -m "Add EntityResolutionStore (source-qualified cache, 14-day miss TTL)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: `MALEntityResolver` — orchestration

Tie the pieces together: fast path → cache → fuzzy search + match → persist outcome. The
network path (`searchManga`) is not unit-testable here (no mock harness, per convention);
the offline-deterministic paths (fast path, cached hit, fresh cached miss) are.

**Files:**
- Create: `Manga-Reader/Services/MALEntityResolver.swift`
- Test: `Manga-ReaderTests/Manga_ReaderTests.swift`

**Interfaces:**
- Consumes: `Manga.malId` (Task 2), `MyAnimeListManga.allTitles` + `MyAnimeListAPI.searchManga` (Task 1), `MALCandidate`/`MALMatchDecision`/`MALTitleMatcher` (Task 3), `EntityResolutionStore`/`MALResolution` (Task 4).
- Produces: `@MainActor final class MALEntityResolver { init(store: EntityResolutionStore, matcher: MALTitleMatcher = .init()); func malId(for manga: Manga) async -> Int? }`.

- [ ] **Step 1: Write the failing tests** (offline-deterministic paths only)

```swift
// MARK: - MALEntityResolver

@MainActor func testResolverFastPathReturnsMangaMalIdWithoutTouchingStore() async {
    let defaults = UserDefaults(suiteName: "test.resolver.\(UUID().uuidString)")!
    let store = EntityResolutionStore(defaults: defaults)
    let resolver = MALEntityResolver(store: store)
    let manga = Manga(id: "m", sourceId: "mangadex", title: "Berserk",
                      description: "", status: "ongoing", year: nil, coverURL: nil, malId: 2)
    let id = await resolver.malId(for: manga)
    XCTAssertEqual(id, 2)
    XCTAssertTrue(store.cache.isEmpty, "fast path must not write to the cache")
}

@MainActor func testResolverReturnsCachedResolvedHit() async {
    let defaults = UserDefaults(suiteName: "test.resolver.\(UUID().uuidString)")!
    let store = EntityResolutionStore(defaults: defaults)
    store.record(sourceId: "weebcentral", mangaId: "x", .resolved(malId: 55))
    let resolver = MALEntityResolver(store: store)
    let manga = Manga(id: "x", sourceId: "weebcentral", title: "Whatever",
                      description: "", status: "unknown", year: nil, coverURL: nil, malId: nil)
    let id = await resolver.malId(for: manga)
    XCTAssertEqual(id, 55)   // returned from cache; no network
}

@MainActor func testResolverReturnsNilForFreshCachedMiss() async {
    let defaults = UserDefaults(suiteName: "test.resolver.\(UUID().uuidString)")!
    let store = EntityResolutionStore(defaults: defaults)
    store.record(sourceId: "weebcentral", mangaId: "x", .unresolved(checkedAt: Date()))
    let resolver = MALEntityResolver(store: store)
    let manga = Manga(id: "x", sourceId: "weebcentral", title: "Whatever",
                      description: "", status: "unknown", year: nil, coverURL: nil, malId: nil)
    let id = await resolver.malId(for: manga)
    XCTAssertNil(id)   // fresh miss short-circuits before any network call
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:Manga-ReaderTests/Manga_ReaderTests/testResolverFastPathReturnsMangaMalIdWithoutTouchingStore`
Expected: FAIL — `cannot find 'MALEntityResolver' in scope` (compile error).

- [ ] **Step 3: Implement `MALEntityResolver.swift`**

Create `Manga-Reader/Services/MALEntityResolver.swift`:

```swift
//
//  MALEntityResolver.swift
//  Manga-Reader
//
//  Resolves a Manga (any source) to a canonical MyAnimeList id. Fast path: a Manga that
//  already carries `malId` (MangaDex) returns it for free. Otherwise consult the cache,
//  then fall back to a title search + pure MALTitleMatcher. Precision-biased and
//  non-throwing: an ordinary no-match returns nil (the caller omits the title); a
//  transient MAL error also returns nil but is NOT cached, so an outage can't poison the
//  cache for the full miss TTL.
//

import Foundation

@MainActor
final class MALEntityResolver {
    private let store: EntityResolutionStore
    private let matcher: MALTitleMatcher

    init(store: EntityResolutionStore, matcher: MALTitleMatcher = .init()) {
        self.store = store
        self.matcher = matcher
    }

    /// The canonical MAL id for `manga`, or nil if none can be found with confidence.
    func malId(for manga: Manga) async -> Int? {
        // 1. Fast path — the source already told us (MangaDex via links.mal). No caching
        //    needed: it's free on every call.
        if let known = manga.malId { return known }

        // 2. Cache — a live entry answers without network.
        if let cached = store.resolution(sourceId: manga.sourceId, mangaId: manga.id),
           cached.isFresh() {
            if case .resolved(let id) = cached { return id }
            return nil   // fresh miss — don't re-hit MAL yet
        }

        // 3. Fuzzy — search MAL by title and match. A thrown/absent result is a transient
        //    failure: return nil WITHOUT recording a miss (only a real "candidates but no
        //    match" is worth caching).
        let results: [MyAnimeListManga]
        do {
            results = try await MyAnimeListAPI.searchManga(title: manga.title)
        } catch {
            return nil
        }

        let candidates = results.map { MALCandidate(malId: $0.id, titles: $0.allTitles) }
        switch matcher.decide(sourceTitle: manga.title, candidates: candidates) {
        case .matched(let id):
            store.record(sourceId: manga.sourceId, mangaId: manga.id, .resolved(malId: id))
            return id
        case .noMatch:
            store.record(sourceId: manga.sourceId, mangaId: manga.id, .unresolved(checkedAt: Date()))
            return nil
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:Manga-ReaderTests/Manga_ReaderTests/testResolverFastPathReturnsMangaMalIdWithoutTouchingStore -only-testing:Manga-ReaderTests/Manga_ReaderTests/testResolverReturnsCachedResolvedHit -only-testing:Manga-ReaderTests/Manga_ReaderTests/testResolverReturnsNilForFreshCachedMiss`
Expected: PASS (all 3).

- [ ] **Step 5: Commit**

```bash
git add Manga-Reader/Services/MALEntityResolver.swift Manga-ReaderTests/Manga_ReaderTests.swift
git commit -m "Add MALEntityResolver (fast path → cache → fuzzy match orchestration)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Debug-screen live verification hook

Add a "Resolve source title" section to the existing throwaway MAL debug screen so the
live fuzzy path can be eyeballed against the real API, plus a throwaway live UI test that
drives it — mirroring `testMyAnimeListDebugScreenLiveVerification`.

**Files:**
- Modify: `Manga-Reader/Views/MyAnimeListDebugView.swift`
- Modify: `Manga-ReaderUITests/Manga_ReaderUITests.swift`

**Interfaces:**
- Consumes: `MALEntityResolver`, `EntityResolutionStore`, `MyAnimeListAPI.mangaDetail` (Task 5 + existing client).
- Produces: no app-facing API (throwaway verification UI).

- [ ] **Step 1: Add a resolver section to `MyAnimeListDebugView`**

Add these `@State`s alongside the existing ones (after `isLoading`):

```swift
    @State private var resolveQuery = ""
    @State private var resolvedText: String?
```

Add this `Section` to the `List`, immediately after the existing `Section("Search")`:

```swift
            Section("Resolve source title") {
                TextField("Scraped-source title", text: $resolveQuery)
                    .accessibilityIdentifier("malResolveField")
                    .onSubmit { resolve() }
                Button("Resolve") { resolve() }
                    .accessibilityIdentifier("malResolveButton")
                    .disabled(resolveQuery.isEmpty || isLoading)
                if let resolvedText {
                    Text(resolvedText)
                        .accessibilityIdentifier("malResolveResult")
                }
            }
```

Add this method next to `search()`:

```swift
    /// Runs a synthetic scraped-source manga (no malId) through the entity resolver so
    /// the live fuzzy path can be verified end-to-end against the real MAL API.
    private func resolve() {
        resolvedText = nil
        isLoading = true
        let manga = Manga(id: "debug-\(UUID().uuidString)", sourceId: "weebcentral",
                          title: resolveQuery, description: "", status: "unknown",
                          year: nil, coverURL: nil, malId: nil)
        let resolver = MALEntityResolver(store: EntityResolutionStore())
        Task {
            defer { isLoading = false }
            if let id = await resolver.malId(for: manga) {
                let title = (try? await MyAnimeListAPI.mangaDetail(id: id))?.title ?? "?"
                resolvedText = "Resolved to MAL id \(id): \(title)"
            } else {
                resolvedText = "No confident match"
            }
        }
    }
```

- [ ] **Step 2: Build to verify the debug screen compiles**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Add a throwaway live UI test**

In `Manga-ReaderUITests/Manga_ReaderUITests.swift`, add a method mirroring the
navigation/retry pattern of `testMyAnimeListDebugScreenLiveVerification` (reuse its
Settings → `malClientRow` navigation verbatim), then drive the resolve field:

```swift
    /// Throwaway live-verification for cross-source entity resolution: drives the MAL
    /// debug screen's "Resolve source title" field with a title whose MAL main title
    /// differs from the scraped one ("Attack on Titan" → Shingeki no Kyojin), proving the
    /// alt-title fuzzy path lands on the right MAL entry against the real API. Same
    /// no-mock live technique as testMyAnimeListDebugScreenLiveVerification; keeping it
    /// long-term is a human call (it hits the network and is slow).
    func testMALEntityResolutionLiveVerification() throws {
        let app = XCUIApplication()
        app.launch()

        let settingsNavTitle = app.navigationBars["Settings"]
        var reachedSettings = false
        for _ in 0..<3 {
            app.tabBars.buttons["Settings"].tap()
            if settingsNavTitle.waitForExistence(timeout: 8) { reachedSettings = true; break }
        }
        XCTAssertTrue(reachedSettings, "should have navigated to the Settings tab")

        let malRow = app.buttons["malClientRow"]
        XCTAssertTrue(malRow.waitForExistence(timeout: 10), "the DEBUG MAL row should be on Settings")

        let resolveField = app.textFields["malResolveField"]
        var reachedDebugScreen = false
        for _ in 0..<3 {
            malRow.tap()
            if resolveField.waitForExistence(timeout: 8) { reachedDebugScreen = true; break }
        }
        XCTAssertTrue(reachedDebugScreen, "the MAL resolve field should be present")

        var focused = false
        for _ in 0..<3 {
            resolveField.tap()
            if app.keyboards.element.waitForExistence(timeout: 5) { focused = true; break }
        }
        XCTAssertTrue(focused, "the resolve field should have keyboard focus before typing")
        resolveField.typeText("Attack on Titan")
        app.buttons["malResolveButton"].tap()

        // Ground truth: the resolver must land on Shingeki no Kyojin via the English
        // alternate title. Poll generously — MAL rate-limits and this does 2 requests.
        let result = app.staticTexts["malResolveResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 90), "a resolve result should appear")
        attach(app, name: "mal-entity-resolution")  // existing screenshot helper in this file
        XCTAssertTrue(result.label.contains("Shingeki no Kyojin"),
                      "expected resolution to Shingeki no Kyojin, got: \(result.label)")
    }
```

- [ ] **Step 4: Run the live UI test**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:Manga-ReaderUITests/Manga_ReaderUITests/testMALEntityResolutionLiveVerification`
Expected: PASS — the resolve result label contains "Shingeki no Kyojin". (Slow; MAL rate-limiting can extend it. If it flakes on a 429, re-run once.)

- [ ] **Step 5: Run the full unit suite once to confirm nothing regressed**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:Manga-ReaderTests`
Expected: PASS (all existing + new unit tests).

- [ ] **Step 6: Commit**

```bash
git add Manga-Reader/Views/MyAnimeListDebugView.swift Manga-ReaderUITests/Manga_ReaderUITests.swift
git commit -m "Add resolve-source-title hook to MAL debug screen + live UI test

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Notes for the implementer

- **Do not wire the resolver into any production screen.** Subsystem 3 ("More Like This")
  does that; this plan stops at the resolver + its debug verification. The debug screen and
  its two live UI tests are throwaway and get deleted when subsystem 3 ships.
- **`MALResolution` Codable:** Swift synthesizes `Codable` for enums with associated values
  automatically — no manual coding keys needed.
- **UserDefaults in tests:** always use a unique `suiteName` per test (`UUID()`), never
  `.standard`, so tests don't bleed into each other or the app.
- **After each task**, the just-added tests plus all previously-added ones should pass;
  the plan commits per task so a bad task is easy to isolate.
```
