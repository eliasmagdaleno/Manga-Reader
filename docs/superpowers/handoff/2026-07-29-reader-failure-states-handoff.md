# Session Handoff — 2026-07-29: reader 404 trap fixed and hand-verified

**Audience:** the next session. The reader work is code-complete, green, and hand-checked on the
simulator; PR #30 needs nothing further. What is left is follow-up work the hand-check turned up —
chiefly that **reading progress is not saved in webtoon mode** (item 2), and that **externally hosted
chapters are reported to the user as broken** (see hazards).

Companion to `2026-07-29-anilist-pool-handoff.md`, which is **still current for the recommender**
and untouched by this work. Its blocker stands: ADR-0011 needs 3 AniList-resolved Works and the
live store has 1, so seeding the library with two or three mainstream series is still a
prerequisite before any pool code. Nothing here changes that.

## What prompted this

User report: opening a chapter that 404s traps you in the reader. The only control was Retry, which
can never succeed, and force-quitting was the only way out. Root cause: three reasonable decisions
lined up so the exit was reachable only through the view that failure prevents from rendering. Full
trace in ADR-0012's Context.

## State

| | |
|---|---|
| `main` | `163d650` — unchanged this session |
| Working branch | `reader-failure-states` — `33c29be` (model layer) + `876a4b8` (view layer) |
| ADRs | 0012 accepted, **amended by 0013**; both written. Next free number is **0014** |
| Tests | **317 green, 0 failures** (274 pre-existing + 29 from ADR-0012 + 14 from ADR-0013) |
| SwiftLint | 0 errors, 0 warnings in touched files (per the `agy` hook on `876a4b8`) |
| PR | opened from this branch — see below |

## Done

**ADR-0012** (`docs/adr/0012-reader-failure-states-and-chapter-advance-commit.md`) — six decisions,
now carrying an in-place amendment note where it flagged the landing-page seam.

**ADR-0013** (`docs/adr/0013-reader-view-layer-after-load-then-commit.md`) — eight decisions for the
view layer. Its Context is the one thing worth reading before touching the reader again:
**load-then-commit removed four protections that were holding by accident.** None was written down as
a protection; each was a side effect of clearing `pages` before the await, which tore the pager down
for the whole fetch. The pager index could not be stranded, re-entry was impossible, a loading
spinner appeared for free, and the progress counters were reset by whoever changed the chapter.

**`docs/glossary.md`** — new `## Reader` section: Chrome, Commit, Pager target, Advance trigger,
Transient / permanent failure, Banner.

**Model layer** (`33c29be`) — `ReaderPresentation`, `isTransientFailure` + `ClassifiedFailure`,
`ReaderViewModel` with load-then-commit `advance`.

**View layer** (`876a4b8`) — `ReaderView` consumes the view model and holds no fetch state; new
`Views/Components/ReaderBanner.swift`. Model-side additions in the same commit: `pagerTarget` (was
`landingPage`), the `requestGeneration` / `lastCompletedRequest` pair, the generation guard,
`Landing`-keyed message composition, `readerFailureMessage`.

All 43 reader tests were confirmed **red before the implementation** — the ADR-0013 batch by failing
to compile against symbols that did not exist yet, and the ADR-0012 batch (recorded last session)
by being written against the shipped mutate-first `advance`, where exactly the three
load-then-commit tests failed and everything else passed.

## Left to do

### 1. Hand-check on the iPhone 17 simulator — partly done

This cannot be automated here and ADR-0012 records why: the UI tests hit live MangaDex, are not in
CI, one red is no signal, and reproducing a failure needs some chapter id to stay permanently dead.
What no unit test can prove is that `dismiss()` escapes a `NavigationLink` push with the navigation
bar hidden (`ReaderView.swift`, `.toolbar(.hidden, for: .navigationBar)`).

- [x] **1. The reported bug.** Open an unreadable chapter → error text, **no** Retry, a working ✕.
      Verified by hand 2026-07-29.
- [x] **2. Failed advance.** Read a healthy chapter, swipe into a dead next chapter → the chapter you
      were on survives, you land back on **its last page**, and the error appears as a banner that
      auto-clears after 5s. Verified by hand 2026-07-29.
