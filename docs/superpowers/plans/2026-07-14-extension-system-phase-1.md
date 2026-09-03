# Extension System — Phase 1 (SDK groundwork + multi-source plumbing) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the app correctly multi-source — an `isNSFW` capability, a Settings source picker with adult-source gating, and `sourceId` carried through persistence so saved/history items reopen through the source they came from.

**Architecture:** Extends the existing `MangaSource` / `SourceRegistry` seam (from the source-abstraction work). No new host-services layer yet — that arrives in Phase 2 with WeebCentral, the first source that needs it. This phase is behavior-preserving for MangaDex and validated by unit tests (with only MangaDex registered, the picker shows one entry; the machinery is proven for Phase 2 to make visible).

**Tech Stack:** SwiftUI + Foundation only. No third-party dependencies, no package manager.

## Global Constraints

- iOS deployment target 17.5; pure SwiftUI + Foundation; **no third-party dependencies or package managers**.
- New files in `Models/`, `Services/`, `Components/` auto-compile (Xcode synchronized root groups). **`Views/` is NOT synchronized** — do not add new files under `Views/`; the source picker goes **inline in `Views/SettingsView.swift`** to avoid `project.pbxproj` edits.
- Persistence changes must be **backward-compatible**: new persisted fields are optional (`var x: T? = nil`) so legacy `UserDefaults` JSON still decodes (mirrors the existing `LibraryItem.chapterNumbers` pattern). A `let` with a default value is NOT decoded by synthesized Codable — the field must be a `var` Optional.
- Run tests with: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:MangaCartaTests`. The full `test` action's UI-test target is flaky in this environment; scope to `MangaCartaTests`.
- Every commit message ends with these two trailers:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_019uB9Pu9FgykTjHDjJt2QDV
  ```
- Deferred to Phase 2 (do NOT build here): `SourceContext`/networking extraction/per-source storage; `LibraryStore.refresh` per-source resolution (harmless with one source — it still uses the active source this phase).

---

### Task 1: `isNSFW` capability on `MangaSource`

**Files:**
- Modify: `MangaCarta/Models/MangaSource.swift`
- Test: `MangaCartaTests/MangaCartaTests.swift`

**Interfaces:**
- Consumes: existing `MangaSource` protocol, existing `MockSource`/`MinimalSource` test doubles.
- Produces: `var isNSFW: Bool { get }` on `MangaSource` with a default-`false` protocol-extension implementation. `MangaDexSource.isNSFW == false` (via default). Consumed by Task 4's `SourceRegistry.visibleSources`.

- [ ] **Step 1: Write the failing test**

Add to `MangaCartaTests` (in the "Source abstraction" area):

```swift
func testMangaDexSourceIsNotNSFWByDefault() {
    XCTAssertFalse(MangaDexSource().isNSFW)
}

func testSourceCanDeclareNSFW() {
    struct AdultMock: MangaSource {
        let id = "adult"; let name = "Adult"
        var isNSFW: Bool { true }
        func search(title: String, limit: Int, offset: Int) async throws -> [Manga] { [] }
        func popular(limit: Int, offset: Int) async throws -> [Manga] { [] }
        func mangaDetail(id: String) async throws -> MangaDetail {
            MangaDetail(description: "", authors: [], tags: [], contentRating: nil)
        }
        func chapters(mangaId: String) async throws -> [Chapter] { [] }
        func pageURLs(chapterId: String, preferDataSaver: Bool) async throws -> [URL] { [] }
    }
    XCTAssertTrue(AdultMock().isNSFW)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:MangaCartaTests 2>&1 | tail -30`
Expected: FAIL to compile — `value of type 'MangaDexSource' has no member 'isNSFW'`.

- [ ] **Step 3: Add `isNSFW` to the protocol + default**

In `Models/MangaSource.swift`, add to the `protocol MangaSource` body (after `var name: String { get }`):

```swift
    /// Whether this source serves adult content. Gated behind a Settings toggle.
    var isNSFW: Bool { get }
```

And in the `extension MangaSource` (with the other default capabilities), add:

