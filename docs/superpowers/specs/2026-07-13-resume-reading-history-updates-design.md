# Resume Reading · History Tab · Library Updates — Design

**Date:** 2026-07-13
**Branch:** `feature/ink-seal-design-dark-mode`
**Status:** Approved (design), pending implementation plan

## Overview

Three related reader-experience features, all built on a shared reading-progress
spine:

1. **Resume button** on the manga detail screen (below "Add to Library") that
   reopens the manga at the chapter and page the reader left off — with a
   Netflix-style jump to the next chapter when they finished the previous one.
2. **History tab** — a full chronological log of chapters read, showing chapter
   and page, that reopens any entry at its exact position.
3. **Library refresh + update badges** — pull-to-refresh (and a toolbar button)
   in the Library that fetches the latest chapters per saved manga and shows a
   count of new chapters on covers that received them.

## Confirmed product decisions

- **Resume point:** exact last chapter + page. Exception: if the reader left off
  on the *very last page* of a chapter, assume they finished it and start the
  next upcoming chapter (Netflix-style).
- **History model:** full chronological log. Re-opening a chapter later creates a
  new entry; a single continuous reading session updates one entry in place.
- **Update badge:** shows the *number* of new chapters available; clears when the
  reader opens the reader for that manga (i.e., reads).
- **Chapter list order:** default newest-first (latest chapter at top, first
  chapter at bottom), with a toggle button to flip to oldest-first.
- **Reading direction default:** right-to-left (manga order).

## Architecture

MVVM over the existing stateless `MangaDexAPI`, matching current conventions.
Two `@MainActor ObservableObject` stores persisted to `UserDefaults` and injected
app-wide as `@EnvironmentObject` (mirroring the existing `LibraryStore`):

- `HistoryStore` — new; the reading-progress spine. Powers both the resume button
  and the History tab.
- `LibraryStore` — extended (not replaced) with update-tracking fields and a
  `refresh()` method.

### Component 1 — `HistoryStore` (new)

New file `Manga-Reader/Services/HistoryStore.swift`. `Services/` is an Xcode 16
synchronized root group, so the file compiles automatically (no `pbxproj` edit).

```swift
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
    @Published private(set) var entries: [ReadingEntry]   // most-recent-first
    func record(manga: Manga, chapter: Chapter, page: Int, pageCount: Int)
    func latestEntry(forManga id: String) -> ReadingEntry?
    func delete(_ entry: ReadingEntry)
    func clear()
}
```

**`record` semantics:**
- If the newest entry is the *same* `mangaId` **and** `chapterId`: update its
  `page`, `pageCount`, `updatedAt` in place and move it to the front. (One
  continuous reading session = one entry.)
- Otherwise prepend a new entry.
- Cap the log at ~500 entries (drop oldest).

**Persistence:** JSON in `UserDefaults` under a dedicated key, same pattern as
`LibraryStore` (`try?` encode/decode, silent no-op on failure).

`page` is stored as the **furthest page reached**, not merely the last-visible
page, so progress never goes backwards within a session.

### Component 2 — `ReaderView` plumbing (the linchpin)

Widen the initializer:

```swift
// before
ReaderView(chapterId: String)
// after
ReaderView(manga: Manga, chapter: Chapter, initialPage: Int = 0)
```

Reasons all three call sites need the richer signature:
- `manga` — identity + title + cover so History can render cards and progress is
  attributable, and so it works for manga not in the Library.
- `chapter` — chapter id **and** number (for "Continue Ch 12" and log rows).
- `initialPage` — seek target when resuming.

**Reading-direction default:** change `@AppStorage("readingMode")`'s default from
`.leftToRight` to `.rightToLeft` (manga order). This applies to fresh installs
only — an existing persisted choice is respected.

Behavior added to `ReaderView`:
- **Furthest-page tracking** via each page's `.onAppear(index)`. This is the only
  mechanism that works in *both* paged and webtoon modes — the vertical/webtoon
  reader currently tracks no page at all (`currentPage` is bound only inside the
  paged `TabView`, and the page indicator is hidden in vertical mode).
- **Seek to `initialPage` on open:** paged mode sets the `TabView` selection;
  webtoon mode uses `ScrollViewReader.scrollTo(index)`.
- **Progress reporting:** call `history.record(...)` as the furthest page advances
  (and on disappear), reading `history` and `library` from the environment.
- **Badge clearing:** call `library.markCaughtUp(mangaId:)` when the reader opens
  a chapter for a manga that is in the Library.

Call sites updated: `MangaDetailView` chapter rows, the new resume button, and
History rows.

### Component 3 — Resume button (`MangaDetailView`)

