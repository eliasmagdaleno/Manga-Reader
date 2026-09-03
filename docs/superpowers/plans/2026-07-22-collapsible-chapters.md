# Collapsible Chapters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Truncate the detail-page chapter list to a 5-chapter preview and move the full list (sort + multi-select) to a dedicated pushed screen, so the "More Like This" rail is reachable in one short scroll.

**Architecture:** Extract the per-chapter row into a shared `Components/ChapterRow`. Add a new `Views/ChapterListView` screen that owns the full list, the newest/oldest sort toggle, and multi-select batch actions (a lift of logic currently in `MangaDetailView`). Slim the detail page's Chapters section down to a preview (newest 5 + "Show all N chapters" → `ChapterListView`), removing select/sort state from `MangaDetailView`.

**Tech Stack:** SwiftUI, Foundation. No third-party deps. Xcode project (no SPM). iOS 17.5 deployment target.

**Spec:** `docs/superpowers/specs/2026-07-22-collapsible-chapters-design.md`

## Global Constraints

- **No third-party dependencies.** Pure SwiftUI + Foundation only.
- **App sources live under `MangaCarta/MangaCarta/…`** (double nesting), e.g. `MangaCarta/MangaCarta/Views/ChapterListView.swift`.
- **`Components/` and `Models/` are Xcode synchronized groups** (new files auto-compile, no `project.pbxproj` edit). **`Views/` is NOT** — a new `Views/` file needs the four-part `project.pbxproj` wiring (see Task 2).
- **Build/test on the iPhone 17 simulator** (no iPhone 16 on this machine — CLAUDE.md's example is outdated) with **`-parallel-testing-enabled NO`** (user dislikes cloned sim instances).
- **SourceKit/LSP false alarms:** standalone diagnostics like "No such module 'XCTest'" or "Cannot find type 'Chapter'/'Manga' in scope" fire because the indexer can't resolve module-internal types. **Judge correctness ONLY by the `xcodebuild` run**, never the diagnostics.
- **Preview size is 5** chapters (newest-first).
- End commit messages with the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer.

---

## Task 1: Extract `ChapterRow` into `Components/`

Lift the private `chapterRow(_:selected:)` from `MangaDetailView` into a standalone, reusable `ChapterRow` view so both the detail-page preview (Task 3) and the full-list screen (Task 2) render identical rows. Pure refactor — no behavior change. `Components/` is a synchronized group, so no `project.pbxproj` edit.

**Files:**
- Create: `MangaCarta/Components/ChapterRow.swift`
- Modify: `MangaCarta/Views/MangaDetailView.swift` (call `ChapterRow`, delete the private `chapterRow` func)

**Interfaces:**
- Consumes: `Chapter` (`Models/MangaDexAPI.swift`), `HistoryStore` (`func isRead(chapterId:) -> Bool`, `func entry(forChapter:) -> ReadingEntry?`), `Ink`/`Gutter` design tokens.
- Produces: `ChapterRow(chapter: Chapter, selecting: Bool = false, selected: Bool = false)` — a `View` reading `HistoryStore` from the environment. Consumed by Tasks 2 and 3.

- [ ] **Step 1: Create the shared row**

Create `MangaCarta/Components/ChapterRow.swift` (this is the exact body currently in `MangaDetailView.chapterRow`, with `isSelecting` replaced by the `selecting` parameter):

```swift
//
//  ChapterRow.swift
//  MangaCarta
//
//  One chapter row, shared by the detail-page preview and the full ChapterListView.
//  Reads read/progress state from HistoryStore. `selecting` shows the selection circle
//  (and hides the trailing chevron); `selected` fills it.
//

import SwiftUI

struct ChapterRow: View {
    let chapter: Chapter
    var selecting: Bool = false
    var selected: Bool = false
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        // Show a resume marker only while a chapter is genuinely mid-read; that
        // chapter stays highlighted (your current spot). Finished/opened
        // chapters that aren't mid-read are dimmed.
        let progress = history.entry(forChapter: chapter.id)
        let inProgress = progress.map { $0.pageCount > 0 && $0.page < $0.pageCount - 1 } ?? false
        let dimmed = history.isRead(chapterId: chapter.id) && !inProgress

        return HStack(spacing: 14) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(selected ? Ink.seal : Ink.tertiary)
            }

            // Monospaced chapter stamp, like a spine number.
            Text("CH·\(chapter.number)")
                .font(.inkMono(12, weight: .semibold))
                .foregroundStyle(dimmed ? Ink.tertiary : Ink.seal)
                .frame(minWidth: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.title?.isEmpty == false ? chapter.title! : "Chapter \(chapter.number)")
                    .font(.subheadline)
                    .foregroundStyle(dimmed ? Ink.tertiary : Ink.primary)
                    .lineLimit(1)

                if inProgress, let p = progress {
                    Text("Page: \(p.page + 1)")
                        .font(.inkMono(11, weight: .semibold))
                        .foregroundStyle(Ink.seal)
                } else if let date = chapter.date {
                    Text(date.formatted(.dateTime.month().day().year()))
                        .font(.inkMono(11, weight: .medium))
                        .foregroundStyle(dimmed ? Ink.tertiary : Ink.secondary)
                }
            }

            Spacer(minLength: 8)

            if !selecting {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.tertiary)
            }
        }
        .padding(.horizontal, Gutter.page)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 2: Point `MangaDetailView` at `ChapterRow`**

In `MangaCarta/Views/MangaDetailView.swift`, the chapters `ForEach` (currently ~lines 414-441) calls `chapterRow(chapter, selected:)`. Replace both call sites so they build `ChapterRow` instead. Change:

```swift
                        if isSelecting {
                            Button {
                                toggleSelection(chapter.id)
                            } label: {
                                chapterRow(chapter, selected: selectedChapterIDs.contains(chapter.id))
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink {
                                ReaderView(manga: manga, chapter: chapter)
                            } label: {
                                chapterRow(chapter, selected: false)
                            }
```
to:
```swift
                        if isSelecting {
                            Button {
                                toggleSelection(chapter.id)
                            } label: {
                                ChapterRow(chapter: chapter, selecting: true,
                                           selected: selectedChapterIDs.contains(chapter.id))
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink {
                                ReaderView(manga: manga, chapter: chapter)
                            } label: {
                                ChapterRow(chapter: chapter)
                            }
```

- [ ] **Step 3: Delete the now-unused private `chapterRow`**

In `MangaCarta/Views/MangaDetailView.swift`, delete the entire `private func chapterRow(_ chapter: Chapter, selected: Bool) -> some View { … }` method (currently ~lines 472-524). Nothing else references it after Step 2.

- [ ] **Step 4: Build**

Run:
```sh
xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `** BUILD SUCCEEDED **`. (Ignore SourceKit "cannot find type" noise.)

- [ ] **Step 5: Regression — the existing detail UI test still passes**

Run:
```sh
xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO test \
  -only-testing:MangaCartaUITests/MangaCartaUITests/testHomeAndDetailScreenshots
```
Expected: `** TEST SUCCEEDED **` (Home → Detail still renders the chapter rows).

- [ ] **Step 6: Commit**

```sh
git add MangaCarta/Components/ChapterRow.swift MangaCarta/Views/MangaDetailView.swift
git commit -m "Extract ChapterRow into Components (shared by preview + full list)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Create `ChapterListView` — the full-list screen

The dedicated pushed screen that owns the complete chapter list, the newest/oldest sort toggle, and multi-select batch actions (Select All / Mark Read / Mark Unread / Cancel). This lifts the sort + select logic currently in `MangaDetailView` into a standalone screen; Task 3 removes the detail-page copies and links here. New `Views/` file → needs `project.pbxproj` wiring.

**Files:**
- Create: `MangaCarta/Views/ChapterListView.swift`
- Modify: `MangaCarta.xcodeproj/project.pbxproj` (four-part wiring)

**Interfaces:**
- Consumes: `ChapterRow` (Task 1), `Chapter`, `Manga`, `HistoryStore` (`isRead(chapterId:)`, `toggleRead(manga:chapter:)`, `markRead(manga:chapters:)`, `markUnread(manga:chapters:)`), `ReaderView(manga:chapter:)`, `sortChapters(_:descending:)` (`Models/ReadingResume.swift`), `Ink`/`Gutter` tokens.
- Produces: `ChapterListView(manga: Manga, chapters: [Chapter])` — a pushable screen. Consumed by Task 3. Exposes `accessibilityIdentifier("chapterListScreen")`.

- [ ] **Step 1: Create the screen**

Create `MangaCarta/Views/ChapterListView.swift`:

```swift
//
//  ChapterListView.swift
//  MangaCarta
//
//  The full chapter list for a manga: newest/oldest sort toggle + multi-select
//  batch actions (mark read/unread). Pushed from the detail page's "Show all N
//  chapters" affordance; the detail page itself shows only a short preview.
//

import SwiftUI

struct ChapterListView: View {
    let manga: Manga
    let chapters: [Chapter]
    @EnvironmentObject private var history: HistoryStore
    @State private var descending = true
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortChapters(chapters, descending: descending)) { chapter in
                    if isSelecting {
                        Button {
                            toggleSelection(chapter.id)
                        } label: {
                            ChapterRow(chapter: chapter, selecting: true,
                                       selected: selectedIDs.contains(chapter.id))
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            ReaderView(manga: manga, chapter: chapter)
                        } label: {
                            ChapterRow(chapter: chapter)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            let read = history.isRead(chapterId: chapter.id)
                            Button {
                                history.toggleRead(manga: manga, chapter: chapter)
                            } label: {
                                Label(read ? "Mark as unread" : "Mark as read",
                                      systemImage: read ? "circle" : "checkmark.circle")
                            }
                        }
                    }
                    Divider().overlay(Ink.hairline)
                        .padding(.leading, Gutter.page)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Ink.background)
        .navigationTitle("Chapters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSelecting {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            isSelecting = false
                            selectedIDs.removeAll()
                        }
                    } label: {
                        Text("CANCEL")
                            .font(.inkMono(11, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(Ink.seal)
                    }
                } else {
                    HStack(spacing: 16) {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { isSelecting = true }
                        } label: {
                            Text("SELECT")
                                .font(.inkMono(11, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(Ink.seal)
                        }
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { descending.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.arrow.down")
                                Text(descending ? "NEWEST" : "OLDEST")
                            }
                            .font(.inkMono(11, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(Ink.seal)
                        }
                    }
                }
            }
            if isSelecting {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(allSelected ? "Deselect All" : "Select All") {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedIDs = allSelected ? [] : Set(chapters.map(\.id))
                        }
                    }
                    Spacer()
                    Button("Mark Unread") { markSelected(read: false) }
                        .disabled(selectedIDs.isEmpty)
                    Button("Mark Read") { markSelected(read: true) }
                        .disabled(selectedIDs.isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
        .accessibilityIdentifier("chapterListScreen")
    }

    private var allSelected: Bool {
        !chapters.isEmpty && selectedIDs.count == chapters.count
    }

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func markSelected(read: Bool) {
        let picked = chapters.filter { selectedIDs.contains($0.id) }
        if read {
            history.markRead(manga: manga, chapters: picked)
        } else {
            history.markUnread(manga: manga, chapters: picked)
        }
        withAnimation(.snappy(duration: 0.2)) {
            isSelecting = false
            selectedIDs.removeAll()
        }
    }
}
```

- [ ] **Step 2: Wire the file into `project.pbxproj`**

`Views/` is not synchronized, so mirror `ReaderView.swift`'s four entries with **two freshly-generated unique 24-character hex IDs** (call them `<BUILD_ID>` for the build file and `<REF_ID>` for the file reference — they must not collide with any existing ID in the file). In `MangaCarta.xcodeproj/project.pbxproj`:

(a) In the `PBXBuildFile` section (near the `ReaderView.swift in Sources` line), add:
```
		<BUILD_ID> /* ChapterListView.swift in Sources */ = {isa = PBXBuildFile; fileRef = <REF_ID> /* ChapterListView.swift */; };
```
(b) In the `PBXFileReference` section (near the `ReaderView.swift` fileRef line), add:
```
		<REF_ID> /* ChapterListView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ChapterListView.swift; sourceTree = "<group>"; };
```
(c) In the `Views` `PBXGroup` children list (near the `ReaderView.swift` child entry), add:
```
				<REF_ID> /* ChapterListView.swift */,
```
(d) In the target's `Sources` build phase `files` list (near the `ReaderView.swift in Sources` entry), add:
```
				<BUILD_ID> /* ChapterListView.swift in Sources */,
```

To generate two IDs: `python3 -c "import uuid;print(uuid.uuid4().hex[:24].upper());print(uuid.uuid4().hex[:24].upper())"`.

- [ ] **Step 3: Build**

Run:
```sh
xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `** BUILD SUCCEEDED **`. If it fails with a project-parse error, the pbxproj edit is malformed (a mistyped/duplicate ID or a missing comma) — re-check the four insertions against `ReaderView.swift`'s entries.

- [ ] **Step 4: Commit**

```sh
git add MangaCarta/Views/ChapterListView.swift MangaCarta.xcodeproj/project.pbxproj
git commit -m "Add ChapterListView: full chapter list screen (sort + multi-select)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Truncated preview on the detail page + wiring + UI verification

Add a pure `chapterPreview` helper (newest-first, capped), unit-test it, then convert `MangaDetailView`'s Chapters section into the preview (newest 5 + "Show all N chapters" → `ChapterListView`) and remove the select/sort machinery now living in `ChapterListView`. Verify with the pure test plus two live UI tests.

**Files:**
- Modify: `MangaCarta/Models/ReadingResume.swift` (add `chapterPreview`)
- Test: `MangaCartaTests/MangaCartaTests.swift` (unit test for `chapterPreview`)
- Modify: `MangaCarta/Views/MangaDetailView.swift` (preview section; remove select/sort state)
- Test: `MangaCartaUITests/MangaCartaUITests.swift` (two UI tests)

**Interfaces:**
- Consumes: `sortChapters(_:descending:)`, `Chapter`, `ChapterListView(manga:chapters:)` (Task 2), `ChapterRow` (Task 1), `InkSectionHeader`, `Ink`/`Gutter`.
- Produces: `chapterPreview(_ chapters: [Chapter], limit: Int) -> [Chapter]` (newest-first, first `limit`). `MangaDetailView` preview exposes `accessibilityIdentifier("showAllChaptersButton")` on the "Show all" row.

- [ ] **Step 1: Write the failing unit test for `chapterPreview`**

In `MangaCartaTests/MangaCartaTests.swift`, add (Swift Testing style — match the file's existing tests; if the file uses XCTest, wrap these as `func test…()` with `XCTAssertEqual`):

```swift
    @Test func chapterPreviewReturnsNewestFirstCapped() {
        let chapters = [
            Chapter(id: "a", number: "1", title: nil),
            Chapter(id: "b", number: "2", title: nil),
            Chapter(id: "c", number: "3", title: nil),
            Chapter(id: "d", number: "4", title: nil),
            Chapter(id: "e", number: "5", title: nil),
            Chapter(id: "f", number: "6", title: nil),
        ]
        let preview = chapterPreview(chapters, limit: 5)
        #expect(preview.map(\.id) == ["f", "e", "d", "c", "b"])
        #expect(preview.count == 5)
    }

    @Test func chapterPreviewShorterThanLimitReturnsAll() {
        let chapters = [
            Chapter(id: "a", number: "1", title: nil),
            Chapter(id: "b", number: "2", title: nil),
        ]
        let preview = chapterPreview(chapters, limit: 5)
        #expect(preview.map(\.id) == ["b", "a"])
    }
```

- [ ] **Step 2: Run it to confirm it fails**

Run:
```sh
xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO test -only-testing:MangaCartaTests
```
Expected: FAIL — `chapterPreview` is undefined (compile error / missing symbol).

- [ ] **Step 3: Implement `chapterPreview`**

In `MangaCarta/Models/ReadingResume.swift`, add after `sortChapters` (after its closing brace, ~line 31):

```swift
/// The chapters shown in the detail-page preview: newest-first, capped at `limit`.
/// Truncation lives here (pure) so the detail view stays declarative and this is
/// unit-tested independently of SwiftUI.
func chapterPreview(_ chapters: [Chapter], limit: Int) -> [Chapter] {
    Array(sortChapters(chapters, descending: true).prefix(limit))
}
```

- [ ] **Step 4: Run the unit suite green**

Run:
```sh
xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO test -only-testing:MangaCartaTests
```
Expected: `** TEST SUCCEEDED **` (the two new tests plus the existing suite).

- [ ] **Step 5: Convert the Chapters section to a preview**

In `MangaCarta/Views/MangaDetailView.swift`, replace the entire `private var chapters: some View { … }` computed property (currently ~lines 356-445) with this preview version. It keeps the header, error/empty/loading states, shows the newest 5 rows as read-navigable `ChapterRow`s, and appends the "Show all" row when there are more than 5:

```swift
    private var chapters: some View {
        VStack(alignment: .leading, spacing: 12) {
            InkSectionHeader("Chapters", eyebrow: "\(vm.chapters.count) available")
                .padding(.trailing, Gutter.page)

            if let error = vm.errorMessage, vm.chapters.isEmpty {
                InkNotice(error)
                    .padding(.horizontal, Gutter.page)
            } else if vm.chapters.isEmpty {
                Text(vm.isLoading ? "Loading chapters…" : "No chapters yet.")
                    .font(.footnote)
                    .foregroundStyle(Ink.tertiary)
                    .padding(.horizontal, Gutter.page)
            } else {
                VStack(spacing: 0) {
                    ForEach(chapterPreview(vm.chapters, limit: 5)) { chapter in
                        NavigationLink {
                            ReaderView(manga: manga, chapter: chapter)
                        } label: {
                            ChapterRow(chapter: chapter)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            let read = history.isRead(chapterId: chapter.id)
                            Button {
                                history.toggleRead(manga: manga, chapter: chapter)
                            } label: {
                                Label(read ? "Mark as unread" : "Mark as read",
                                      systemImage: read ? "circle" : "checkmark.circle")
                            }
                        }
                        Divider().overlay(Ink.hairline)
                            .padding(.leading, Gutter.page)
                    }

                    if vm.chapters.count > 5 {
                        NavigationLink {
                            ChapterListView(manga: manga, chapters: vm.chapters)
                        } label: {
                            HStack {
                                Text("Show all \(vm.chapters.count) chapters")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Ink.seal)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Ink.tertiary)
                            }
                            .padding(.horizontal, Gutter.page)
                            .padding(.vertical, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("showAllChaptersButton")
                    }
                }
            }
        }
    }
```

- [ ] **Step 6: Remove the select/sort machinery from `MangaDetailView`**

The preview no longer selects or sorts, so delete these now-unused members (they live in `ChapterListView` now):

1. The `@State` declarations `chaptersDescending`, `isSelecting`, `selectedChapterIDs` (currently ~lines 15-17).
2. In `body`, the `.toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)` modifier and the `if isSelecting { ToolbarItemGroup(placement: .bottomBar) { … } }` block inside `.toolbar { … }` (the topBarTrailing safari button stays). Also delete the now-orphaned `// Hide the tab bar while selecting …` comment.
3. The helpers `allChaptersSelected`, `toggleSelection(_:)`, and `markSelected(read:)` (currently ~lines 447-470).

Leave everything else (`hero`, `actionRow`, `tags`, `description`, `moreLikeThisRail`, resume logic, `mangaSource`/`mangaWebURL`, the safari sheet) untouched.

- [ ] **Step 7: Build**

Run:
```sh
xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `** BUILD SUCCEEDED **`. If the compiler flags an unused `chaptersDescending`/`isSelecting`/`selectedChapterIDs` or a call to a deleted helper, finish removing the reference per Step 6.

- [ ] **Step 8: Add the two UI tests**

Append inside `final class MangaCartaUITests` in `MangaCartaUITests/MangaCartaUITests.swift`:

```swift
    /// The detail page shows a truncated chapter preview, so the bottom-of-page
    /// "More Like This" rail is reachable in a few swipes instead of scrolling past
    /// the entire chapter list. Opens the first Home title and asserts the rail header
    /// appears within a small number of swipes.
    func testChapterPreviewKeepsRailReachable() throws {
        let app = XCUIApplication()
        app.launch()

        let firstCard = app.buttons.matching(identifier: "mangaCoverCard").firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 20), "a cover card should load on Home")
        let libraryToggle = app.buttons["Add to Library"]
        let removeToggle = app.buttons["Remove from Library"]
        firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        if !libraryToggle.waitForExistence(timeout: 8) && !removeToggle.exists {
            firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        }
        XCTAssertTrue(libraryToggle.waitForExistence(timeout: 15) || removeToggle.exists,
                      "should have opened a manga detail page")

        XCTAssertTrue(app.staticTexts["Chapters"].waitForExistence(timeout: 15),
                      "the Chapters section should render")

        // Rail must be reachable within a handful of swipes (previously required
        // scrolling past the full list). Allow time for the async MAL/MangaDex rail load.
        let header = app.staticTexts["More Like This"]
        var reached = false
        for _ in 0..<8 where !reached {
            if header.exists { reached = true; break }
            app.swipeUp(velocity: .fast)
            usleep(500_000)
        }
        XCTAssertTrue(reached,
                      "the More Like This rail should be reachable within a few swipes of a truncated chapter list")
    }

    /// "Show all N chapters" opens the full-list screen, where sort and multi-select
    /// live. Taps through, toggles sort, then marks a chapter read via select mode.
    func testShowAllChaptersOpensFullListWithSortAndSelect() throws {
        let app = XCUIApplication()
        app.launch()

        let firstCard = app.buttons.matching(identifier: "mangaCoverCard").firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 20), "a cover card should load on Home")
        let libraryToggle = app.buttons["Add to Library"]
        let removeToggle = app.buttons["Remove from Library"]
        firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        if !libraryToggle.waitForExistence(timeout: 8) && !removeToggle.exists {
            firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        }
        XCTAssertTrue(libraryToggle.waitForExistence(timeout: 15) || removeToggle.exists,
                      "should have opened a manga detail page")

        // The "Show all" row only exists for titles with > 5 chapters. Scroll it into
        // view; popular Home titles reliably qualify. (If the first title has ≤ 5
        // chapters the button is legitimately absent — re-run against a longer title.)
        let showAll = app.buttons["showAllChaptersButton"]
        var foundShowAll = false
        for _ in 0..<10 where !foundShowAll {
            if showAll.exists { foundShowAll = true; break }
            app.swipeUp(velocity: .fast)
            usleep(500_000)
        }
        XCTAssertTrue(foundShowAll, "a long title should show the 'Show all N chapters' row")
        showAll.tap()

        // Full-list screen: assert it appeared, exercise the sort toggle, then select-mode.
        XCTAssertTrue(app.otherElements["chapterListScreen"].waitForExistence(timeout: 8)
                      || app.navigationBars["Chapters"].waitForExistence(timeout: 8),
                      "the full chapter-list screen should open")

        let newest = app.buttons["NEWEST"]
        if newest.waitForExistence(timeout: 5) {
            newest.tap()
            XCTAssertTrue(app.buttons["OLDEST"].waitForExistence(timeout: 5),
                          "the sort toggle should flip to OLDEST")
        }

        let select = app.buttons["SELECT"]
        XCTAssertTrue(select.waitForExistence(timeout: 5), "SELECT should be available on the full list")
        select.tap()
        XCTAssertTrue(app.buttons["Select All"].waitForExistence(timeout: 5),
                      "entering select mode should reveal the batch-action bar")
        app.buttons["Select All"].tap()
        let markRead = app.buttons["Mark Read"]
        XCTAssertTrue(markRead.waitForExistence(timeout: 5))
        markRead.tap()
        // Select mode dismisses after a batch action.
        XCTAssertTrue(select.waitForExistence(timeout: 5),
                      "select mode should exit after Mark Read")
    }
