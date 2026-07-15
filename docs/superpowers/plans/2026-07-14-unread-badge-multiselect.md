# Unread chapter badge + chapter multiselect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the library "new chapter" badge into a live "total unread chapters" count that decrements as chapters are read, and add multiselect mark-read/mark-unread (including select-all) to the chapter list in `MangaDetailView`.

**Architecture:** `LibraryItem` stores a deduped chapter-number snapshot from the last refresh (`chapterNumbers: [String]?`); the badge is computed on the fly in `BookmarksView` as `chapterNumbers` minus `HistoryStore.readChapterNumbers(forManga:)`, so it's always correct without any imperative decrement bookkeeping. `MangaDetailView` gains a selection mode that swaps chapter rows' tap target from "open reader" to "toggle checkbox" and drives new batch `HistoryStore.markRead(manga:chapters:)` / `markUnread(manga:chapters:)` methods.

**Tech Stack:** Swift, SwiftUI, XCTest — no third-party dependencies.

## Global Constraints

- iOS 17.5 deployment target; no `#available(iOS 18, *)` APIs unless guarded (this plan uses none).
- No third-party dependencies or package manager — pure SwiftUI + Foundation only.
- `Models/` and `Services/` are Xcode synchronized groups — new files there are picked up automatically. `Views/` is **not** synchronized — this plan adds no new files anywhere, only edits existing ones, so no `project.pbxproj` changes are needed.
- Build: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Test: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test`
- Single test: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:Manga-ReaderTests/Manga_ReaderTests/<testMethod>`
- Spec: `docs/superpowers/specs/2026-07-14-unread-badge-multiselect-design.md`

---

## Task 1: Live unread-count badge (`LibraryItem` model + `LibraryStore.refresh` + call sites)

**Files:**
- Modify: `Manga-Reader/Services/LibraryStore.swift:12-19` (struct), `:47-96` (refresh/markCaughtUp)
- Modify: `Manga-Reader/Views/BookmarksView.swift:29-40` (grid item), `:47`, `:54` (refresh call sites)
- Modify: `Manga-Reader/Views/ReaderView.swift:59` (env object), `:95-104` (loadAndBegin)
- Test: `Manga-ReaderTests/Manga_ReaderTests.swift:245-252` (update), new tests appended near there

**Interfaces:**
- Produces: `LibraryItem.chapterNumbers: [String]?`, `LibraryItem.unreadCount(readNumbers: Set<String>) -> Int`, `LibraryStore.refresh() async` (no `history:` parameter).
- Consumes: `MangaDexAPI.fetchChapters(mangaId: String) async throws -> [Chapter]` (existing, `Manga-Reader/Models/MangaDexAPI.swift:446`), `HistoryStore.readChapterNumbers(forManga:) -> Set<String>` (existing).

- [ ] **Step 1: Write the failing tests for `LibraryItem.unreadCount`**

Add to `Manga-ReaderTests/Manga_ReaderTests.swift`, right after the `// MARK: - Library updates` comment (currently line 144, just before `testNewChapterCountCountsNewerDistinct` — leave that existing test in place for now, Task 2 removes it):

```swift
    func testUnreadCountNilChapterNumbersIsZero() {
        let item = LibraryItem(id: "m1", title: "T", coverURL: nil, chapterNumbers: nil)
        XCTAssertEqual(item.unreadCount(readNumbers: []), 0)
    }

    func testUnreadCountWithNoneReadCountsAll() {
        let item = LibraryItem(id: "m1", title: "T", coverURL: nil, chapterNumbers: ["1", "2", "3"])
        XCTAssertEqual(item.unreadCount(readNumbers: []), 3)
    }

    func testUnreadCountExcludesReadNumbers() {
        let item = LibraryItem(id: "m1", title: "T", coverURL: nil, chapterNumbers: ["1", "2", "3"])
        XCTAssertEqual(item.unreadCount(readNumbers: ["2"]), 2)
    }

    func testUnreadCountAllReadIsZero() {
        let item = LibraryItem(id: "m1", title: "T", coverURL: nil, chapterNumbers: ["1", "2"])
        XCTAssertEqual(item.unreadCount(readNumbers: ["1", "2"]), 0)
    }
```

