# Session Handoff — webtoon resume position (ADR-0014 written, step 2 committed, step 3 designed)

**Audience:** the next session, continuing on `webtoon-resume-position`.
**Updated 2026-07-30** after a grilling session that settled six implementation questions the ADR
left open — see *Decided 2026-07-30*. Those decisions are **not yet in ADR-0014**; writing the
amendments is the first task below.

**This file replaces the design handoff that was here.** The design now lives in **ADR-0014**, which
is authoritative and contains one correction the old handoff got wrong (see *What implementation
changed about the design*). Read the ADR, not a summary of it.

## State

| | |
|---|---|
| `main` | `bd0d678` — PR #30 merged, ADR-0012 + ADR-0013 |
| Working branch | `webtoon-resume-position` at **`5cbd41d`**, steps 1–2 committed, **tree clean, nothing pushed** |
| ADR | `docs/adr/0014-resuming-a-webtoon-where-the-reader-stopped.md`, 12 decisions |
| Tests | **340 green, 0 failures** (329 unit + 11 UI), verified on the commit |
| Next ADR number | 0015 |

`5cbd41d` — *"Record a reading position, not just a page (ADR-0014, steps 1-2)"* — carries
`ReadingPosition`, its 12 tests, ADR-0014, the whole `HistoryStore` change, `history.flush()` on
`.background`, the 24 migrated `record()` call sites, the ADR-0013 amendments and the glossary terms.
The `agy` hook wrapped two over-long JSON literals in `ReadingPositionTests.swift` for SwiftLint;
that was verified and `--amend`ed in, which is why the SHA is `5cbd41d` and not the `da16b42` the
hook's own log names.

The `pbxproj` in that commit is **exactly the 4 lines the new test file needs** — the `xcp` noise
(three stripped `PBXFileReference` attributes, the synchronized-group reflow) was reverted by
restoring the committed file and re-adding the four entries by hand.

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

## Decided 2026-07-30 (grilling session) — not yet in the ADR

Six answers to questions ADR-0014 left open. **Each of these is confirmed by the user.** Where one
changes something the ADR states, the amendment is named — write those amendments *before* the code,
so the ADR never lags the branch.

**1. A clamped page drops its fraction.** `landingIndex` becomes
`landingPosition(_:pageCount:) -> ReadingPosition` and, whenever the clamp *moves* the page (saved
page 7 against a chapter that now returns 5 pages, or a negative page), the fraction resets to 0.
The fraction survives only when the page comes through untouched. Rationale: `pageCount` changing
means the strips were re-cut, so the ratio maps to nothing — and ADR-0014 decision 1's accepted cost
already names a stale pair as resuming "at a plausible-looking wrong place", which is harder to
notice than resuming at zero. Wants a test named after the clamp.

**2. `ResumeAction.reread` loses its payload — `case reread(Chapter)`.** Its `page:` was inert:
`MangaDetailView.swift:473` maps `.reread` to page 0, and nothing else reads it, so the enum
documented behaviour the app does not have. `.start` and `.next` already carry a chapter alone.
Two test assertions change (`ReadingPositionTests.swift:148`, `Manga_ReaderTests.swift:157`).
→ **Amends ADR-0014 decision 4**, which lists `.cont`/`.reread` as both carrying a position.

**3. Strip measurements live in a non-observable box, not `@State`.** A `PreferenceKey` per realized
row transports frames; `.onPreferenceChange` merges them into

```swift
final class StripMetrics {          // deliberately NOT ObservableObject
    var frames: [Int: CGRect] = [:] // realized strips, reader coordinate space
    var viewport: CGRect = .zero
    var live: ReadingPosition?
}
@State private var metrics = StripMetrics()   // reference never reassigned ⇒ no invalidation
```

Rationale: nothing on screen renders the live position (`pageIndicator` is `mode.isPaged`-only,
`ReaderView.swift:116`), so a `@State` write per scroll frame would re-evaluate the reader's body —
with N=50 anchor views per realized strip — for no rendered benefit. Preference callbacks fire
outside the update cycle, so there is no "modifying state during view update", and both the settle
loop and the throttled `record` read the box directly and always see the newest measurement.
`onGeometryChange` would be tidier and is iOS 18; the target is 17.5.
→ **Amends ADR-0014 decision 8's mechanism only.** Its substance is unchanged: the live position
lives in the *view*, not the view model, and restore prefers it over `pagerTarget`.