```swift
    var isNSFW: Bool { false }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:MangaCartaTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add MangaCarta/Models/MangaSource.swift MangaCartaTests/MangaCartaTests.swift
git commit -m "Add isNSFW capability to MangaSource

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019uB9Pu9FgykTjHDjJt2QDV"
```

---

### Task 2: `sourceId` on `ReadingEntry`

**Files:**
- Modify: `MangaCarta/Services/HistoryStore.swift`
- Modify: `MangaCarta/Views/HistoryView.swift:107-110` (`ReadingEntry.asManga`)
- Test: `MangaCartaTests/MangaCartaTests.swift`

**Interfaces:**
- Consumes: existing `ReadingEntry`, `HistoryStore.record(manga:chapter:page:pageCount:)`, `Manga.sourceId`, `MangaDexSource.sourceID`.
- Produces: `ReadingEntry.sourceId: String?` (nil = legacy = MangaDex). `record` persists `manga.sourceId`. `ReadingEntry.asManga` uses the stored source id.

- [ ] **Step 1: Write the failing tests**

Add to `MangaCartaTests`:

```swift
@MainActor func testReadingEntryRecordsSourceId() {
    let store = makeHistoryStore()
    let manga = sampleManga("m", sourceId: "weebcentral")
    store.record(manga: manga, chapter: Chapter(id: "c1", number: "1", title: nil), page: 0, pageCount: 5)
    XCTAssertEqual(store.entries.first?.sourceId, "weebcentral")
}

func testReadingEntryDecodesLegacyJSONAsNil() throws {
    // JSON saved before sourceId existed.
    let legacy = #"{"id":"00000000-0000-0000-0000-000000000000","mangaId":"m","mangaTitle":"T","coverURL":null,"chapterId":"c","chapterNumber":"1","page":0,"pageCount":5,"updatedAt":0}"#
        .data(using: .utf8)!
    let entry = try JSONDecoder().decode(ReadingEntry.self, from: legacy)
    XCTAssertNil(entry.sourceId)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:MangaCartaTests 2>&1 | tail -30`
Expected: FAIL to compile — `value of type 'ReadingEntry' has no member 'sourceId'`.

- [ ] **Step 3: Add the field + persist it**

In `Services/HistoryStore.swift`, add to `struct ReadingEntry` (after `var updatedAt: Date`):

```swift
    var sourceId: String? = nil   // nil = saved before multi-source; treat as MangaDex
```

In `record(...)`, update the `ReadingEntry(...)` construction to pass the source id (append the argument):

```swift
            entries.insert(
                ReadingEntry(id: UUID(), mangaId: manga.id, mangaTitle: manga.title,
                             coverURL: manga.coverURL, chapterId: chapter.id,
                             chapterNumber: chapter.number, page: page,
                             pageCount: pageCount, updatedAt: Date(),
                             sourceId: manga.sourceId),
                at: 0
            )
```

In `Views/HistoryView.swift`, change `ReadingEntry.asManga` (lines 107-110):

```swift
private extension ReadingEntry {
    var asManga: Manga {
        Manga(id: mangaId, sourceId: sourceId ?? MangaDexSource.sourceID, title: mangaTitle,
              description: "", status: "unknown", year: nil, coverURL: coverURL)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:MangaCartaTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add MangaCarta/Services/HistoryStore.swift MangaCarta/Views/HistoryView.swift MangaCartaTests/MangaCartaTests.swift
git commit -m "Persist sourceId on ReadingEntry so history reopens via the right source

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019uB9Pu9FgykTjHDjJt2QDV"
```

---

### Task 3: `sourceId` on `LibraryItem`

**Files:**
- Modify: `MangaCarta/Services/LibraryStore.swift`
- Modify: `MangaCarta/Views/BookmarksView.swift:66-70` (`LibraryItem.asManga`)
- Test: `MangaCartaTests/MangaCartaTests.swift`

**Interfaces:**
- Consumes: existing `LibraryItem`, `LibraryStore.toggle(_:)`, `Manga.sourceId`, `MangaDexSource.sourceID`.
- Produces: `LibraryItem.sourceId: String?` (nil = legacy = MangaDex). `toggle` persists `manga.sourceId`. `LibraryItem.asManga` uses the stored source id.

