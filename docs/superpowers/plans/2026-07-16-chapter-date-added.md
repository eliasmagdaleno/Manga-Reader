# Chapter "Date Added" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show each chapter's publish/added date in the detail chapter list, for every source that provides it (MangaDex + WeebCentral).

**Architecture:** Add an optional `date: Date?` to the `Chapter` domain type (with a defaulted initializer so existing call sites are untouched) plus a shared ISO-8601 parse helper. MangaDex populates it from `publishAt`; WeebCentral from its chapter rows' `<time datetime>`. The detail row renders the date, compact/absolute, right-aligned, when present.

**Tech Stack:** Swift / SwiftUI / Foundation / XCTest. No third-party deps.

**Spec:** `docs/superpowers/specs/2026-07-16-chapter-date-added-design.md` (authoritative).

## Global Constraints

- Pure SwiftUI + Foundation + system frameworks. NO third-party deps.
- `Models/` is a synchronized Xcode group (auto-compiled, no pbxproj edits). `Views/` and the test target are NOT synchronized — but this plan only MODIFIES existing files there (`MangaDetailView.swift`, `MangaCartaTests.swift`), which needs no pbxproj edits.
- Build: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Unit tests (scope to the unit target): `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:MangaCartaTests` (minutes; be patient).
- After any build, revert cosmetic pbxproj churn: `git checkout -- MangaCarta.xcodeproj/project.pbxproj`.
- Every commit ends with the trailer: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- Date format = the app's existing absolute style: `.formatted(.dateTime.month().day().year())` ("Jul 12, 2026"). Placement: right-aligned in the chapter row, before the chevron (first cut; user may adjust after review).
- Scope: MangaDex + WeebCentral only. private-source is deferred to its own branch and is NOT part of this plan.

---

### Task 1: `Chapter.date` + ISO-8601 helper + MangaDex population

Add the model field, the parse helper, and wire MangaDex — the field is only meaningful once a source populates it, so this task delivers all three.

**Files:**
- Modify: `MangaCarta/Models/MangaDexAPI.swift` (the `Chapter` struct ~lines 153-157, and `ChapterAttributes.toChapter` ~lines 159-163)
- Test: `MangaCartaTests/MangaCartaTests.swift` (append)

**Interfaces:**
- Produces: `Chapter(id:number:title:date:)` with `date: Date? = nil` defaulted (existing `Chapter(id:number:title:)` calls keep compiling); `static func Chapter.parseISO8601(_ string: String?) -> Date?`; `ChapterAttributes.toChapter(id:)` now sets `date` from `publishAt ?? readableAt`.

- [ ] **Step 1: Write the failing tests** — append inside the `MangaCartaTests` class:

```swift
    // MARK: - Chapter date-added (MangaDex)

    func testChapterParseISO8601() {
        XCTAssertNotNil(Chapter.parseISO8601("2024-01-15T12:00:00+00:00"))
        XCTAssertNotNil(Chapter.parseISO8601("2024-01-15T12:00:00.123+00:00"))  // fractional seconds
        XCTAssertNotNil(Chapter.parseISO8601("2024-01-15T12:00:00Z"))
        XCTAssertNil(Chapter.parseISO8601(nil))
        XCTAssertNil(Chapter.parseISO8601(""))
        XCTAssertNil(Chapter.parseISO8601("not a date"))
    }

    func testChapterDateDefaultsToNil() {
        XCTAssertNil(Chapter(id: "c1", number: "1", title: nil).date)   // existing call shape → nil
    }

    func testMangaDexToChapterUsesPublishAt() throws {
        let json = #"{"chapter":"12","title":"T","translatedLanguage":"en","publishAt":"2024-01-15T12:00:00+00:00","readableAt":"2024-01-16T12:00:00+00:00"}"#
        let attrs = try JSONDecoder().decode(ChapterAttributes.self, from: Data(json.utf8))
        XCTAssertEqual(attrs.toChapter(id: "c1").date, Chapter.parseISO8601("2024-01-15T12:00:00+00:00"))
    }

    func testMangaDexToChapterFallsBackToReadableAt() throws {
        let json = #"{"chapter":"12","title":null,"translatedLanguage":"en","publishAt":null,"readableAt":"2024-01-16T12:00:00+00:00"}"#
        let attrs = try JSONDecoder().decode(ChapterAttributes.self, from: Data(json.utf8))
        XCTAssertEqual(attrs.toChapter(id: "c1").date, Chapter.parseISO8601("2024-01-16T12:00:00+00:00"))
    }

    func testMangaDexToChapterNilWhenNoTimestamps() throws {
        let json = #"{"chapter":"12","title":null,"translatedLanguage":"en","publishAt":null,"readableAt":null}"#
        let attrs = try JSONDecoder().decode(ChapterAttributes.self, from: Data(json.utf8))
        XCTAssertNil(attrs.toChapter(id: "c1").date)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:MangaCartaTests 2>&1 | tail -20`