Also replace the now-stale legacy-decode assertions in the same file (currently lines 245-252):

```swift
    func testLibraryItemDecodesLegacyJSON() throws {
        // JSON saved before chapterNumbers existed (pre-migration installs).
        let legacy = #"{"id":"m1","title":"Old","coverURL":null}"#.data(using: .utf8)!
        let item = try JSONDecoder().decode(LibraryItem.self, from: legacy)
        XCTAssertEqual(item.id, "m1")
        XCTAssertNil(item.chapterNumbers)
        XCTAssertEqual(item.unreadCount(readNumbers: []), 0)
    }
```

- [ ] **Step 2: Run the new tests to verify they fail to compile**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:Manga-ReaderTests/Manga_ReaderTests/testUnreadCountWithNoneReadCountsAll`
Expected: FAIL — `LibraryItem` has no member `chapterNumbers` / no `unreadCount` method yet.

- [ ] **Step 3: Rewrite `LibraryItem` and add `unreadCount`**

In `Manga-Reader/Services/LibraryStore.swift`, replace lines 12-19:

```swift
/// A saved manga snapshot. Kept small and Codable for on-device persistence.
struct LibraryItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let coverURL: URL?
    var chapterNumbers: [String]? = nil   // deduped chapter numbers from last refresh; nil = never refreshed
}

extension LibraryItem {
    /// Chapters not yet read, given this manga's read chapter numbers from `HistoryStore`.
    /// Returns 0 until the first successful refresh populates `chapterNumbers`.
    func unreadCount(readNumbers: Set<String>) -> Int {
        guard let chapterNumbers else { return 0 }
        return chapterNumbers.filter { !readNumbers.contains($0) }.count
    }
}
```

- [ ] **Step 4: Rewrite `refresh()` to fetch full chapter lists and drop `markCaughtUp`**

In `Manga-Reader/Services/LibraryStore.swift`, replace the `refresh(history:)` method and `markCaughtUp(_:)` method (originally lines 47-96) with:

```swift
    /// Refresh every saved manga's full chapter-number list concurrently. Best-effort:
    /// per-item failures leave that item's existing `chapterNumbers` untouched.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let current = items
        let results: [(String, [String])] = await withTaskGroup(
            of: (String, [String])?.self
        ) { group in
            for item in current {
                group.addTask {
                    guard let chapters = try? await MangaDexAPI.fetchChapters(mangaId: item.id) else { return nil }
                    return (item.id, chapters.map(\.number))
                }
            }
            var out: [(String, [String])] = []
            for await result in group { if let result { out.append(result) } }
            return out
        }

        var updated = items
        for (id, numbers) in results {
            guard let idx = updated.firstIndex(where: { $0.id == id }) else { continue }
            updated[idx].chapterNumbers = numbers
        }
        items = updated
        save()
    }
```

The existing `toggle(_:)` method's call site (`LibraryItem(id: manga.id, title: manga.title, coverURL: manga.coverURL)`) still compiles unchanged — `chapterNumbers` has a default value of `nil`, so omitting it is fine.

- [ ] **Step 5: Fix `BookmarksView` call sites and badge display**

In `Manga-Reader/Views/BookmarksView.swift`, replace the `ForEach` body (originally lines 29-40):

```swift
                            ForEach(library.items) { item in
                                let unread = item.unreadCount(readNumbers: history.readChapterNumbers(forManga: item.id))
                                NavigationLink(destination: MangaDetailView(manga: item.asManga)) {
                                    MangaCoverCard(
                                        title: item.title,
                                        coverURL: item.coverURL,
                                        stamp: unread > 0 ? "UNREAD · \(unread)" : nil,
                                        stampTinted: true,
                                        fill: true
                                    )
                                }
                                .buttonStyle(.plain)
                            }
```

And update both refresh call sites (originally lines 47 and 54) from `library.refresh(history: history)` to `library.refresh()`:

```swift
                    .refreshable { await library.refresh() }