- [x] **3. Normal open** still works and the top bar auto-hides once pages arrive. Verified by hand
      2026-07-29.
- [x] **4. Webtoon mode**, since its scroll restore changed from `pages.count` to the completion
      marker. Verified by hand 2026-07-29 — and it surfaced a separate defect, item 2 below.

**All four pass. ADR-0012 and ADR-0013 are hand-verified; PR #30 needs nothing further.**

**Reproduction for 2 and 4** (verified 2026-07-29; content, so it can rot): *Hidarikiki no Eren*,
manga `672be603-c8f1-478b-866a-811652cffabc` — chapter 33 (22 pages) is immediately followed in the
reader's sorted list by chapter 207, which is externally hosted and has none. *Yamero Suki ni
Natteshimau*, manga `f5badc31-60a8-4a47-9ef8-cd40ba62e473`, has the same adjacency six times over
(chapters 1–6 each precede a dead duplicate). To find fresh ones: query
`/chapter?includeExternalUrl=1` for candidates, then look for a `pages > 0` entry followed by a
`pages == 0` one in the same manga's English feed.

### 2. Reported 2026-07-29: reading progress is not saved in webtoon mode

Found while hand-checking item 4. **Not a regression from this branch** — see below — so it does not
block PR #30, but it is the next real reader defect.

Two separate paths, and the fix depends on which one is at fault. The observation to make first is
whether History holds *no useful entry* for the webtoon chapter, or holds one that simply does not
resume you where you stopped.

- **Recording** — `.onAppear { advanceProgress(to: index) }` on each `WebtoonPage`. Materially
  unchanged by ADR-0013 (same call, same guard, only `pages` → `vm.pages`), so if nothing is written
  at all it predates this work. Suspect the `LazyVStack` realization order or the
  `index > furthestPage || !hasRecordedProgress` guard.
- **Restore** — this branch replaced an observer on `pages.count` with one on the completion marker,
  calling `proxy.scrollTo(vm.pagerTarget, anchor: .top)`. Stronger than what it replaced on a first
  load, but `scrollTo` into a `LazyVStack` whose rows are not realized yet — and whose images are
  unmeasured, since `WebtoonPage`'s placeholder is a fixed 460pt against strips that can be thousands
  of points tall — can silently do nothing.

**The likely root cause is conceptual, not a bug.** `ReadingEntry.page` is a *page index*
(`HistoryStore.swift:22`), and a webtoon "page" is a long strip. A chapter of 8 strips has only 8
resume points, so even a perfectly honored restore drops the reader at the top of the strip they were
halfway down. Doing this properly means storing a fractional or offset-based position for vertical
reading — a model change, and one that needs a decision about whether `ReadingEntry` grows a second
notion of position or `page` becomes a `Double`. Worth an ADR if it is taken on.

### 3. Optional: the 5xx wording

