# Resume Reading · History Tab · Library Updates — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add resume-reading (Continue button), a chronological History tab, and library refresh with new-chapter badges — plus newest-first chapter ordering and a right-to-left reading default — to the MangaCarta SwiftUI app.

**Architecture:** MVVM over the stateless `MangaDexAPI`. A new `@MainActor` `HistoryStore` (UserDefaults-backed, injected app-wide) is the reading-progress spine feeding both the Continue button and the History tab; `ReaderView` is widened to report progress. `LibraryStore` is extended with per-item update tracking and a concurrent `refresh()`. Pure logic (chapter ordering, resume-target selection, new-chapter counting) is extracted into free functions in `Models/` for unit testing.

**Tech Stack:** Swift 5 / SwiftUI, iOS 17.5 (some `#available(iOS 18.0)` branches), Foundation `URLSession`, XCTest, Xcode project (no SPM/CocoaPods).

## Global Constraints

- Deployment target iOS 17.5; keep both `#available(iOS 18.0, *)` and pre-18 `TabView` branches in `ContentView` in sync.
- No third-party dependencies — pure SwiftUI + Foundation only.
- `Models/`, `Services/`, `Components/` are Xcode 16 **synchronized root groups** — files dropped in compile automatically. **`Views/` and `MangaCartaTests/` are NOT synchronized** — new files there need `project.pbxproj` edits (4 places each). Tests in this plan are appended to the existing `MangaCartaTests/MangaCartaTests.swift` to avoid pbxproj churn.
- Persisted-model rule: any new field on `LibraryItem` (already saved in UserDefaults) MUST be an `Optional var` — `LibraryStore.load()` uses `try?` decode, so a non-optional new field silently wipes the saved library.
- Follow the existing "Ink & Seal" tokens (`Ink.*`, `Gutter.*`, `.inkMono`, `.inkDisplay`, `InkStamp`, `InkSectionHeader`, `InkEmptyState`, `InkNotice`).
- Test/build simulator: use an available device from `xcrun simctl list devices available` (examples below use `iPhone 16`; substitute if absent).

---

### Task 1: `HistoryStore` + `ReadingEntry`

**Files:**
- Create: `MangaCarta/Services/HistoryStore.swift` (synchronized group — auto-compiles)
- Test: `MangaCartaTests/MangaCartaTests.swift` (append methods)

**Interfaces:**
- Consumes: `Manga` (id/title/coverURL), `Chapter` (id/number) from `Models/MangaDexAPI.swift`.
- Produces:
  - `struct ReadingEntry: Codable, Identifiable, Hashable { let id: UUID; let mangaId: String; let mangaTitle: String; let coverURL: URL?; let chapterId: String; let chapterNumber: String; var page: Int; var pageCount: Int; var updatedAt: Date }`
  - `@MainActor final class HistoryStore: ObservableObject` with `@Published private(set) var entries: [ReadingEntry]`, `init(defaults: UserDefaults = .standard)`, `func record(manga: Manga, chapter: Chapter, page: Int, pageCount: Int)`, `func latestEntry(forManga id: String) -> ReadingEntry?`, `func delete(_ entry: ReadingEntry)`, `func clear()`.

- [ ] **Step 1: Write the failing tests** — append to `MangaCartaTests/MangaCartaTests.swift` (inside the class):

```swift
// MARK: - HistoryStore

@MainActor
private func makeHistoryStore() -> HistoryStore {
    let suite = UserDefaults(suiteName: "test.history.\(UUID().uuidString)")!
    return HistoryStore(defaults: suite)
}

private func sampleManga(_ id: String = "m1") -> Manga {
    Manga(id: id, title: "Title \(id)", description: "", status: "ongoing", year: nil, coverURL: nil)
}

@MainActor func testRecordPrependsNewEntry() throws {
    let store = makeHistoryStore()
    store.record(manga: sampleManga(), chapter: Chapter(id: "c1", number: "1", title: nil), page: 2, pageCount: 10)
    store.record(manga: sampleManga(), chapter: Chapter(id: "c2", number: "2", title: nil), page: 0, pageCount: 8)
    XCTAssertEqual(store.entries.count, 2)
    XCTAssertEqual(store.entries.first?.chapterId, "c2") // most-recent-first
}

@MainActor func testRecordSameChapterUpdatesInPlace() throws {
    let store = makeHistoryStore()
    store.record(manga: sampleManga(), chapter: Chapter(id: "c1", number: "1", title: nil), page: 2, pageCount: 10)
    store.record(manga: sampleManga(), chapter: Chapter(id: "c1", number: "1", title: nil), page: 5, pageCount: 10)
    XCTAssertEqual(store.entries.count, 1)
    XCTAssertEqual(store.entries.first?.page, 5)
}

@MainActor func testLatestEntryForManga() throws {
    let store = makeHistoryStore()
    store.record(manga: sampleManga("a"), chapter: Chapter(id: "c1", number: "1", title: nil), page: 1, pageCount: 10)
    store.record(manga: sampleManga("b"), chapter: Chapter(id: "c2", number: "1", title: nil), page: 1, pageCount: 10)
    XCTAssertEqual(store.latestEntry(forManga: "a")?.chapterId, "c1")
    XCTAssertNil(store.latestEntry(forManga: "zzz"))
}

@MainActor func testDeleteAndClear() throws {
    let store = makeHistoryStore()
    store.record(manga: sampleManga(), chapter: Chapter(id: "c1", number: "1", title: nil), page: 1, pageCount: 10)
    let entry = store.entries[0]
    store.delete(entry)
    XCTAssertTrue(store.entries.isEmpty)
    store.record(manga: sampleManga(), chapter: Chapter(id: "c1", number: "1", title: nil), page: 1, pageCount: 10)
    store.clear()
    XCTAssertTrue(store.entries.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:MangaCartaTests/MangaCartaTests/testRecordPrependsNewEntry`