A new `resumeButton` view placed directly below `libraryButton`. It computes a
target from `history.latestEntry(forManga: manga.id)` and the loaded
`vm.chapters` (ordered ascending):

| State | Label | Target |
|---|---|---|
| No history entry | "Start Reading" | first chapter, page 0 |
| Mid-chapter (`page < pageCount - 1`) | "Continue Ch X · p.Y" | that chapter, that page |
| Finished last page, next chapter exists | "Start Ch Z" | next chapter, page 0 |
| Finished last page, already latest | "Read Again · Ch X" | that chapter, last page |

- "Finished" = `page >= pageCount - 1` (guard `pageCount > 0`).
- "Next chapter" = the chapter after the entry's `chapterNumber` in `vm.chapters`.
- The button is meaningful only once `vm.chapters` is loaded (the target needs the
  list). While loading, show a disabled placeholder ("Start Reading" disabled or a
  spinner). If chapters fail to load / are empty, hide the button.
- Implemented as a `NavigationLink` into `ReaderView` with the computed
  `manga`/`chapter`/`initialPage`.

Styling: secondary treatment relative to the primary "Add to Library" button —
e.g. seal-outlined rather than filled — so the two buttons read as a pair without
competing. Follows the existing "Ink & Seal" tokens (`Ink.seal`, `Gutter.page`,
`.inkMono` for the chapter/page stamp).

**Chapter list ordering.** `fetchChapters` returns chapters ascending; the view
owns display order. Add `@State private var chaptersDescending = true` (default
newest-first: latest chapter at top, chapter 1 at bottom). The `chapters` section
renders `vm.chapters` sorted by chapter number accordingly, with a small toggle
button in the section header (e.g. an `arrow.up.arrow.down` stamp reading
"NEWEST" / "OLDEST") that flips the order.

- Sort key is the **numeric** value of `Chapter.number` (`Double(number)`), since
  numbers are strings ("2" vs "10" vs "10.5"); unparseable/`"?"` numbers sort to
  the end. Use a stable sort helper so ties keep source order.
- **Resume "next chapter" logic is independent of display order** — it always
  finds the next chapter by ascending numeric order, regardless of how the list is
  currently sorted. Both the display sort and the resume logic share the same
  numeric-ordering helper.

### Component 4 — History tab (`HistoryView`)