Expected: build failure — `Chapter has no member 'parseISO8601'` and `extra argument 'date'`.

- [ ] **Step 3: Implement** in `MangaCarta/Models/MangaDexAPI.swift`.

Replace the `Chapter` struct with the field + defaulted init + parse helper:

```swift
/// A single readable chapter for the detail screen's chapter list.
struct Chapter: Identifiable, Equatable {           // Identifiable so SwiftUI ForEach works directly.
    let id: String                                  // Chapter UUID (used to open the reader).
    let number: String                              // Chapter number as displayed (e.g., "12").
    let title: String?                              // Optional chapter title.
    let date: Date?                                 // When the chapter was added/published (nil if unknown).

    init(id: String, number: String, title: String?, date: Date? = nil) {
        self.id = id
        self.number = number
        self.title = title
        self.date = date
    }

    /// Parse an ISO-8601 timestamp (with or without fractional seconds) into a `Date`.
    /// Shared by the sources that expose a chapter date. Returns nil for nil/empty/garbage.
    static func parseISO8601(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
```

Replace `ChapterAttributes.toChapter` to populate `date`:

```swift
extension ChapterAttributes {                       // Convert raw chapter attributes → domain `Chapter`.
    /// Builds a `Chapter` from decoded attributes plus the chapter id from its container.
    func toChapter(id: String) -> Chapter {
        Chapter(id: id, number: chapter ?? "?", title: title,
                date: Chapter.parseISO8601(publishAt ?? readableAt))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:MangaCartaTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **` — the new tests plus every pre-existing test (existing `Chapter(id:number:title:)` calls still compile via the defaulted init).

- [ ] **Step 5: Commit**