Expected: FAIL — compile error, `cannot find 'HistoryStore' in scope`.

- [ ] **Step 3: Create `MangaCarta/Services/HistoryStore.swift`**

```swift
//
//  HistoryStore.swift
//  MangaCarta
//
//  Chronological reading history + per-manga resume position. Backed by
//  UserDefaults. Powers both the detail "Continue" button and the History tab.
//

import SwiftUI

/// One logged reading position. A continuous session updates a single entry in
/// place; re-opening a chapter later creates a new entry.
struct ReadingEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let mangaId: String
    let mangaTitle: String
    let coverURL: URL?
    let chapterId: String
    let chapterNumber: String
    var page: Int
    var pageCount: Int
    var updatedAt: Date
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [ReadingEntry] = []

    private let key = "history.entries"
    private let defaults: UserDefaults
    private let cap = 500

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Record progress. If the newest entry is the same manga + chapter, update
    /// it in place and float to the front; otherwise prepend a new entry.
    func record(manga: Manga, chapter: Chapter, page: Int, pageCount: Int) {
        if let idx = entries.firstIndex(where: { $0.mangaId == manga.id && $0.chapterId == chapter.id }) {
            var entry = entries.remove(at: idx)
            entry.page = max(entry.page, page)   // furthest page reached
            entry.pageCount = pageCount
            entry.updatedAt = Date()
            entries.insert(entry, at: 0)
        } else {
            entries.insert(
                ReadingEntry(id: UUID(), mangaId: manga.id, mangaTitle: manga.title,
                             coverURL: manga.coverURL, chapterId: chapter.id,
                             chapterNumber: chapter.number, page: page,
                             pageCount: pageCount, updatedAt: Date()),
                at: 0
            )
        }
        if entries.count > cap { entries.removeLast(entries.count - cap) }
        save()
    }

    func latestEntry(forManga id: String) -> ReadingEntry? {
        entries.first { $0.mangaId == id }
    }

    func delete(_ entry: ReadingEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ReadingEntry].self, from: data)
        else { return }
        entries = decoded
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:MangaCartaTests/MangaCartaTests/testRecordPrependsNewEntry -only-testing:MangaCartaTests/MangaCartaTests/testRecordSameChapterUpdatesInPlace -only-testing:MangaCartaTests/MangaCartaTests/testLatestEntryForManga -only-testing:MangaCartaTests/MangaCartaTests/testDeleteAndClear`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add MangaCarta/Services/HistoryStore.swift MangaCartaTests/MangaCartaTests.swift
git commit -m "Add HistoryStore reading-progress spine"
```

---

### Task 2: Chapter-ordering + resume-target helpers

**Files:**
- Create: `MangaCarta/Models/ReadingResume.swift` (synchronized group — auto-compiles)
- Modify: `MangaCarta/Models/MangaDexAPI.swift` — add `Equatable` to `Chapter` (line 151: `struct Chapter: Identifiable {` → `struct Chapter: Identifiable, Equatable {`)
- Test: `MangaCartaTests/MangaCartaTests.swift` (append)

**Interfaces:**
- Consumes: `Chapter` (now `Equatable`), `ReadingEntry` (Task 1).
- Produces (all free functions, no `@MainActor`):
  - `func numericChapterValue(_ number: String) -> Double?`
  - `func sortChapters(_ chapters: [Chapter], descending: Bool) -> [Chapter]`
  - `func nextChapter(after number: String, in ascending: [Chapter]) -> Chapter?`
  - `enum ResumeAction: Equatable { case start(Chapter); case cont(Chapter, page: Int); case next(Chapter); case reread(Chapter, page: Int) }`
  - `func resumeAction(entry: ReadingEntry?, chapters: [Chapter]) -> ResumeAction?`

- [ ] **Step 1: Write the failing tests** — append to `MangaCartaTests.swift`:

```swift
// MARK: - Chapter ordering & resume

private func ch(_ n: String, _ id: String? = nil) -> Chapter {
    Chapter(id: id ?? "id\(n)", number: n, title: nil)
}

func testNumericChapterValue() {
    XCTAssertEqual(numericChapterValue("10.5"), 10.5)
    XCTAssertNil(numericChapterValue("?"))
}

func testSortChaptersNumeric() {
    let input = [ch("2"), ch("10"), ch("1"), ch("10.5"), ch("?")]
    let asc = sortChapters(input, descending: false).map(\.number)
    XCTAssertEqual(asc, ["1", "2", "10", "10.5", "?"])   // unparseable sorts last
    let desc = sortChapters(input, descending: true).map(\.number)
    XCTAssertEqual(desc, ["10.5", "10", "2", "1", "?"])  // unparseable still last
}

func testNextChapter() {
    let asc = [ch("1"), ch("2"), ch("3")]
    XCTAssertEqual(nextChapter(after: "2", in: asc)?.number, "3")
    XCTAssertNil(nextChapter(after: "3", in: asc))
}

func testResumeActionNoHistory() {
    let action = resumeAction(entry: nil, chapters: [ch("2"), ch("1")])
    XCTAssertEqual(action, .start(ch("1")))
}

func testResumeActionMidChapter() {
    let entry = ReadingEntry(id: UUID(), mangaId: "m", mangaTitle: "t", coverURL: nil,
                             chapterId: "id2", chapterNumber: "2", page: 3, pageCount: 10, updatedAt: Date())
    XCTAssertEqual(resumeAction(entry: entry, chapters: [ch("1"), ch("2"), ch("3")]),
                   .cont(ch("2"), page: 3))
}

func testResumeActionFinishedJumpsToNext() {
    let entry = ReadingEntry(id: UUID(), mangaId: "m", mangaTitle: "t", coverURL: nil,
                             chapterId: "id2", chapterNumber: "2", page: 9, pageCount: 10, updatedAt: Date())
    XCTAssertEqual(resumeAction(entry: entry, chapters: [ch("1"), ch("2"), ch("3")]),
                   .next(ch("3")))
}

func testResumeActionFinishedLatestRereads() {
    let entry = ReadingEntry(id: UUID(), mangaId: "m", mangaTitle: "t", coverURL: nil,
                             chapterId: "id3", chapterNumber: "3", page: 9, pageCount: 10, updatedAt: Date())
    XCTAssertEqual(resumeAction(entry: entry, chapters: [ch("1"), ch("2"), ch("3")]),
                   .reread(ch("3"), page: 9))
}
```

- [ ] **Step 2: Run to verify fail**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:MangaCartaTests/MangaCartaTests/testResumeActionNoHistory`
Expected: FAIL — `cannot find 'resumeAction' in scope`.

- [ ] **Step 3a: Make `Chapter` Equatable** in `MangaCarta/Models/MangaDexAPI.swift` (line ~151):

```swift
struct Chapter: Identifiable, Equatable {          // Identifiable so SwiftUI ForEach works directly.
```

- [ ] **Step 3b: Create `MangaCarta/Models/ReadingResume.swift`**

```swift
//
//  ReadingResume.swift
//  MangaCarta
//
//  Pure helpers for numeric chapter ordering and choosing where the "Continue"
//  button should drop the reader. Kept free of UI / persistence so they unit-test
//  cleanly.
//

import Foundation

/// Numeric value of a chapter "number" string ("10.5" -> 10.5). `nil` when the
/// number is unparseable (e.g. "?", oneshot labels).
func numericChapterValue(_ number: String) -> Double? {
    Double(number)
}

/// Sort chapters by numeric value. Unparseable numbers always sort to the end,
/// in both directions. Stable on ties (preserves source order).
func sortChapters(_ chapters: [Chapter], descending: Bool) -> [Chapter] {
    chapters.enumerated().sorted { lhs, rhs in
        switch (numericChapterValue(lhs.element.number), numericChapterValue(rhs.element.number)) {
        case let (l?, r?):
            if l == r { return lhs.offset < rhs.offset }        // stable
            return descending ? l > r : l < r
        case (nil, nil): return lhs.offset < rhs.offset
        case (_?, nil):  return true                            // parseable before unparseable
        case (nil, _?):  return false
        }
    }.map(\.element)
}

/// The chapter immediately after `number` in ascending numeric order.
func nextChapter(after number: String, in ascending: [Chapter]) -> Chapter? {
    guard let value = numericChapterValue(number) else { return nil }
    return sortChapters(ascending, descending: false)
        .first { ($0.number != number) && (numericChapterValue($0.number).map { $0 > value } ?? false) }
}

/// What the detail-screen "Continue" button should do.
enum ResumeAction: Equatable {
    case start(Chapter)             // no history -> first chapter, page 0
    case cont(Chapter, page: Int)   // mid-chapter -> exact page
    case next(Chapter)              // finished a chapter -> next chapter, page 0
    case reread(Chapter, page: Int) // finished the latest chapter -> re-read last page
}

/// Choose the resume action from the latest history entry and the chapter list
/// (any order — sorted ascending internally). `nil` when there are no chapters.
func resumeAction(entry: ReadingEntry?, chapters: [Chapter]) -> ResumeAction? {
    let ascending = sortChapters(chapters, descending: false)
    guard let first = ascending.first else { return nil }
    guard let entry else { return .start(first) }

    // The chapter the entry refers to (fall back to a reconstructed one if it has
    // since disappeared from the list).
    let current = ascending.first { $0.id == entry.chapterId }
        ?? ascending.first { $0.number == entry.chapterNumber }
        ?? Chapter(id: entry.chapterId, number: entry.chapterNumber, title: nil)

    let finished = entry.pageCount > 0 && entry.page >= entry.pageCount - 1
    if !finished { return .cont(current, page: entry.page) }
    if let nxt = nextChapter(after: entry.chapterNumber, in: ascending) { return .next(nxt) }
    return .reread(current, page: entry.page)
}
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:MangaCartaTests/MangaCartaTests/testNumericChapterValue -only-testing:MangaCartaTests/MangaCartaTests/testSortChaptersNumeric -only-testing:MangaCartaTests/MangaCartaTests/testNextChapter -only-testing:MangaCartaTests/MangaCartaTests/testResumeActionNoHistory -only-testing:MangaCartaTests/MangaCartaTests/testResumeActionMidChapter -only-testing:MangaCartaTests/MangaCartaTests/testResumeActionFinishedJumpsToNext -only-testing:MangaCartaTests/MangaCartaTests/testResumeActionFinishedLatestRereads`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add MangaCarta/Models/ReadingResume.swift MangaCarta/Models/MangaDexAPI.swift MangaCartaTests/MangaCartaTests.swift
git commit -m "Add chapter-ordering and resume-target helpers"
```

---

### Task 3: Widen `ReaderView`, track progress, RTL default, inject `HistoryStore`

**Files:**
- Modify: `MangaCarta/Views/ReaderView.swift`
- Modify: `MangaCarta/Views/MangaDetailView.swift:198-200` (existing `ReaderView(chapterId:)` call site)
- Modify: `MangaCarta/MangaCartaApp.swift` (inject `HistoryStore`)

**Interfaces:**
- Consumes: `HistoryStore.record` (Task 1), `Manga`, `Chapter`.
- Produces: `ReaderView(manga: Manga, chapter: Chapter, initialPage: Int = 0)` — the signature every later call site uses. Reads `HistoryStore` from the environment and records furthest-page progress.

- [ ] **Step 1: Update `ReaderView` initializer & state** — in `MangaCarta/Views/ReaderView.swift`, replace the struct's stored `let chapterId: String` and the `@AppStorage` mode default, and add progress state. Replace lines 45-55 region:

```swift
struct ReaderView: View {
    let manga: Manga
    let chapter: Chapter
    let initialPage: Int

    init(manga: Manga, chapter: Chapter, initialPage: Int = 0) {
        self.manga = manga
        self.chapter = chapter
        self.initialPage = initialPage
    }

    @AppStorage("readingMode") private var mode: ReadingMode = .rightToLeft
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var history: HistoryStore

    @State private var pages: [URL] = []
    @State private var currentPage = 0
    @State private var furthestPage = 0
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showChrome = false
```

- [ ] **Step 2: Record progress + seek** — in `ReaderView`, add these helpers (anywhere in the struct, e.g. after `toggleChrome()`):

```swift
    private func advanceProgress(to index: Int) {
        furthestPage = max(furthestPage, index)
        guard !pages.isEmpty else { return }
        history.record(manga: manga, chapter: chapter, page: furthestPage, pageCount: pages.count)
    }
```

- [ ] **Step 3: Seek on load & track paged changes** — update the paged reader and the `load()`/`task`:

In `pagedReader`, add an `.onChange` to the `TabView` (after `.ignoresSafeArea()`):

```swift
        .onChange(of: currentPage) { _, newValue in advanceProgress(to: newValue) }
```

Replace the `.task { await load() }` modifier (line ~79) with:

```swift
        .task {
            await load()
            let start = min(max(initialPage, 0), max(pages.count - 1, 0))
            currentPage = start
            furthestPage = start
            advanceProgress(to: start)
        }
```

- [ ] **Step 4: Track & seek in webtoon mode** — wrap the vertical reader in a `ScrollViewReader`, give pages index ids, seek, and track via `onAppear`. Replace `verticalReader` (lines ~113-125) and `verticalPage` header:

```swift
    private var verticalReader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, url in
                        verticalPage(url: url, index: index)
                            .id(index)
                            .onAppear { advanceProgress(to: index) }
                    }
                    if !pages.isEmpty && !isLoading { endMark }
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: toggleChrome)
            }
            .ignoresSafeArea()
            .onChange(of: pages.count) { _, count in
                guard count > 0, initialPage > 0 else { return }
                proxy.scrollTo(min(initialPage, count - 1), anchor: .top)
            }
        }
    }
