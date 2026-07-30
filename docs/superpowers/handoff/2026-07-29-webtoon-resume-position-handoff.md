# Session Handoff — 2026-07-29: webtoon resume position (ADR-0014 written, step 2 of 6 done)

**Audience:** the next session, continuing on `webtoon-resume-position`.

**This file replaces the design handoff that was here.** The design now lives in **ADR-0014**, which
is authoritative and contains one correction the old handoff got wrong (see *What implementation
changed about the design*). Read the ADR, not a summary of it.

## State

| | |
|---|---|
| `main` | `bd0d678` — PR #30 merged, ADR-0012 + ADR-0013 |
| Working branch | `webtoon-resume-position` at `0cf97eb`, **nothing committed yet** — all work below is uncommitted in the tree |
| ADR | `docs/adr/0014-resuming-a-webtoon-where-the-reader-stopped.md`, 12 decisions |
| Tests | **329 green, 0 failures** (317 on `main` + 12 new) |
| Next ADR number | 0015 |

Uncommitted files:

```
new:  Manga-Reader/Models/ReadingPosition.swift
new:  Manga-ReaderTests/ReadingPositionTests.swift          (12 tests)
new:  docs/adr/0014-resuming-a-webtoon-where-the-reader-stopped.md
mod:  Manga-Reader/Services/HistoryStore.swift              (the whole model change)
mod:  Manga-Reader/Manga_ReaderApp.swift                    (history.flush() on .background)
mod:  Manga-Reader/Views/ReaderView.swift                   (call site only — the view work is step 4)
mod:  Manga-ReaderTests/{Manga_ReaderTests,WorkMintingTests}.swift  (23 record() call sites migrated)
mod:  docs/adr/0013-…, docs/glossary.md                     (amendments + vocabulary)
mod:  Manga-Reader.xcodeproj/project.pbxproj                (see the xcp note in Hazards)
```

## The decision that constrains everything else

**`entry.page` is the completion signal for three subsystems, one of which is the recommender.**
`finished = pageCount > 0 && page >= pageCount - 1` is computed independently at
`ReadingResume.swift:68`, `TasteProfile.swift:99`, and inverted as `inProgress` at
`ChapterRow.swift:23`. That is why recorded progress is monotonic. Do not make `page` a
last-position pointer. ADR-0014's Context has the full verified list — *do not re-derive it*.

## Done

**Step 1 — ADR-0014, glossary, ADR-0013 amendments.** ADR-0013's header now reads
`amended by ADR-0014`; three of its hazards and two of its revisit triggers are struck through with
what resolved them. Glossary gained **Reading position**, **Strip**, **Anchor grid**, **Settle loop**,
and **Pager target** was amended to say it is a `ReadingPosition` and is *not* monotonic.

**Step 2 — the model/store layer, TDD, five red-green slices.**

- `ReadingPosition { page: Int, fraction: Double }`, `Comparable` **lexicographically** — page
  dominates, fraction breaks ties. `HistoryStore.record` takes `max()` over it, so the monotonicity
  is visible at the point it is enforced.
- `ReadingEntry.fraction` (flat) + a `position` computed property with a setter.
- `record(manga:chapter:position:pageCount:)` — signature changed, all 24 call sites migrated.
- **A `record` that advances nothing changes nothing**: no position write, no `updatedAt` bump, no
  save. `furthestPage`/`hasRecordedProgress` in the view are now redundant (step 4 deletes them).
- **Throttled save**: `saveInterval` (production default 2s, injected in tests), leading-edge
  `saveSoon()` that does *not* re-arm, and a public `flush()` wired into `Manga_ReaderApp`'s
  `.background` case beside `works.flush()`.

Two judgment calls made inside the confirmed design:

- **Only `record` is throttled.** `markRead`/`markUnread`/`delete`/`clear` write straight through —
  a manual mark surviving one relaunch but not another is worse than losing a fraction — and an
  immediate `save()` cancels whatever the throttle had pending. Pinned by
  `testMarkingReadWritesWithoutWaitingForTheThrottle`.
- **The no-op guard exempts `pageCount`.** A corrected page count still lands even when the position
  does not, so a chapter whose count was recorded wrong can fix itself without scrolling forward.

## What implementation changed about the design

**ADR-0014 decision 1 originally claimed "migration is free: the default fills in for every existing
entry". That was false, and a test caught it.** Swift's synthesized `init(from:)` **ignores default
values for non-optional properties** and throws `keyNotFound` — so every pre-ADR-0014 entry would have
failed to decode and the entire History tab would have read as empty. `sourceId` migrated for free only
because `Optional` decodes via `decodeIfPresent`.

`ReadingEntry` now hand-writes `init(from:)`: `decodeIfPresent` for `fraction`, every other key still
required, because a missing `page` is corruption rather than an old format. The ADR carries the
correction inline, including the honest admission that the rejected `Double`-page alternative genuinely
*would* have migrated for free (`"page":4` decodes into a `Double`) — it was still rejected, on the
grounds that a decoder is a one-time cost in one file while a field that lies for two of three reading
modes is paid at every read site forever.

**Generalise the lesson:** any future defaulted, non-optional field on a persisted type needs the same
treatment, and a migration test is the only thing that will tell you.

## Left to do, in order