```

```swift
                        Task { await library.refresh() }
```

- [ ] **Step 6: Remove the now-obsolete caught-up call site in `ReaderView`**

In `Manga-Reader/Views/ReaderView.swift`, delete the `@EnvironmentObject private var library: LibraryStore` line (originally line 59).

Replace `loadAndBegin()` (originally lines 95-104):

```swift
    /// Fetch the chapter's pages and, on success, seed reading progress. Also
    /// invoked by the retry button after a failed load.
    private func loadAndBegin() async {
        await load()
        guard !pages.isEmpty else { return }   // load failed → don't record progress
        let start = min(max(initialPage, 0), pages.count - 1)
        currentPage = start
        advanceProgress(to: start)
    }
```

- [ ] **Step 7: Run the full unit test target**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:Manga-ReaderTests`
Expected: PASS for all `Manga_ReaderTests` methods except the three `testNewChapterCount*` tests, which still reference the (still-present, untouched-until-Task-2) `RecentChapter`/`newChapterCount` symbols and continue to pass unchanged at this point.

- [ ] **Step 8: Build the app target to confirm no other call sites broke**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 9: Commit**

```bash
git add Manga-Reader/Services/LibraryStore.swift Manga-Reader/Views/BookmarksView.swift Manga-Reader/Views/ReaderView.swift Manga-ReaderTests/Manga_ReaderTests.swift
git commit -m "Replace new-since-baseline badge with live unread chapter count"
```

---

## Task 2: Remove dead "new since baseline" code

**Files:**
- Modify: `Manga-Reader/Models/MangaDexAPI.swift:128-150` (`RecentChapter`, `newChapterCount`), `:473-486` (`recentChapters`)
- Test: `Manga-ReaderTests/Manga_ReaderTests.swift:146-174` (delete three tests)

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new (pure deletion). Confirms Task 1 left no remaining references to the deleted symbols.

- [ ] **Step 1: Delete the three obsolete tests**

In `Manga-ReaderTests/Manga_ReaderTests.swift`, delete `testNewChapterCountCountsNewerDistinct`, `testNewChapterCountNilBaselineCountsAllDistinct`, and `testNewChapterCountExcludesReadNumbers` (originally lines 146-174, everything between the `// MARK: - Library updates` comment and `testReadChapterNumbersForManga`). The `// MARK: - Library updates` comment can stay (it now precedes `testReadChapterNumbersForManga`).

- [ ] **Step 2: Delete `RecentChapter` and the free `newChapterCount` function**

In `Manga-Reader/Models/MangaDexAPI.swift`, delete lines 128-150 (the `RecentChapter` struct and the `newChapterCount(_:since:excludingNumbers:)` function, including their doc comments), leaving the `ChapterAttributes` struct directly followed by the `// MARK: - Reading (at-home) payloads` section.

- [ ] **Step 3: Delete `MangaDexAPI.recentChapters(mangaId:)`**

In `Manga-Reader/Models/MangaDexAPI.swift`, delete the `recentChapters(mangaId:)` static method (originally lines 473-486, the doc comment plus function body) from the `MangaDexAPI` struct.

- [ ] **Step 4: Run the full test suite**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:Manga-ReaderTests`
Expected: PASS — no test references the deleted symbols anymore.

- [ ] **Step 5: Build**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Manga-Reader/Models/MangaDexAPI.swift Manga-ReaderTests/Manga_ReaderTests.swift
git commit -m "Remove dead new-since-baseline chapter tracking code"
```

---

## Task 3: Batch mark-read / mark-unread API on `HistoryStore`

**Files:**
- Modify: `Manga-Reader/Services/HistoryStore.swift:117-123` (insert after `toggleRead`, before `delete`)
- Test: `Manga-ReaderTests/Manga_ReaderTests.swift` (append near existing read/unread tests, originally ending at line 233 with `testToggleReadRoundTrips`)