```

(`verticalPage(url:index:)` body is unchanged.)

- [ ] **Step 5: Update the detail-screen call site** — in `MangaCarta/Views/MangaDetailView.swift` (chapters section, line ~198-200):

```swift
                        NavigationLink {
                            ReaderView(manga: manga, chapter: chapter)
                        } label: {
```

- [ ] **Step 6: Inject `HistoryStore`** — in `MangaCarta/MangaCartaApp.swift`, add the store and inject it:

```swift
    @StateObject private var library = LibraryStore()
    @StateObject private var history = HistoryStore()
```

```swift
            ContentView()
                .tint(Ink.seal)
                .environmentObject(library)
                .environmentObject(history)
                .preferredColorScheme(appearance.colorScheme)
```

- [ ] **Step 7: Build to verify it compiles**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Manual verification**

Launch the app (open a manga from Home → open a chapter). Read a few pages, back out, reopen the same chapter — it should resume near where you left off. Confirm swipe direction defaults to right-to-left (swipe right advances) on a fresh install / after resetting the `readingMode` default. Confirm webtoon mode still scrolls.

- [ ] **Step 9: Commit**

```bash
git add MangaCarta/Views/ReaderView.swift MangaCarta/Views/MangaDetailView.swift MangaCarta/MangaCartaApp.swift
git commit -m "Widen ReaderView to report progress; default RTL; inject HistoryStore"
```

---

### Task 4: Resume button + chapter-order toggle in `MangaDetailView`

**Files:**
- Modify: `MangaCarta/Views/MangaDetailView.swift`

**Interfaces:**
- Consumes: `resumeAction`, `sortChapters`, `ResumeAction` (Task 2); `HistoryStore.latestEntry` (Task 1); `ReaderView(manga:chapter:initialPage:)` (Task 3).
- Produces: (UI only)

- [ ] **Step 1: Add environment + sort state** — near the top of `MangaDetailView` (after `@EnvironmentObject private var library`):

```swift
    @EnvironmentObject private var history: HistoryStore
    @State private var chaptersDescending = true
```

- [ ] **Step 2: Add the resume button** — insert `resumeButton` into the `body` VStack, directly after `libraryButton` (line ~23):

```swift
                hero
                libraryButton
                resumeButton
```

Add the computed view (place after `libraryButton`'s definition):

```swift
    // MARK: Resume / Continue reading

    @ViewBuilder private var resumeButton: some View {
        if let action = resumeAction(entry: history.latestEntry(forManga: manga.id),
                                     chapters: vm.chapters) {
            NavigationLink {
                ReaderView(manga: manga, chapter: action.chapter, initialPage: action.startPage)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "book.pages")
                    Text(action.label)
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(Ink.seal)
                .background(RoundedRectangle(cornerRadius: 12).fill(Ink.sealSoft))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Ink.seal, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Gutter.page)
        } else if vm.isLoading {
            // Chapters still loading — show a disabled placeholder so layout is stable.
            HStack(spacing: 8) {
                ProgressView().tint(Ink.seal)
                Text("Start Reading")
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Ink.tertiary)
            .background(RoundedRectangle(cornerRadius: 12).fill(Ink.sealSoft.opacity(0.5)))
            .padding(.horizontal, Gutter.page)
        }
    }
