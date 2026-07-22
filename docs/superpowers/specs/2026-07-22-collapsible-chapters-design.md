# Collapsible Chapters — compact preview + dedicated full-list screen

**Date:** 2026-07-22
**Status:** Design approved, pending spec review

## Problem

The manga detail page (`Views/MangaDetailView.swift`) renders the **entire** chapter
list inline in its scrolling body. For long series this is a wall: Steel Ball Run has 98
chapters, so the newly-shipped **"More Like This"** rail — which sits at the very bottom of
the page — is only reachable after scrolling past all 98 rows. Visual QA confirmed this
firsthand.

Goal: make the More Like This rail reachable in one short scroll, and make long detail
pages less of a wall, **without** hiding chapters (the primary content of a reader) behind a
tap on every visit.

## Approach (chosen)

Truncate the inline chapter list to a small **preview**, and move the full chapter
experience to a **dedicated pushed screen**. Rejected alternatives: a pure collapse-to-header
toggle (hides primary content by default), and reordering the rail above chapters (demotes
the main content). Expand-in-place was also considered and deferred — a dedicated screen was
chosen for now so the result is easy to evaluate.

## Design

### Component split

Two units with clear, separate purposes:

- **`ChapterListView` (new, `Views/`)** — the canonical home for the *full* chapter
  experience. Owns the complete list, the sort toggle (newest/oldest), and multi-select
  mode with the bottom-bar batch actions (Select All / Mark Read / Mark Unread / Cancel).
  This is a **lift** of logic that already exists in `MangaDetailView` — no new behavior.
  As a pushed `NavigationStack` screen it gets its own `.bottomBar` toolbar and tab-bar
  hiding naturally, replacing today's in-page toolbar juggling.
  - Interface: `ChapterListView(manga: Manga, chapters: [Chapter])`.
  - Depends on: `HistoryStore` (from the environment, for read-state + mark read/unread),
    `ReaderView` (per-row navigation), the shared chapter-row rendering.
  - Does NOT depend on `LibraryStore` or `MangaDetailViewModel`.

- **`MangaDetailView` Chapters section (modified)** — becomes a compact **preview**:
  - The existing `InkSectionHeader("Chapters", eyebrow: "\(count) available")`.
  - The **newest 5** chapters, rendered with the existing `chapterRow`, each a
    `NavigationLink` to `ReaderView` with the current long-press "mark read/unread"
    context menu. Always newest-first (no inline sort toggle).
  - A **"Show all N chapters"** row (chevron, `NavigationLink` to `ChapterListView`) shown
    only when `count > 5`.
  - The inline `SELECT` and sort controls are **removed** from the detail page (they now
    live on `ChapterListView`).

Net effect: `MangaDetailView` sheds its select-mode state (`isSelecting`,
`selectedChapterIDs`), the `.bottomBar` select toolbar, `toggleSelection`, `markSelected`,
and `allChaptersSelected` — a welcome simplification of a large file. The More Like This
rail (already the last section) now follows a short preview instead of the full list.

### Constants

- **Preview size: 5** chapters (newest-first).

### Behavior by chapter count

- **count > 5:** preview shows the newest 5 + "Show all N chapters" → `ChapterListView`.
- **count ≤ 5:** preview shows all of them inline; **no** "Show all" row.

### Edge cases

- **Loading / error / empty:** the preview keeps the current states verbatim — "Loading
  chapters…", the `InkNotice(error)` notice, and "No chapters yet." No "Show all" row until
  chapters have loaded.
- **Preview sort:** always newest-first; the newest/oldest toggle lives on `ChapterListView`.

### Intentional drop (YAGNI)

For manga with **≤ 5 chapters**, sort and multi-select become unavailable (they exist only
on `ChapterListView`, which there is no reason to open when every chapter is already shown).
This is a deliberate, minor change from today, where even a 3-chapter manga carries those
controls. Rationale: sorting or bulk-marking a handful of chapters is negligible value;
per-row tap-to-read and long-press "mark read/unread" still work inline. Accepted.

### Unaffected

- The **"Continue"/resume** button in `actionRow` and its Netflix-style next-chapter advance
  are independent of chapter *display* logic — untouched.
- `sortChapters`, `resumeAction`, and the reader flow are reused as-is.

## Data flow

`MangaDetailViewModel` continues to own `vm.chapters` on the detail page. The preview reads
`vm.chapters`, sorts newest-first, and takes the first 5. "Show all" passes the full
`vm.chapters` array by value into `ChapterListView(manga:chapters:)`. `ChapterListView`
resolves `HistoryStore` from the environment (like `MangaDetailView`), sorts/selects
locally, and navigates to `ReaderView` per row.

## Shared rendering

The per-chapter row (`chapterRow(_:selected:)` in `MangaDetailView`) is used by both the
preview and `ChapterListView`. To avoid divergence, extract it into a small reusable
`ChapterRow` view **in `Components/`** that both call. It reads `HistoryStore` for
read-state. This keeps one source of truth for row appearance, and `Components/` is a
synchronized group so the extraction needs no `project.pbxproj` edit.

## Project wiring

`Views/` is **not** an Xcode synchronized group, so the new **`ChapterListView`** file needs
the four-part `project.pbxproj` wiring — `PBXFileReference`, `PBXBuildFile`, a child entry in
the `Views` `PBXGroup`, and a `Sources`-build-phase entry — mirroring an existing `Views`
file (per CLAUDE.md). `ChapterRow` lives in `Components/` (synchronized) and needs no pbxproj
edit.

## Testing

Consistent with the codebase's XCUITest-driven UI verification (iPhone 17 sim,
`-parallel-testing-enabled NO`):

1. **Preview truncation + rail reachability (UI test):** open a long Home title, assert the
   Chapters header, assert a "Show all" affordance exists, and assert the "More Like This"
   header is reachable with far less scrolling than the full list. (Complements, and largely
   supersedes the scroll cost of, the existing `testMoreLikeThisDetailRailLiveVerification`.)
2. **Full-list screen (UI test):** tap "Show all", assert the full list, exercise the sort
   toggle, and enter select mode → Mark Read on a chapter, asserting the read state via the
   existing history affordance.
3. **Regression:** the existing detail/reader/history unit + UI tests must stay green.

## Out of scope

- Expand-in-place (deferred; dedicated screen chosen for now).
- Any change to resume/Continue, the reader, or the recommendations rail.
- Per-chapter read/unread marks beyond what exists today.