New file `Manga-Reader/Views/HistoryView.swift`. **`Views/` is NOT a synchronized
group** — this file must be added to `project.pbxproj` in all four places
(`PBXFileReference`, `PBXBuildFile`, the `Views` `PBXGroup` child list, and the
target's `Sources` build phase), mirroring an existing `Views` file.

New tab in `ContentView` (both the iOS 18 and pre-18 `TabView` branches):
- 5th tab, label "History", system image `clock.arrow.circlepath`, own `case` in
  the `Tabs` enum and its own `.tag`.
- Wrapped in its own `NavigationStack` (only Home and Library have one today).

`HistoryView` contents:
- Reads `history.entries` (already reverse-chronological).
- Rows grouped by relative day: **Today**, **Yesterday**, then formatted dates.
- Each row: cover thumbnail, serif title, monospaced "CH·X · page Y/Z" stamp, and
  a relative timestamp. Tap → `NavigationLink` into `ReaderView(manga:chapter:
  initialPage: entry.page)` reopening the **exact** logged position.
- Swipe-to-delete removes a single entry (`history.delete`); a toolbar "Clear"
  action wipes all (`history.clear`).
- `InkEmptyState` (symbol `clock.arrow.circlepath`) when the log is empty.

**Design note — the Netflix "advance to next chapter" logic lives only on the
detail-view resume button, never on History rows.** A History entry is a snapshot
of a reading session, so tapping it reopens that exact chapter + page. This keeps
next-chapter logic in one place (the detail view, which owns the chapter list).

### Component 5 — Library refresh + update badges

**API addition** — `MangaDexAPI.recentChapters(mangaId:)`:
- One request: `/chapter?manga={id}&translatedLanguage[]=en&order[readableAt]=desc&limit=100`.
- Returns a lightweight list of `(id, number, readableAt)` — no full pagination (unlike
  `fetchChapters`), because we only need the newest slice to detect and count
  updates. `readableAt` is already decoded in `ChapterAttributes`.
- Comparison is by `readableAt` timestamp string (ISO-8601, lexically sortable),
  **not** chapter number (numbers are unreliable strings, e.g. "10" < "9").

**`LibraryItem` extension** — three new **optional** fields (optional is required:
`load()` uses `try?` decode, so a required new field would fail to decode
previously-saved libraries and silently wipe them):
- `lastSeenReadableAt: String?` — the `readableAt` the reader has caught up to;
  advances only when they read.
- `latestReadableAt: String?` — newest chapter's `readableAt` at last refresh.
- `newChapterCount: Int?` — the badge number (nil/0 = no badge).

**`LibraryStore` additions:**
- `@Published private(set) var isRefreshing = false`
- `func refresh() async` — fetch all items **concurrently** (via a task group;
  the API client already handles 429 retry). Per item:
  - `let recent = try await MangaDexAPI.recentChapters(mangaId: item.id)`
  - `latestReadableAt = recent.first?.readableAt`
  - If `lastSeenReadableAt == nil` (first-ever refresh): establish baseline —
    `lastSeenReadableAt = latestReadableAt`, `newChapterCount = 0` (no false
    "new" on first sync).
  - Else: count chapters newer than the baseline —
    `recent.filter { $0.readableAt > lastSeenReadableAt }`, **deduped by chapter
    number** first (multiple scanlation groups upload the same number; keep one
    per number, mirroring `fetchChapters`), so the badge counts distinct new
    chapters, not uploads.
  - Failures per-item are swallowed (leave that item's badge unchanged); refresh
    is best-effort.
  - Persist updated items.
- `func markCaughtUp(_ mangaId: String)` — set `lastSeenReadableAt =
  latestReadableAt`, `newChapterCount = 0`, persist. Called from the reader when
  opening a chapter of a saved manga.

**`BookmarksView` changes:**
- `.refreshable { await library.refresh() }` on the grid's `ScrollView`
  (pull-to-refresh), plus a toolbar refresh button that runs the same in a `Task`;
  disable it / show progress while `library.isRefreshing`.
- Cover cards with `newChapterCount > 0` show a tinted stamp "NEW · N" using
  `MangaCoverCard`'s existing `stamp` / `stampTinted` parameters.

**App wiring:** `Manga_ReaderApp` creates `@StateObject private var history =
HistoryStore()` and injects `.environmentObject(history)` alongside the existing
`library`.

## Data flow

```
Reader opens (manga, chapter, initialPage)
  → seeks to initialPage
  → user reads; furthest page advances (onAppear per index)
  → history.record(manga, chapter, page, pageCount)      [powers resume + History]
  → library.markCaughtUp(manga.id) if saved              [clears update badge]

Detail resume button
  → history.latestEntry(manga.id) + vm.chapters → target → ReaderView

History tab
  → history.entries (grouped by day) → row tap → ReaderView at exact page

Library refresh
  → library.refresh() → per item recentChapters() → newChapterCount → badge
```

## Error handling

- Store persistence: `try?` encode/decode, silent no-op (existing convention).
- `refresh()`: per-item failures swallowed; the overall call never throws to the
  UI. A fully failed refresh simply leaves badges as they were.
- Resume button: hidden if chapters fail to load; disabled placeholder while
  loading.
- Reader: unchanged existing error/empty handling for page fetches.

## Testing

Unit tests (`Manga-ReaderTests`, Swift Testing) for the pure logic:
- `HistoryStore.record`: same-session update-in-place vs. new entry on chapter
  change; most-recent-first ordering; 500-cap eviction.
- Resume-target selection: no-history → first chapter; mid-chapter → exact page;
  finished + next exists → next chapter page 0; finished + latest → re-read.
  (Extract this into a pure, testable free function / static method taking
  `(entry?, chapters)`.)
- Numeric chapter-ordering helper: "2" < "10" < "10.5"; `"?"`/unparseable sort to
  the end; stable on ties. Shared by the display-sort toggle and the resume
  next-chapter lookup.
- New-chapter counting: `readableAt` comparison; first-refresh baseline yields 0;
  subsequent refresh counts only newer entries.
- `LibraryItem` decodes from **old** JSON (without the three new fields) without
  data loss.

Manual verification on the iOS simulator: read part of a chapter → detail shows
"Continue Ch X · p.Y"; finish a chapter → detail offers next chapter; History tab
lists sessions and reopens them; add manga to Library, refresh, confirm badge
appears only for genuinely new chapters and clears after reading.

## Build order

1. `HistoryStore` + `ReaderView` plumbing (widen signature, furthest-page
   tracking, seek, `record`, RTL default).
2. Resume button + chapter-order toggle in `MangaDetailView` (shared numeric
   chapter-ordering helper).
3. History tab (`HistoryView` + `ContentView` tab + `pbxproj` edit).
4. Library refresh + badges (`recentChapters` API, `LibraryStore.refresh` /
   `markCaughtUp`, `LibraryItem` fields, `BookmarksView` UI).

## Out of scope (YAGNI)

- Syncing progress across devices / any backend.
- Per-chapter read/unread checkmarks in the chapter list.
- Background/automatic library refresh (manual pull-to-refresh only).
- Configurable history retention beyond the fixed ~500 cap.