```

- [ ] **Step 3: Add `ResumeAction` UI accessors** — at the bottom of `MangaDetailView.swift` (file scope, outside the struct):

```swift
private extension ResumeAction {
    var chapter: Chapter {
        switch self {
        case .start(let c), .next(let c), .cont(let c, _), .reread(let c, _): return c
        }
    }
    var startPage: Int {
        switch self {
        case .start, .next: return 0
        case .cont(_, let p), .reread(_, let p): return p
        }
    }
    var label: String {
        switch self {
        case .start:                 return "Start Reading"
        case .cont(let c, let p):    return "Continue Ch \(c.number) · p.\(p + 1)"
        case .next(let c):           return "Start Ch \(c.number)"
        case .reread(let c, _):      return "Read Again · Ch \(c.number)"
        }
    }
}
```

- [ ] **Step 4: Chapter-order toggle** — in the `chapters` computed view, replace the `InkSectionHeader` line and the `ForEach(vm.chapters)` with a sorted list and a toggle. Replace the header + loop region (lines ~184-207):

```swift
            HStack {
                InkSectionHeader("Chapters", eyebrow: "\(vm.chapters.count) available")
                Spacer()
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
                .padding(.trailing, Gutter.page)
            }
```

And change the loop to sort:

```swift
                VStack(spacing: 0) {
                    ForEach(sortChapters(vm.chapters, descending: chaptersDescending)) { chapter in
                        NavigationLink {
                            ReaderView(manga: manga, chapter: chapter)
                        } label: {
                            chapterRow(chapter)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Ink.hairline)
                            .padding(.leading, Gutter.page)
                    }
                }