`readerFailureMessage` rewrites *every* `MangaDexError.httpStatus` code to "This chapter isn't
available to read from this source. (HTTP 503)" — and a 503 is transient, so that sentence can appear
next to a Retry button. Approved as-is deliberately; the refinement is one branch keyed on the
classification already computed (permanent → "isn't available", transient → "Couldn't reach the
source right now"), plus a test.

## Decisions worth not re-litigating

All argued out in grilling sessions and recorded with their rejected alternatives — ADR-0012 for the
model, ADR-0013 for the view. The ones most likely to be "simplified" back:

- **Chrome visibility is derived**, never assigned in a `catch`. Assigning works today and creates
  permanent bookkeeping.
- **The view repositions the pager on `lastCompletedRequest`, never on `pagerTarget`'s value.** Two
  consecutive chapters both landing on page 0 is the *common* case, fires no `onChange`, and leaves
  the pager on a stale sentinel index that immediately re-requests the next chapter.
- **Superseded requests commit nothing, report nothing, and touch neither `isLoading` nor the
  completion marker.** `guard !isLoading` was rejected for dropping the request the user most likely
  wants; task cancellation was rejected because `CancellationError` lands in the same `catch` and
  would banner "cancelled".
- **Reset, position and record are one ordered handler**, not three `onChange` observers. SwiftUI's
  observer ordering is not a documented guarantee, and if `advanceProgress` loses the race, page 0 of
  a new chapter goes unrecorded.
- **Vertical does not snap back on failure; paged does.** A discrete selection stranded on an index
  that renders nothing must move; a continuous offset at the bottom of a rendered chapter need not.
- **Banner dismissal is view state.** Clearing `errorMessage` to hide UI would make the model forget
  a failure `ReaderPresentation` derives the whole body from, and strand `failureIsTransient`.
- **Unknown errors are transient**; 408 is transient here though `MetadataUpgradeQueue` excludes only
  429 — a deliberate divergence, recorded as an ADR-0012 revisit trigger.

## Known hazards (recorded, not fixed)

- **The folded post-load handler is untestable** — view code, and the bug it prevents (silently not
  recording progress after a chapter change) is invisible unless you inspect history. ADR-0013's own
  weakest decision and its first revisit trigger: move the two counters into `ReaderViewModel`.
- **`presentation.banner` is now advisory, not authoritative** — the view can suppress it, so a
  presentation test asserting `banner != nil` proves only that the model wants one.
- **An externally hosted chapter is reported to the user as broken.** It answers `/at-home/server`
  with **200 and an empty file list** (*not* the 404 ADR-0012 originally claimed — corrected there in
  place on 2026-07-29), so it fails through the zero-pages path and reads "This chapter has no pages
  to read." Nothing is actually wrong: the chapter is published on the publisher's site. Fixing it is
  a chapter-list change, not a reader change, and it is cheap — such chapters report `pages: 0` in the
  `/chapter` feed and `ChapterAttributes` (`MangaDexAPI.swift:125-131`) does not decode `pages` yet.
  **This is the most worthwhile follow-up on the reader.**
- **`.task { await vm.begin() }` still has no cancellation story.** Latest-wins makes the *commit*
  correct; the work still runs.

## Facts verified live 2026-07-29 (do not re-derive)

- `GET /at-home/server/{id}` returns **404 `not_found_http_exception`** for a missing chapter (probed
  with a nil UUID and a malformed id; both 404). An **externally hosted** chapter is different: it
  answers **200 with an empty file list** (real `baseUrl`, `data: []`, `dataSaver: []`), so it fails
  through the zero-pages path, not the HTTP one. ADR-0012 originally claimed 404 for both; corrected
  in place. External chapters also report `pages: 0` in the `/chapter` feed, and the app's query
  returns them — it does not pass `includeExternalUrl`, and the default includes them.
- Both sources can return `[]` with no throw — `MangaDexAPI.swift:591`, `WeebCentralSource.swift:87`.
- `permanentStatus(of:)` is `MetadataUpgradeQueue.swift:259-267`: `400..<500` except `429`, `nil` for
  unrecognised error types.
- **`pageOrder`'s `else` branch is reachable only by the two advance-trigger indices** — the extras
  are 0 or 2, so `-2` and `pages.count + 1` are the only fall-through. `Color.clear` was never a
  bounds fallback.
- **`HistoryStore.record` takes `max(first.page, page)`** for the same manga + chapter
  (`HistoryStore.swift:67`), so an over-eager progress reset cannot regress history. The failure mode
  is one-sided: silently *not* recording.
- **Only `MangaDexError.httpStatus` produced developer-facing copy** (`MangaDexAPI.swift:349`); every
  `SourceError` case and `ReaderError.noPages` were already plain English.

## Gotchas (carried forward, all still true)

- **SourceKit is unreliable here** — "No such module 'XCTest'", "Cannot find type 'Chapter' in scope"
  on files that compile and test clean. It was noisy through this whole session. Judge only by
  `xcodebuild`.
- **The `agy` post-commit hook runs its own `xcodebuild`** and holds the DerivedData lock for 2+
  minutes; a concurrent build dies with "database is locked". Gate on
  `until ! pgrep -f "agy --model" >/dev/null; do sleep 15; done`.
- **Do not stack PRs.** Merging a base with `--delete-branch` closes the child unrecoverably.
- **New files in `Models/`, `Services/` and `Views/Components/` need no project edit** — synchronized
  groups. `ReaderBanner.swift` confirmed this again. `Views/` proper and `Manga-ReaderTests/` are not
  synchronized and need `xcp`.