**4. Capture's three holes, all in the pure function, all decided:**

- **Viewport top past the last strip** (interstitial, end mark, the 50pt loader at
  `ReaderView.swift:274-286`) → fall back to the **last measured strip, fraction clamped just under
  1**. Costs nothing for completion (`finished` only asks `page >= pageCount - 1`, already satisfied
  on entering the last strip) but keeps the value monotone as the reader scrolls off the end.
- **Overscroll above the first strip** → `(0, 0)`. Rubber-band is not a position.
- **Nothing measured yet** → **`nil`, record nothing.** An unmeasured strip is unknown, not "the
  top"; writing `(0, 0)` would be harmless only because `record` is monotonic, which is the wrong
  reason for a capture function to be correct.

`[0, 1)` is enforced where the value is *made*, because restore computes `slot = Int(f · N)` and
`f == 1.0` addresses slot 50 in a `0..<50` grid. Restore clamps too, as a backstop.

**5. The view's throttle gets a trailing fire, and the reader records on disappear.** This is the
one real *gap* found in ADR-0014 rather than an unwritten detail. Decision 5 says the reader needs no
`scenePhase` code because `history.flush()` covers backgrounding — but that only holds if the store
already has the final position, and with a leading-edge-only view throttle it does not:

> Scroll for 30s, last tick fired 0.9s ago at 55% down strip 5, stop at 62%, read the screenful for
> two minutes, background the app. `flush()` faithfully writes 55%. Nothing ever writes 62%.

Scroll-then-stop-then-leave is the normal shape of reading, so the trailing value is the one that
matters most.

- **(a)** Leading edge records immediately; if more measurements arrive inside the window, **one**
  catch-up record is scheduled at the window's end with the latest value. This is **not** the
  debounce trap decision 5 rejected — the trailing fire is pinned to a fixed window end and never
  pushed out, so the maximum gap stays ~1s however long the scroll runs.
- **(b)** `onDisappear` records the live position, guarded by the same
  `progressChapterID == vm.currentChapter.id` check the throttled path uses. It fires on the pop and
  on a reading-mode switch, and it is required because a `.task`-scoped trailing timer dies with the
  view — it covers "stop scrolling, immediately tap ✕", which (a) alone leaves up to a second short.

With (a) in place the reader still needs no `scenePhase` code: ≥1s after the last scroll the store
already holds the final position.
→ **Amends ADR-0014 decision 5**, which currently reads as though one throttle shape covers both
layers. The store's non-re-arming shape is exactly the wrong thing to copy into the view.

**6. The settle loop's threshold is the grid's own resolution.** With
`residual = (stripTop + f · stripHeight) − viewportTop`:

- **Stop when `0 ≤ residual < slotHeight`**, `slotHeight = stripHeight / N`. Anything tighter cannot
  be satisfied — the grid only addresses multiples of `slotHeight` (~60pt on a 3000pt strip) — so it
  would burn the whole budget on every restore and stop anyway.
- **Overshoot (`residual < 0`) always gets another attempt**, aiming one slot earlier. This is what
  makes ADR-0014's "the residual lands behind the reader" true by construction.
- **Budget: 10 attempts.** Per-attempt wait: poll until the target strip's measured frame changes,
  or ~50ms. Step zero is "wait until the target row is realized and measured at all", capped at
  ~1.5s — this **replaces** ADR-0013's fixed 50ms sleep rather than sitting beside it.

Deriving the threshold from `N` keeps the two constants from drifting: raise `N` and the stopping
rule tightens automatically.

**Placement:** a new `Models/WebtoonGeometry.swift` holds `StripAnchor`, the capture function
(`stripPosition(frames:viewport:) -> ReadingPosition?`) and `settleStep(...) -> StripAnchor?`.
`Models/` is synchronized so it needs no `pbxproj` edit; its test file does, via `xcp`. The precedent
is `Models/ReaderPresentation.swift` — the reader's pure pieces, lifted out of the view to be tested.

### Still open — the grill stopped here

- **Does `pagerTarget`'s retreat carry a fraction?** `retreatIndex` returns an `Int`
  (`ReaderViewModel.swift:200-206`). Leaning: no — `ReadingPosition(page: retreat)`, fraction 0.
  A failed advance never scrolls the vertical reader (`.task(id:)` is guarded on
  `errorMessage == nil`), and restore prefers the live position anyway, so the fraction would be
  unobservable.