```

- [ ] **Step 5: Build**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual verification**

Open a manga: chapters list shows newest at top; tap the NEWEST/OLDEST toggle to flip order. With no reading history the button reads "Start Reading". Read part of a chapter, return to detail → "Continue Ch X · p.Y". Finish a chapter's last page, return → "Start Ch (next)".

- [ ] **Step 7: Commit**

```bash
git add MangaCarta/Views/MangaDetailView.swift
git commit -m "Add resume button and chapter-order toggle to detail view"
```

---

### Task 5: History tab

**Files:**
- Create: `MangaCarta/Views/HistoryView.swift`
- Modify: `MangaCarta.xcodeproj/project.pbxproj` (4 entries)
- Modify: `MangaCarta/ContentView.swift` (both `TabView` branches + `Tabs` enum)

**Interfaces:**
- Consumes: `HistoryStore.entries/delete/clear` (Task 1), `ReadingEntry`, `ReaderView(manga:chapter:initialPage:)` (Task 3), `MangaCoverCard`-style tokens.
- Produces: `struct HistoryView: View`.

- [ ] **Step 1: Create `MangaCarta/Views/HistoryView.swift`**

```swift
//
//  HistoryView.swift
//  MangaCarta
//
//  The "History" tab: a reverse-chronological log of chapters read, grouped by
//  day. Tapping a row reopens that exact chapter and page.
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    InkEmptyState(
                        symbol: "clock.arrow.circlepath",
                        title: "No reading history",
                        message: "Chapters you read will appear here so you can pick up where you left off."
                    )
                } else {
                    List {
                        ForEach(groupedEntries, id: \.key) { group in
                            Section(group.key) {
                                ForEach(group.value) { entry in
                                    row(entry)
                                }
                                .onDelete { offsets in delete(in: group.value, at: offsets) }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Ink.background)
            .navigationTitle("History")
            .toolbar {
                if !history.entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", role: .destructive) { history.clear() }
                            .foregroundStyle(Ink.seal)
                    }
                }
            }
        }
    }

    private func row(_ entry: ReadingEntry) -> some View {
        NavigationLink {
            ReaderView(manga: entry.asManga, chapter: entry.asChapter, initialPage: entry.page)
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: entry.coverURL) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: CoverPlaceholder()
                    }
                }
                .frame(width: 44, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Ink.hairline, lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.mangaTitle)
                        .font(.system(.subheadline, design: .serif).weight(.semibold))
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    Text("CH·\(entry.chapterNumber) · page \(entry.page + 1)/\(max(entry.pageCount, entry.page + 1))")
                        .font(.inkMono(11, weight: .medium))
                        .foregroundStyle(Ink.seal)
                    Text(entry.updatedAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(Ink.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Ink.background)
    }

    /// Entries grouped by relative day, preserving recency order of groups.
    private var groupedEntries: [(key: String, value: [ReadingEntry])] {
        var order: [String] = []
        var buckets: [String: [ReadingEntry]] = [:]
        for entry in history.entries {
            let key = Self.dayLabel(entry.updatedAt)
            if buckets[key] == nil { buckets[key] = []; order.append(key) }
            buckets[key]?.append(entry)
        }
        return order.map { ($0, buckets[$0]!) }
    }

    private static func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month().day().year())
    }

    private func delete(in group: [ReadingEntry], at offsets: IndexSet) {
        for index in offsets { history.delete(group[index]) }
    }
}