- [ ] **Step 1: Write the failing tests**

Add to `MangaCartaTests`:

```swift
@MainActor func testLibraryToggleRecordsSourceId() {
    let store = LibraryStore()
    let manga = sampleManga("m", sourceId: "weebcentral")
    store.toggle(manga)
    XCTAssertEqual(store.items.first?.sourceId, "weebcentral")
    store.toggle(manga)   // clean up shared UserDefaults
}

func testLibraryItemRoundTripsSourceId() throws {
    let item = LibraryItem(id: "m", title: "T", coverURL: nil, sourceId: "weebcentral")
    let data = try JSONEncoder().encode(item)
    let decoded = try JSONDecoder().decode(LibraryItem.self, from: data)
    XCTAssertEqual(decoded.sourceId, "weebcentral")
}
```

Note: the existing `testLibraryItemDecodesLegacyJSON` already covers legacy decode; after this change `item.sourceId` will be `nil` for that legacy JSON (Optional missing key), which the existing test does not assert, so it stays green.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:MangaCartaTests 2>&1 | tail -30`
Expected: FAIL to compile — `extra argument 'sourceId' in call` / `has no member 'sourceId'`.

- [ ] **Step 3: Add the field + persist it**

In `Services/LibraryStore.swift`, add to `struct LibraryItem` (after `var chapterNumbers`):

```swift
    var sourceId: String? = nil   // nil = saved before multi-source; treat as MangaDex
```

In `toggle(_:)`, pass the source id when inserting:

```swift
            items.insert(
                LibraryItem(id: manga.id, title: manga.title, coverURL: manga.coverURL,
                            sourceId: manga.sourceId),
                at: 0
            )