**Interfaces:**
- Consumes: `Manga`, `Chapter` (existing types), `HistoryStore.readMarks: [ReadMark]`, `HistoryStore.entries: [ReadingEntry]`, `HistoryStore.save()` (existing private method), `HistoryStore.isRead(chapterId:)`, `HistoryStore.readChapterNumbers(forManga:)` (existing).
- Produces: `HistoryStore.markRead(manga: Manga, chapters: [Chapter])`, `HistoryStore.markUnread(manga: Manga, chapters: [Chapter])`.

- [ ] **Step 1: Write the failing tests**

Append to `Manga-ReaderTests/Manga_ReaderTests.swift`, after `testToggleReadRoundTrips` (originally ending at line 233) and before `testReadMarksPersistAcrossReload`:

```swift
    @MainActor func testMarkReadBatchMarksAllGivenChapters() throws {
        let store = makeHistoryStore()
        let chapters = [Chapter(id: "c1", number: "1", title: nil), Chapter(id: "c2", number: "2", title: nil)]
        store.markRead(manga: sampleManga("m"), chapters: chapters)
        XCTAssertTrue(store.isRead(chapterId: "c1"))
        XCTAssertTrue(store.isRead(chapterId: "c2"))
        XCTAssertEqual(store.readChapterNumbers(forManga: "m"), ["1", "2"])
    }

    @MainActor func testMarkReadBatchIsIdempotent() throws {
        let store = makeHistoryStore()
        let chapter = Chapter(id: "c1", number: "1", title: nil)
        store.markRead(manga: sampleManga("m"), chapters: [chapter])
        store.markRead(manga: sampleManga("m"), chapters: [chapter])
        XCTAssertEqual(store.readMarks.count, 1)
    }

    @MainActor func testMarkUnreadBatchClearsOnlyGivenChapters() throws {
        let store = makeHistoryStore()
        let manga = sampleManga("m")
        let c1 = Chapter(id: "c1", number: "1", title: nil)
        let c2 = Chapter(id: "c2", number: "2", title: nil)
        let c3 = Chapter(id: "c3", number: "3", title: nil)
        store.record(manga: manga, chapter: c1, page: 2, pageCount: 5)  // opened
        store.markRead(manga: manga, chapter: c2)                       // manually marked
        store.markRead(manga: manga, chapter: c3)                       // manually marked, untouched below

        store.markUnread(manga: manga, chapters: [c1, c2])
        XCTAssertFalse(store.isRead(chapterId: "c1"))
        XCTAssertFalse(store.isRead(chapterId: "c2"))
        XCTAssertTrue(store.isRead(chapterId: "c3"))                    // not in the batch, stays read
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.readChapterNumbers(forManga: "m"), ["3"])
    }
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMarkReadBatchMarksAllGivenChapters`
Expected: FAIL — `HistoryStore` has no member `markRead(manga:chapters:)`.

- [ ] **Step 3: Implement the batch methods**

In `Manga-Reader/Services/HistoryStore.swift`, insert after `toggleRead(manga:chapter:)` (originally lines 117-123) and before `delete(_:)` (originally line 125):

```swift
    /// Mark multiple chapters read in one save. Skips chapters already marked
    /// (mirrors the single-chapter `markRead`'s idempotency).
    func markRead(manga: Manga, chapters: [Chapter]) {
        let existing = Set(readMarks.map(\.chapterId))
        for chapter in chapters where !existing.contains(chapter.id) {
            readMarks.append(ReadMark(mangaId: manga.id, chapterId: chapter.id,
                                      chapterNumber: chapter.number))
        }
        save()
    }

    /// Mark multiple chapters unread in one save: drops both manual marks and
    /// any history entries for exactly the given chapters, leaving others untouched.
    func markUnread(manga: Manga, chapters: [Chapter]) {
        let ids = Set(chapters.map(\.id))
        readMarks.removeAll { ids.contains($0.chapterId) }
        entries.removeAll { ids.contains($0.chapterId) }
        save()
    }
```

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMarkReadBatchMarksAllGivenChapters,Manga-ReaderTests/Manga_ReaderTests/testMarkReadBatchIsIdempotent,Manga-ReaderTests/Manga_ReaderTests/testMarkUnreadBatchClearsOnlyGivenChapters`
Expected: PASS

- [ ] **Step 5: Run the full unit test target**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:Manga-ReaderTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Manga-Reader/Services/HistoryStore.swift Manga-ReaderTests/Manga_ReaderTests.swift
git commit -m "Add batch mark-read/unread API to HistoryStore"
```