private extension ReadingEntry {
    var asManga: Manga {
        Manga(id: mangaId, title: mangaTitle, description: "", status: "unknown", year: nil, coverURL: coverURL)
    }
    var asChapter: Chapter {
        Chapter(id: chapterId, number: chapterNumber, title: nil)
    }
}

#Preview {
    HistoryView().environmentObject(HistoryStore())
}
```

- [ ] **Step 2: Register the file in `project.pbxproj`** — first pick two IDs not already present:

Run: `grep -c "AD1157092EA0000100CF2434\|AD1157092EA0000200CF2434" MangaCarta.xcodeproj/project.pbxproj`
Expected: `0` (if not 0, change the last digits until unique).

Make 4 edits mirroring `SearchView.swift`:

1. In `/* Begin PBXBuildFile section */` (near line 21), add:
```
		AD1157092EA0000200CF2434 /* HistoryView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AD1157092EA0000100CF2434 /* HistoryView.swift */; };
```
2. In `/* Begin PBXFileReference section */` (near line 57), add:
```
		AD1157092EA0000100CF2434 /* HistoryView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HistoryView.swift; sourceTree = "<group>"; };
```
3. In the `Views` `PBXGroup` `children` list (near line 157), add a line:
```
				AD1157092EA0000100CF2434 /* HistoryView.swift */,
```
4. In the `MangaCarta` target's `Sources` build phase `files` list (near line 300, alongside `SearchView.swift in Sources`), add:
```
				AD1157092EA0000200CF2434 /* HistoryView.swift in Sources */,
```

- [ ] **Step 3: Add the History tab to `ContentView.swift`** — add the enum case and a tab in **both** `TabView` branches.

Enum (line ~14):
```swift
    enum Tabs: Equatable, Hashable, Identifiable  {
        case home
        case bookmarks
        case history
        case search
        case settings

        var id: Self { self }
    }