3. **Plumbing** — carry `ReadingPosition` end to end, TDD where it is pure:
   - `ResumeAction.cont`/`.reread` carry a position, not a page (`ReadingResume.swift:52`, `:69`)
   - `ReaderView.init` and `ReaderViewModel.init` take a position instead of `initialPage`
     (`ReaderView.swift:56`, `ReaderViewModel.swift:73`); `Landing.exact` carries one
   - `pagerTarget` becomes a `ReadingPosition` (`ReaderViewModel.swift:52`) — expect ~13
     `ReaderViewModelTests` assertions to need updating
   - `HistoryView.swift:66` passes `entry.position`
   - **the row-tap doors**: `ChapterListView.swift:34` and `MangaDetailView.swift:411` pass
     `history.entry(forChapter:)?.position` (ADR-0014 decision 11)
   - `continueProgress` → `(page + fraction) / pageCount`, treating a paged entry's `fraction == 0`
     as "page seen" so paged progress does not shift down a page (`MangaDetailView.swift:211-215`)
4. **Capture + live position in `verticalReader`** — `GeometryReader` per realized row, viewport-top
   fraction clamped to `[0,1)`, ~1s **throttle** (not idle-debounce) feeding `record`, live position as
   `@State`, pending update **dropped** on chapter change via `progressChapterID`
   (`ReaderView.swift:134`). **Delete `advanceProgress`'s latch and the `.onAppear` advance for
   `.vertical` only** (`ReaderView.swift:188-195`, `:272`) — paged modes keep `onChange(of: currentPage)`.
5. **Restore** — anchor grid (`N = 50`, `Color.clear` slices, **`allowsHitTesting(false)`** or it eats
   the chrome-toggle tap) + the settle loop. Its stopping rule is a **pure function, unit-tested**
   against: strip shorter than viewport, fraction 0.99, measurement that never stabilises, target row
   not realized. Replace the guard `vm.pagerTarget > 0` with `page > 0 || fraction > 0`
   (`ReaderView.swift:305`) and **delete the 50ms sleep** (`:309`).
6. **Hand-checks** — resume mid-strip; after rotation; images all disk-cached vs all cold (the two ends
   of the settle loop's timing); mode switch mid-chapter; paged modes unaffected; row tap resumes.

## Hazards

- **`xcp` reformatted `project.pbxproj` in the *opposite* direction to what CLAUDE.md documents.** This
  time it **collapsed** the three `PBXFileSystemSynchronizedRootGroup` entries to one line each *and*
  stripped `lastKnownFileType`/`name` from three unrelated `PBXFileReference` entries. Net 10
  insertions / 30 deletions, of which only **4 lines** are the new test file. Decide before staging
  whether to keep the noise or `git checkout -p` the unrelated hunks. The lesson from CLAUDE.md holds
  and generalises: **inspect the pbxproj diff immediately before `git add`, and do not assume which
  direction the reformat went.**
- **The 5 remaining SourceKit errors are noise** — "No such module 'XCTest'", "Cannot find type
  'Manga' in scope" on files that compile and test clean. Judge only by `xcodebuild`.
- **`finished` changes meaning for webtoons in step 4** (viewport top *enters* the last strip, rather
  than that strip *appearing*). It feeds the recommender via `TasteProfile.swift:99`. Nothing fails
  loudly; the effect is different For You output later.
- **A paged read leaves a stale fraction behind** — reading page 5 paged records `(5, 0)` and the max
  keeps an earlier `(5, 0.8)`, so switching back to webtoon resumes 80% down a strip whose top the
  paged reader was on. Harmless, invisible in the model, documented in ADR-0014's Hazards.
- **The `agy` post-commit hook runs its own `xcodebuild`** and holds the DerivedData lock for 2+
  minutes; a concurrent build dies with "database is locked". Gate on
  `until ! pgrep -f "agy --model" >/dev/null; do sleep 15; done`.
- **A stub `MangaSource` mutated by both the test and the code under test must be `@MainActor`** — its
  methods are nonisolated, so `await source.pageURLs(...)` from a `@MainActor` view model runs off the
  main actor. This crashed `ReaderViewModelTests` with `unrecognized selector` *after passing twice*.
- **Do not stack PRs.** Merging a base with `--delete-branch` closes the child unrecoverably.
- A full `xcodebuild test` cycle here is ~90s; budget for it in the red-green loop.

## Also still open on the reader (deliberately out of scope for this branch)

- **Externally hosted chapters are reported as broken.** They answer `/at-home/server` with 200 and an
  empty file list, so they fail through the zero-pages path and read "This chapter has no pages to
  read." They report `pages: 0` in the `/chapter` feed and `ChapterAttributes`
  (`MangaDexAPI.swift:125-131`) does not decode `pages` yet — one field would let the chapter list mark
  or route the row before anyone opens it. **The most worthwhile reader follow-up.**
- **The 5xx wording.** `readerFailureMessage` rewrites every `MangaDexError.httpStatus` to "This
  chapter isn't available to read from this source. (HTTP 503)", so a transient 503 gets that sentence
  next to a Retry button. One branch on the classification already computed fixes it.
- **`HistoryStore.save()` is still an all-or-nothing re-encode** of 500 entries plus read marks
  (`:167-174`). The throttle makes it survivable, not cheap. ADR-0014 Revisit triggers.