---

## Task 4: Chapter list multiselect in `MangaDetailView`

**Files:**
- Modify: `Manga-Reader/Views/MangaDetailView.swift:14` (new `@State`), `:225-277` (`chapters` section), `:279-316` (`chapterRow`), `:21-36` (`body`, to attach the selection toolbar)

**Interfaces:**
- Consumes: `HistoryStore.markRead(manga: Manga, chapters: [Chapter])`, `HistoryStore.markUnread(manga: Manga, chapters: [Chapter])` (from Task 3), `sortChapters(_:descending:)` (existing free function), `Chapter` (existing).
- Produces: nothing consumed by later tasks — this is the last functional task.

- [ ] **Step 1: Add selection state**

In `Manga-Reader/Views/MangaDetailView.swift`, after `@State private var chaptersDescending = true` (originally line 14):

```swift
    @State private var isSelecting = false
    @State private var selectedChapterIDs: Set<String> = []
```

- [ ] **Step 2: Rewrite the Chapters header to add Select/Cancel**

Replace the `chapters` computed property's header `HStack` (originally lines 226-243, the block from `HStack {` through its closing `.padding(.trailing, Gutter.page)`):

```swift
            HStack {
                InkSectionHeader("Chapters", eyebrow: "\(vm.chapters.count) available")
                Spacer()
                if isSelecting {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            isSelecting = false
                            selectedChapterIDs.removeAll()
                        }
                    } label: {
                        Text("CANCEL")
                            .font(.inkMono(11, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(Ink.seal)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 16) {
                        if !vm.chapters.isEmpty {
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { isSelecting = true }
                            } label: {
                                Text("SELECT")
                                    .font(.inkMono(11, weight: .semibold))
                                    .tracking(0.5)
                                    .foregroundStyle(Ink.seal)
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { chaptersDescending.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.arrow.down")
                                Text(chaptersDescending ? "NEWEST" : "OLDEST")
                            }
                            .font(.inkMono(11, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(Ink.seal)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.trailing, Gutter.page)
```

- [ ] **Step 3: Swap the chapter row's tap target based on `isSelecting`**

Replace the `ForEach` inside the `VStack(spacing: 0)` (originally lines 255-273):

```swift
                    ForEach(sortChapters(vm.chapters, descending: chaptersDescending)) { chapter in
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
```

- [ ] **Step 4: Add a selection checkbox to `chapterRow`**

Replace `chapterRow(_:)` (originally lines 279-316) with a version taking a `selected` flag and showing a leading checkbox while selecting, hiding the trailing chevron:

```swift
    private func chapterRow(_ chapter: Chapter, selected: Bool) -> some View {
        // Show a resume marker only while a chapter is genuinely mid-read; that
        // chapter stays highlighted (your current spot). Finished/opened
        // chapters that aren't mid-read are dimmed.
        let progress = history.entry(forChapter: chapter.id)
        let inProgress = progress.map { $0.pageCount > 0 && $0.page < $0.pageCount - 1 } ?? false
        let dimmed = history.isRead(chapterId: chapter.id) && !inProgress

        return HStack(spacing: 14) {
            if isSelecting {
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
                }
            }

            Spacer(minLength: 8)

            if !isSelecting {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.tertiary)
            }
        }
        .padding(.horizontal, Gutter.page)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
```

- [ ] **Step 5: Add selection helpers and the bottom selection toolbar**

Add these private members to `MangaDetailView` (place them right after the `chapters` computed property, before `chapterRow`):