```

- [ ] **Step 9: Run the two UI tests**

Run:
```sh
xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO test \
  -only-testing:MangaCartaUITests/MangaCartaUITests/testChapterPreviewKeepsRailReachable \
  -only-testing:MangaCartaUITests/MangaCartaUITests/testShowAllChaptersOpensFullListWithSortAndSelect
```
Expected: both PASS. Notes: these are live/network-dependent (Home content + the MAL/MangaDex rail load). A flake is API availability, not a logic bug — re-run after a pause. If the first Home title has ≤ 5 chapters, `testShowAllChapters…` legitimately can't find the row; re-run (popular titles reliably have many chapters).

- [ ] **Step 10: Commit**

```sh
git add MangaCarta/Models/ReadingResume.swift MangaCarta/Views/MangaDetailView.swift \
  MangaCartaTests/MangaCartaTests.swift MangaCartaUITests/MangaCartaUITests.swift
git commit -m "Truncate detail chapters to a 5-item preview + Show all → ChapterListView

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification (before finishing the branch)

- [ ] **Full unit suite** (regression):
```sh
xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO test -only-testing:MangaCartaTests
```
Expected: PASS (existing suite + the two `chapterPreview` tests).

- [ ] **Whole-branch review**, then **superpowers:finishing-a-development-branch** (merge to `main` + push, matching the recommender subsystems).

## Notes for the executor

- **Verification is by `xcodebuild`, not the SourceKit indexer** — "Cannot find type 'Chapter'/'Manga'/'XCTest'" diagnostics are false alarms.
- **`MangaCartaTests.swift` test style:** the snippets use Swift Testing (`@Test` / `#expect`). If the file is XCTest-based, translate to `func test…()` + `XCTAssertEqual` — check the file's existing tests and match them.
- **The `Views/` pbxproj edit (Task 2) is the one fragile step.** A malformed edit surfaces as a project-parse failure at build; mirror `ReaderView.swift`'s four entries exactly and use fresh unique IDs.
- **Task order matters:** Task 1 (`ChapterRow`) is consumed by Tasks 2 and 3; Task 3's "Show all" links to Task 2's `ChapterListView`.