```

In **each** of the two `TabView` blocks, insert after the `BookmarksView()` tab:
```swift
                HistoryView()
                    .tabItem {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                    .tag(Tabs.history)
```

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `** BUILD SUCCEEDED **`. (If the build can't find `HistoryView`, the pbxproj edit is wrong — recheck all four entries.)

- [ ] **Step 5: Manual verification**

Read a couple of chapters across different manga. Open the History tab: entries appear newest-first, grouped under "Today". Tap one → reopens at the saved page. Swipe a row to delete it; "Clear" empties the tab and shows the empty state.

- [ ] **Step 6: Commit**

```bash
git add MangaCarta/Views/HistoryView.swift MangaCarta.xcodeproj/project.pbxproj MangaCarta/ContentView.swift
git commit -m "Add History tab"
```

---

### Task 6: Library update tracking — API, counting, store

**Files:**
- Modify: `MangaCarta/Models/MangaDexAPI.swift` (add `RecentChapter`, `recentChapters`, `newChapterCount`)
- Modify: `MangaCarta/Services/LibraryStore.swift` (fields, `refresh()`, `markCaughtUp`)
- Test: `MangaCartaTests/MangaCartaTests.swift` (append)

**Interfaces:**
- Consumes: existing `request<T>`, `ChapterListResponse`, `ChapterData` in `MangaDexAPI.swift`.
- Produces:
  - `struct RecentChapter: Equatable { let id: String; let number: String; let readableAt: String? }`
  - `static func recentChapters(mangaId: String) async throws -> [RecentChapter]`
  - `func newChapterCount(_ recent: [RecentChapter], since baseline: String?) -> Int`
  - `LibraryItem` gains `var lastSeenReadableAt: String?`, `var latestReadableAt: String?`, `var newChapterCount: Int?`
  - `LibraryStore`: `@Published private(set) var isRefreshing`, `func refresh() async`, `func markCaughtUp(_ id: String)`

- [ ] **Step 1: Write the failing tests** — append to `MangaCartaTests.swift`:

```swift
// MARK: - Library updates

func testNewChapterCountCountsNewerDistinct() {
    let recent = [
        RecentChapter(id: "a", number: "12", readableAt: "2026-07-13T00:00:00Z"),
        RecentChapter(id: "b", number: "12", readableAt: "2026-07-12T00:00:00Z"), // dup number
        RecentChapter(id: "c", number: "11", readableAt: "2026-07-11T00:00:00Z"),
        RecentChapter(id: "d", number: "10", readableAt: "2026-07-01T00:00:00Z"),
    ]
    // baseline just after ch10 -> ch11 and ch12 are new (distinct) = 2
    XCTAssertEqual(newChapterCount(recent, since: "2026-07-05T00:00:00Z"), 2)
}

func testNewChapterCountNilBaselineCountsAllDistinct() {
    let recent = [
        RecentChapter(id: "a", number: "2", readableAt: "2026-07-13T00:00:00Z"),
        RecentChapter(id: "b", number: "1", readableAt: "2026-07-12T00:00:00Z"),
    ]
    XCTAssertEqual(newChapterCount(recent, since: nil), 2)
}

func testLibraryItemDecodesLegacyJSON() throws {
    // JSON saved before the update-tracking fields existed.
    let legacy = #"{"id":"m1","title":"Old","coverURL":null}"#.data(using: .utf8)!
    let item = try JSONDecoder().decode(LibraryItem.self, from: legacy)
    XCTAssertEqual(item.id, "m1")
    XCTAssertNil(item.newChapterCount)
    XCTAssertNil(item.lastSeenReadableAt)
}
```

- [ ] **Step 2: Run to verify fail**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:MangaCartaTests/MangaCartaTests/testNewChapterCountCountsNewerDistinct`
Expected: FAIL — `cannot find 'RecentChapter' in scope`.

- [ ] **Step 3a: Add API + counting** — append to `MangaCarta/Models/MangaDexAPI.swift` inside the `MangaDexAPI` type (near `fetchChapters`), plus the `RecentChapter` type and `newChapterCount` at file scope:

```swift
/// A lightweight recent-chapter record for update detection.
struct RecentChapter: Equatable {
    let id: String
    let number: String
    let readableAt: String?
}

/// Count of distinct new chapter numbers whose `readableAt` is later than
/// `baseline`. `recent` is expected newest-first, so the first record per number
/// wins the dedupe. A `nil` baseline treats every dated chapter as new.
func newChapterCount(_ recent: [RecentChapter], since baseline: String?) -> Int {
    var seen = Set<String>()
    var count = 0
    for chapter in recent {
        guard seen.insert(chapter.number).inserted else { continue } // dedupe by number
        guard let readable = chapter.readableAt else { continue }
        if let baseline { if readable > baseline { count += 1 } }
        else { count += 1 }
    }
    return count
}
```

And the API method (inside `extension MangaDexAPI` / the namespace, next to `fetchChapters`):

```swift
    /// Newest English chapters for a manga (single page, no pagination) — used to
    /// detect and count library updates. Ordered newest-first by `readableAt`.
    static func recentChapters(mangaId: String) async throws -> [RecentChapter] {
        let res: ChapterListResponse = try await request(endpoint: "/chapter", queryItems: [
            URLQueryItem(name: "manga", value: mangaId),
            URLQueryItem(name: "translatedLanguage[]", value: "en"),
            URLQueryItem(name: "order[readableAt]", value: "desc"),
            URLQueryItem(name: "limit", value: "100")
        ])
        return res.data.map {
            RecentChapter(id: $0.id, number: $0.attributes.chapter ?? "?",
                          readableAt: $0.attributes.readableAt)
        }
    }
```

(Note: `ChapterAttributes` already exposes `chapter` and `readableAt`; verify by reading `MangaDexAPI.swift:120-126`.)

- [ ] **Step 3b: Extend `LibraryItem` + `LibraryStore`** — in `MangaCarta/Services/LibraryStore.swift`:

Replace the struct (lines 12-16):
```swift
struct LibraryItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let coverURL: URL?
    var lastSeenReadableAt: String?   // caught-up marker; advances only on read
    var latestReadableAt: String?     // newest chapter seen at last refresh
    var newChapterCount: Int?         // badge count (nil/0 = no badge)
}
```

Add to the class (after `@Published private(set) var items`):
```swift
    @Published private(set) var isRefreshing = false
```

Add these methods to `LibraryStore` (before `save()`):
```swift
    /// Refresh every saved manga's latest-chapter info concurrently and recompute
    /// new-chapter badges. Best-effort: per-item failures are ignored.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let current = items
        let results: [(String, [RecentChapter])] = await withTaskGroup(
            of: (String, [RecentChapter])?.self
        ) { group in
            for item in current {
                group.addTask {
                    guard let recent = try? await MangaDexAPI.recentChapters(mangaId: item.id) else { return nil }
                    return (item.id, recent)
                }
            }
            var out: [(String, [RecentChapter])] = []
            for await result in group { if let result { out.append(result) } }
            return out
        }

        var updated = items
        for (id, recent) in results {
            guard let idx = updated.firstIndex(where: { $0.id == id }) else { continue }
            let latest = recent.first?.readableAt
            if updated[idx].lastSeenReadableAt == nil {
                // First-ever refresh: establish baseline, no false "new".
                updated[idx].lastSeenReadableAt = latest
                updated[idx].latestReadableAt = latest
                updated[idx].newChapterCount = 0
            } else {
                updated[idx].latestReadableAt = latest
                updated[idx].newChapterCount = newChapterCount(recent, since: updated[idx].lastSeenReadableAt)
            }
        }
        items = updated
        save()
    }

    /// Mark a manga caught-up (called when the reader opens one of its chapters):
    /// advance the baseline to the newest known chapter and clear the badge.
    func markCaughtUp(_ id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].lastSeenReadableAt = items[idx].latestReadableAt ?? items[idx].lastSeenReadableAt
        items[idx].newChapterCount = 0
        save()
    }
```

- [ ] **Step 4: Run tests to verify pass**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:MangaCartaTests/MangaCartaTests/testNewChapterCountCountsNewerDistinct -only-testing:MangaCartaTests/MangaCartaTests/testNewChapterCountNilBaselineCountsAllDistinct -only-testing:MangaCartaTests/MangaCartaTests/testLibraryItemDecodesLegacyJSON`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add MangaCarta/Models/MangaDexAPI.swift MangaCarta/Services/LibraryStore.swift MangaCartaTests/MangaCartaTests.swift
git commit -m "Add library refresh + new-chapter counting"
```

---

### Task 7: Library refresh UI + badges + clear-on-read

**Files:**
- Modify: `MangaCarta/Views/BookmarksView.swift`
- Modify: `MangaCarta/Views/ReaderView.swift` (call `markCaughtUp`)

**Interfaces:**
- Consumes: `LibraryStore.refresh/isRefreshing/markCaughtUp` (Task 6), `MangaCoverCard(stamp:stampTinted:)`.
- Produces: (UI only)

- [ ] **Step 1: Pull-to-refresh + toolbar button + badges** — in `MangaCarta/Views/BookmarksView.swift`, update the populated branch. Add `.refreshable` to the `ScrollView`, pass a stamp to the card, and add a toolbar button.

Card call (line ~29-32):
```swift
                                NavigationLink(destination: MangaDetailView(manga: item.asManga)) {
                                    MangaCoverCard(
                                        title: item.title,
                                        coverURL: item.coverURL,
                                        stamp: (item.newChapterCount ?? 0) > 0 ? "NEW · \(item.newChapterCount!)" : nil,
                                        stampTinted: true
                                    )
                                }
                                .buttonStyle(.plain)
```

Add `.refreshable` to the populated `ScrollView` (after `.background(Ink.background)`):
```swift
                    .refreshable { await library.refresh() }
```

Add a toolbar to the `NavigationStack`'s content (after `.navigationTitle("Library")`):
```swift
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await library.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(library.isRefreshing || library.items.isEmpty)
                }
            }
```

- [ ] **Step 2: Clear badge on read** — in `MangaCarta/Views/ReaderView.swift`, add the library env object and call `markCaughtUp` once pages load. Add near the other env objects:
```swift
    @EnvironmentObject private var library: LibraryStore
```
In the `.task` (Task 3, step 3), after `advanceProgress(to: start)` add:
```swift
            library.markCaughtUp(manga.id)
```

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verification**

Add a manga to the Library. Pull down on the Library grid (and try the toolbar refresh button) — first refresh establishes the baseline with no badge. Simulate an update by clearing the app's baseline (or wait for a real new chapter) and refresh again: a "NEW · N" stamp appears on that cover. Open the manga and read → the badge clears.

- [ ] **Step 5: Commit**

```bash
git add MangaCarta/Views/BookmarksView.swift MangaCarta/Views/ReaderView.swift
git commit -m "Add library pull-to-refresh, new-chapter badges, clear-on-read"
```

---

## Final verification

- [ ] Run the full test suite: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 16' test` → all pass.
- [ ] Build succeeds: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 16' build` → `** BUILD SUCCEEDED **`.
- [ ] End-to-end manual pass: read → resume (mid-chapter and next-chapter), History tab logs and reopens, Library refresh badges appear and clear, chapter order toggles, reader defaults to right-to-left.
- [ ] Update `CLAUDE.md` "Current state" section: History tab now exists; Library has refresh + update badges; reader tracks progress. (Small doc edit, commit separately.)

## Notes on conventions

- Tests use XCTest (existing `MangaCartaTests` class), appended in-file to avoid `pbxproj` edits for the non-synchronized test target.
- `@MainActor` store tests use `@MainActor func ... ` and an injected `UserDefaults(suiteName:)` so they never touch the real defaults.
- All new UI uses existing "Ink & Seal" tokens; no new colors or fonts introduced.