```swift
    private var allChaptersSelected: Bool {
        !vm.chapters.isEmpty && selectedChapterIDs.count == vm.chapters.count
    }

    private func toggleSelection(_ id: String) {
        if selectedChapterIDs.contains(id) {
            selectedChapterIDs.remove(id)
        } else {
            selectedChapterIDs.insert(id)
        }
    }

    private func markSelected(read: Bool) {
        let chapters = vm.chapters.filter { selectedChapterIDs.contains($0.id) }
        if read {
            history.markRead(manga: manga, chapters: chapters)
        } else {
            history.markUnread(manga: manga, chapters: chapters)
        }
        withAnimation(.snappy(duration: 0.2)) {
            isSelecting = false
            selectedChapterIDs.removeAll()
        }
    }
```

Then attach the bottom toolbar to `body`. Replace the `.onAppear { vm.load() }` line at the end of `body` (originally line 35) so the modifier chain becomes:

```swift
        .background(Ink.background)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.load() }
        .toolbar {
            if isSelecting {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(allChaptersSelected ? "Deselect All" : "Select All") {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedChapterIDs = allChaptersSelected ? [] : Set(vm.chapters.map(\.id))
                        }
                    }
                    Spacer()
                    Button("Mark Unread") { markSelected(read: false) }
                        .disabled(selectedChapterIDs.isEmpty)
                    Button("Mark Read") { markSelected(read: true) }
                        .disabled(selectedChapterIDs.isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
```

- [ ] **Step 6: Build**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Run the full unit test target**

Run: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:Manga-ReaderTests`
Expected: PASS (no unit tests target `MangaDetailView` directly, so this confirms no regressions elsewhere)

- [ ] **Step 8: Commit**

```bash
git add Manga-Reader/Views/MangaDetailView.swift
git commit -m "Add chapter list multiselect with select-all mark read/unread"
```

---

## Task 5: Manual verification in simulator

**Files:** none (verification only)

- [ ] **Step 1: Boot the simulator and launch the app**

```bash
xcrun simctl boot "iPhone 17" 2>/dev/null || true
xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' build
xcrun simctl install "iPhone 17" $(find ~/Library/Developer/Xcode/DerivedData -name "Manga-Reader.app" -path "*Debug-iphonesimulator*" | head -1)
xcrun simctl launch "iPhone 17" $(defaults read $(find ~/Library/Developer/Xcode/DerivedData -name "Info.plist" -path "*Manga-Reader.app*" | head -1) CFBundleIdentifier)
```

- [ ] **Step 2: Verify the unread badge**

In the running app: Search tab → search any manga → open its detail → "Add to Library". Go to the Library tab and pull to refresh. Confirm the card shows an `UNREAD · N` stamp where N equals the manga's total chapter count (nothing has been read yet). Capture a screenshot:

```bash
xcrun simctl io "iPhone 17" screenshot /private/tmp/claude-501/-Users-eliasmagdaleno-xcode-Manga-Reader/*/scratchpad/library-badge.png
```

- [ ] **Step 3: Verify the badge decrements on read**

Open the manga's detail screen, open its first chapter in the reader (any page), go back, return to the Library tab, pull to refresh if needed. Confirm the `UNREAD · N` count dropped by exactly 1 (not to 0) — this is the core behavior change from the old "caught up" reset.

- [ ] **Step 4: Verify multiselect mark-read and select-all**

On the manga detail screen's Chapters section, tap "SELECT". Confirm each row grows a leading checkbox and tapping a row toggles it (no longer opens the reader). Select two chapters and tap "Mark Read" in the bottom bar. Confirm those rows dim (matching the existing read-row styling) and selection mode exits. Re-enter selection mode, tap "Select All", tap "Mark Read". Confirm every row is dimmed. Return to the Library tab and pull to refresh — confirm the `UNREAD · N` badge is now gone for that manga (all chapters read).

- [ ] **Step 5: Verify mark-unread via multiselect**

Re-enter selection mode, select one already-read chapter, tap "Mark Unread". Confirm that row is no longer dimmed. Confirm the per-row context menu (long-press when not selecting) still independently offers "Mark as unread"/"Mark as read" and works as before.

- [ ] **Step 6: Report results**

Summarize pass/fail for each of Steps 2-5 back to the user before considering Task 5 complete. If any step fails, treat it as a bug against the relevant earlier task — do not silently patch around it without noting the discrepancy from this plan.