```bash
git checkout -- MangaCarta.xcodeproj/project.pbxproj 2>/dev/null || true
git add MangaCarta/Models/MangaDexAPI.swift MangaCartaTests/MangaCartaTests.swift
git commit -m "Add Chapter.date + ISO-8601 helper; MangaDex populates it from publishAt

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: WeebCentral populates `Chapter.date` from the row `<time>`

**Files:**
- Modify: `MangaCarta/Models/WeebCentralSource.swift` (the `chapters(mangaId:)` mapping ~line 71, the `WCChapterItem` DTO ~lines 139-142, and `chaptersScript` ~lines 209-227)
- Test: `MangaCartaTests/MangaCartaTests.swift` (append)

**Interfaces:**
- Consumes: `Chapter(id:number:title:date:)`, `Chapter.parseISO8601` (Task 1); the existing `MockWebView` test helper.
- Produces: `WCChapterItem` gains `date: String?`; `chapters(mangaId:)` maps it through `Chapter.parseISO8601`.

- [ ] **Step 1: Write the failing test** — append inside the `MangaCartaTests` class:

```swift
    // MARK: - Chapter date-added (WeebCentral)

    @MainActor func testWeebCentralChaptersCarryDate() async throws {
        let (source, mock) = makeWeebCentral()
        mock.responses["https://weebcentral.com/series/01J76XYZ/full-chapter-list"] = #"""
        [{"id": "chap3", "title": "Chapter 105", "date": "2024-01-15T12:00:00Z"},
         {"id": "chap2", "title": "Chapter 104", "date": null}]
        """#
        let chapters = try await source.chapters(mangaId: "01J76XYZ")
        XCTAssertEqual(chapters[0].date, Chapter.parseISO8601("2024-01-15T12:00:00Z"))
        XCTAssertNil(chapters[1].date)
    }
```

(The existing `testWeebCentralChaptersMapping` fixture has no `date` key; decoding an optional `date: String?` from JSON that omits it yields nil, so that test keeps passing unchanged.)

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:MangaCartaTests 2>&1 | tail -20`
Expected: `testWeebCentralChaptersCarryDate` FAILS on the assertion — the current mapping builds `Chapter` without a date (and `WCChapterItem` has no `date` field, so the fixture's `date` key is ignored), so `chapters[0].date` is `nil`, not the parsed date. (Compiles fine; it's an assertion failure.)

- [ ] **Step 3: Implement** in `MangaCarta/Models/WeebCentralSource.swift`.

Add `date` to the DTO:

```swift
private struct WCChapterItem: Decodable {
    let id: String
    let title: String
    let date: String?
}
```

Map it in `chapters(mangaId:)` (the `.map` at ~line 71):

```swift
        return items.map {
            Chapter(id: $0.id, number: Self.chapterNumber(fromTitle: $0.title),
                    title: $0.title, date: Chapter.parseISO8601($0.date))
        }
```

Extend `chaptersScript` to read the row's `<time datetime>` (the reference exposes it on a `<time>` element; grab any `time[datetime]` inside the row):

```swift
    static let chaptersScript = #"""
    (() => {
      const seg = (href, name) => {
        const parts = (href || '').replace(/\/$/, '').split('/');
        const i = parts.indexOf(name);
        return i >= 0 && parts[i + 1] ? parts[i + 1] : null;
      };
      const items = [...document.querySelectorAll('a.flex.items-center')].map(a => {
        const titleEl = a.querySelector('span.grow.flex.gap-2 span')
          || a.querySelector('span.grow span')
          || a.querySelector('span');
        const timeEl = a.querySelector('time[datetime]');
        return {
          id: seg(a.getAttribute('href'), 'chapters'),
          title: titleEl ? titleEl.textContent.trim() : '',
          date: timeEl ? timeEl.getAttribute('datetime') : null
        };
      }).filter(x => x.id);
      return JSON.stringify(items);
    })()
    """#
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:MangaCartaTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **` — the new date test, the unchanged existing WeebCentral chapter test, and everything else. (The `<time datetime>` selector is confirmed against live HTML in the branch's live check; the mock test verifies the DTO→`Chapter.date` mapping.)

- [ ] **Step 5: Commit**

```bash
git checkout -- MangaCarta.xcodeproj/project.pbxproj 2>/dev/null || true
git add MangaCarta/Models/WeebCentralSource.swift MangaCartaTests/MangaCartaTests.swift
git commit -m "WeebCentral: populate Chapter.date from the chapter-row <time datetime>

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Detail chapter row shows the date

**Files:**
- Modify: `MangaCarta/Views/MangaDetailView.swift` (`chapterRow` ~lines 385-430)
- Test: none (visual; build + full unit-suite regression, then human review)

**Interfaces:**
- Consumes: `Chapter.date` (Task 1).

- [ ] **Step 1: Read `chapterRow`** and locate the trailing `Spacer(minLength: 8)` followed by the `if !isSelecting { Image(systemName: "chevron.right") … }` block (~lines 419-425).

- [ ] **Step 2: Insert the date** between the `Spacer` and the chevron block:

```swift
            Spacer(minLength: 8)

            if let date = chapter.date {
                Text(date.formatted(.dateTime.month().day().year()))
                    .font(.inkMono(11, weight: .medium))
                    .foregroundStyle(dimmed ? Ink.tertiary : Ink.secondary)
            }

            if !isSelecting {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.tertiary)
            }
```

(Only the `if let date = chapter.date { … }` block is new; the surrounding `Spacer` and chevron are unchanged.)

- [ ] **Step 3: Build + full unit suite (regression only)**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`
Then: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:MangaCartaTests 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git checkout -- MangaCarta.xcodeproj/project.pbxproj 2>/dev/null || true
git add MangaCarta/Views/MangaDetailView.swift
git commit -m "Show chapter added-date in the detail chapter row

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Build + install for human review**

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -path "*Build/Products/Debug-iphonesimulator/MangaCarta.app" -not -path "*Index.noindex*" -print -quit)
xcrun simctl boot "iPhone 17" 2>/dev/null || true
xcrun simctl install booted "$APP" && xcrun simctl launch booted Elias-Magdaleno.Manga-Reader
```

Human checks a MangaDex (and WeebCentral) title's chapter list: each chapter row shows its
added-date right-aligned ("Jul 12, 2026"); chapters with no date show no date; placement/size
feels right (the user may request a move or a more compact format).