- **`continueProgress`'s exact formula** (ADR-0014 decision 12). `(page + fraction) / pageCount`
  with a paged entry's `fraction == 0` treated as "page seen" — the entry does not record which mode
  it was read in, so `fraction == 0` is genuinely ambiguous. Leaning:
  `min(1, (Double(page) + (fraction > 0 ? fraction : 1)) / Double(pageCount))`.
- **Does `didCompleteLoad` still call `record` after the latch is deleted?** It currently does
  (`ReaderView.swift:140`), which is what records page 0 of a freshly opened chapter.
- **Slicing and PR shape** for steps 3–5 — one PR with a commit per step is the assumption
  (no stacked PRs), but the TDD order inside step 4/5 is not planned yet.

## Left to do, in order

0. **Write the six amendments above into ADR-0014** (decisions 4, 5, 8 by name) and the glossary
   where it is affected, before touching code.

3. **Plumbing** — carry `ReadingPosition` end to end, TDD where it is pure:
   - `ResumeAction.cont` carries a position, not a page; `.reread` **loses its payload entirely**
     (`ReadingResume.swift:52`, `:69` — see *Decided* 2)
   - `ReaderView.init` and `ReaderViewModel.init` take a position instead of `initialPage`
     (`ReaderView.swift:56`, `ReaderViewModel.swift:73`); `Landing.exact` carries one, and
     `landingIndex` becomes `landingPosition` which **zeroes the fraction on a clamp**
     (see *Decided* 1)
   - `pagerTarget` becomes a `ReadingPosition` (`ReaderViewModel.swift:52`) — expect ~13
     `ReaderViewModelTests` assertions to need updating
   - `HistoryView.swift:66` passes `entry.position`
   - **the row-tap doors**: `ChapterListView.swift:34` and `MangaDetailView.swift:411` pass
     `history.entry(forChapter:)?.position` (ADR-0014 decision 11)
   - `continueProgress` → `(page + fraction) / pageCount`, treating a paged entry's `fraction == 0`
     as "page seen" so paged progress does not shift down a page (`MangaDetailView.swift:211-215`)
4. **Capture + live position in `verticalReader`** — `GeometryReader` per realized row reporting
   through a `PreferenceKey` into `StripMetrics` (*Decided* 3), viewport-top fraction clamped to
   `[0,1)` with the three holes of *Decided* 4, a ~1s **throttle with a trailing fire** plus a
   record on `onDisappear` (*Decided* 5), pending update **dropped** on chapter change via
   `progressChapterID` (`ReaderView.swift:134`). **Delete `advanceProgress`'s latch and the
   `.onAppear` advance for `.vertical` only** (`ReaderView.swift:188-195`, `:272`) — paged modes keep
   `onChange(of: currentPage)`.
5. **Restore** — anchor grid (`N = 50`, `Color.clear` slices, **`allowsHitTesting(false)`** or it eats
   the chrome-toggle tap) + the settle loop, stopping rule per *Decided* 6. It is a **pure function,
   unit-tested** against: strip shorter than viewport, fraction 0.99, measurement that never
   stabilises, target row not realized. Replace the guard `vm.pagerTarget > 0` with
   `page > 0 || fraction > 0` (`ReaderView.swift:305`) and **delete the 50ms sleep** (`:309`).
6. **Hand-checks** — resume mid-strip; after rotation; images all disk-cached vs all cold (the two ends
   of the settle loop's timing); mode switch mid-chapter; paged modes unaffected; row tap resumes.

## Hazards

- **`xcp` reformatted `project.pbxproj` in the *opposite* direction to what CLAUDE.md documents.** This
  time it **collapsed** the three `PBXFileSystemSynchronizedRootGroup` entries to one line each *and*
  stripped `lastKnownFileType`/`name` from three unrelated `PBXFileReference` entries. Net 10
  insertions / 30 deletions, of which only **4 lines** are the new test file. The lesson from
  CLAUDE.md holds and generalises: **inspect the pbxproj diff immediately before `git add`, and do
  not assume which direction the reformat went.**
  **What worked (2026-07-30):** `git checkout -p` is unusable here — one hunk mixes the new
  `PBXFileReference` with two stripped ones. Instead: back the file up, `git checkout --` it, then
  re-add the four entries (`PBXBuildFile`, `PBXFileReference`, the group child, the `Sources` build
  phase) by copying `xcp`'s own lines out of the backup. `git diff --stat` then reads
  `4 ++++`, and the target built and tested clean.
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