```

In `Views/BookmarksView.swift`, change `LibraryItem.asManga` (lines 66-70):

```swift
private extension LibraryItem {
    /// A minimal `Manga` for navigation; the detail view refetches full data by id.
    var asManga: Manga {
        Manga(id: id, sourceId: sourceId ?? MangaDexSource.sourceID, title: title,
              description: "", status: "unknown", year: nil, coverURL: coverURL)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:MangaCartaTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add MangaCarta/Services/LibraryStore.swift MangaCarta/Views/BookmarksView.swift MangaCartaTests/MangaCartaTests.swift
git commit -m "Persist sourceId on LibraryItem so bookmarks reopen via the right source

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019uB9Pu9FgykTjHDjJt2QDV"
```

---

### Task 4: Source picker + adult-source gating in Settings

**Files:**
- Modify: `MangaCarta/Services/SourceRegistry.swift` (add `visibleSources(includeAdult:)`)
- Modify: `MangaCarta/Views/SettingsView.swift` (add a "Sources" section — inline, no new file)
- Test: `MangaCartaTests/MangaCartaTests.swift`

**Interfaces:**
- Consumes: `SourceRegistry` (`sources`, `activeSourceID`), `MangaSource.isNSFW` (Task 1).
- Produces: `SourceRegistry.visibleSources(includeAdult: Bool) -> [MangaSource]` — sources filtered by the adult toggle. A `@AppStorage("settings.showAdultSources")` Bool (default false) drives the picker.

- [ ] **Step 1: Write the failing test**

Add to `MangaCartaTests`:

```swift
@MainActor func testVisibleSourcesRespectAdultToggle() {
    struct AdultMock: MangaSource {
        let id = "adult"; let name = "Adult"
        var isNSFW: Bool { true }
        func search(title: String, limit: Int, offset: Int) async throws -> [Manga] { [] }
        func popular(limit: Int, offset: Int) async throws -> [Manga] { [] }
        func mangaDetail(id: String) async throws -> MangaDetail {
            MangaDetail(description: "", authors: [], tags: [], contentRating: nil)
        }
        func chapters(mangaId: String) async throws -> [Chapter] { [] }
        func pageURLs(chapterId: String, preferDataSaver: Bool) async throws -> [URL] { [] }
    }
    let registry = SourceRegistry(sources: [MangaDexSource(), AdultMock()])

    XCTAssertEqual(registry.visibleSources(includeAdult: false).map(\.id), ["mangadex"])
    XCTAssertEqual(registry.visibleSources(includeAdult: true).map(\.id), ["mangadex", "adult"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:MangaCartaTests 2>&1 | tail -30`
Expected: FAIL to compile — `value of type 'SourceRegistry' has no member 'visibleSources'`.

- [ ] **Step 3: Add `visibleSources` to the registry**

In `Services/SourceRegistry.swift`, add a method to the class (after `source(for:)`):

```swift
    /// Sources eligible to show in the picker: adult sources only when opted in.
    func visibleSources(includeAdult: Bool) -> [MangaSource] {
        sources.filter { includeAdult || !$0.isNSFW }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:MangaCartaTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Add the Sources section to Settings**

In `Views/SettingsView.swift`, add the two stored properties at the top of `struct SettingsView` (next to `appearanceRaw`):

```swift
    @AppStorage("settings.showAdultSources") private var showAdultSources = false
    @ObservedObject private var registry = SourceRegistry.shared
```

Insert this section in the `VStack` **before** the "About" section:

```swift
                    VStack(alignment: .leading, spacing: 14) {
                        InkSectionHeader("Sources", eyebrow: "Content")
                        VStack(spacing: 0) {
                            let visible = registry.visibleSources(includeAdult: showAdultSources)
                            ForEach(Array(visible.enumerated()), id: \.element.id) { idx, source in
                                if idx > 0 {
                                    Divider().overlay(Ink.hairline).padding(.leading, Gutter.page)
                                }
                                Button {
                                    registry.activeSourceID = source.id
                                } label: {
                                    HStack {
                                        Text(source.name)
                                            .font(.subheadline)
                                            .foregroundStyle(Ink.primary)
                                        Spacer()
                                        if source.id == registry.activeSourceID {
                                            Image(systemName: "checkmark").foregroundStyle(Ink.seal)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.horizontal, Gutter.page)
                                    .padding(.vertical, 15)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 14).fill(Ink.surface))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.hairline, lineWidth: 1))
                        .padding(.horizontal, Gutter.page)

                        Toggle("Show adult sources", isOn: $showAdultSources)
                            .font(.subheadline)
                            .tint(Ink.seal)
                            .padding(.horizontal, Gutter.page)
                    }
```

- [ ] **Step 6: Build to verify the view compiles**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add MangaCarta/Services/SourceRegistry.swift MangaCarta/Views/SettingsView.swift MangaCartaTests/MangaCartaTests.swift
git commit -m "Add source picker + adult-source gating to Settings

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019uB9Pu9FgykTjHDjJt2QDV"
```

---

## Final verification

- [ ] **Full unit suite:** `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:MangaCartaTests 2>&1 | tail -5` → `** TEST SUCCEEDED **`.
- [ ] **Live smoke test:** boot iPhone 17 sim, install + launch, open Settings → confirm a "Sources" section with MangaDex checked and a "Show adult sources" toggle; Home still browses via MangaDex. (Full source-switching becomes visible in Phase 2 when WeebCentral is added.)
- [ ] **pbxproj clean:** confirm `git status` shows no `project.pbxproj` change (all edits were to existing files / synchronized groups). If Xcode reshuffled it cosmetically, `git checkout -- MangaCarta.xcodeproj/project.pbxproj`.

## Self-review notes (against the spec)

- Spec Phase 1 items covered: `isNSFW` + adult toggle (Task 1, 4), source picker (Task 4), `sourceId` in `LibraryItem`/`ReadingEntry` + migration + fixing the hardcoded `"mangadex"` reconstruction (Tasks 2, 3).
- Deliberately deferred to Phase 2 (flagged to the user): `SourceContext`/networking extraction/per-source storage (no Phase-1 consumer — YAGNI), and `LibraryStore.refresh` per-source resolution (no observable effect with a single source; WeebCentral makes it testable and meaningful).
