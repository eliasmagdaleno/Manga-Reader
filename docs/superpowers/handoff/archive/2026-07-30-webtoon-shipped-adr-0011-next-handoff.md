# Session Handoff — 2026-07-30: webtoon resume shipped to PR #31, ADR-0011 is next

**Audience:** the next session. The reader work is *done and deliberately parked*; the live
thread is the recommender.

Supersedes `2026-07-29-webtoon-resume-position-handoff.md` for **state**. That file stays as the
record of *why* the reader looks the way it does — its account of the two grilling sessions, the
`xcp` technique that worked, and the migration lesson about defaulted non-optional fields are not
repeated here. It also still holds the full hand-check list, which is the one thing from it that
is still owed.

Supersedes `2026-07-29-anilist-pool-handoff.md` for **its blocker**, which is now resolved — see
*Verified live today*. Its slice plan for ADR-0011 is unchanged and still the plan.

## State

| | |
|---|---|
| `main` | `bd0d678` — PR #30 merged (ADR-0012, ADR-0013) |
| Working branch | `webtoon-resume-position` at **`94b3dc4`**, pushed, tree clean |
| **PR #31** | **open, MERGEABLE.** SwiftLint green; "Build & unit tests" was still pending when this was written — check before merging |
| Unit tests | **362 pass, 0 failures** (iPhone 17, `-parallel-testing-enabled NO`) — was 335 |
| ADRs | 0007–0014 accepted; **next free number is 0015** |
| Device | iPhone 16 Pro `BE0AB07B-8A4E-5D2C-A674-5698010C4D27`, connected. The user tests on **hardware**, not the simulator |

## Pick up here

### 1. Merge PR #31 once its build check is green

`gh pr merge 31 --squash --delete-branch`. Do not stack anything on this branch — merging a base
with `--delete-branch` closes the child unrecoverably.

### 2. Implement ADR-0011 — the AniList ranked-tag pool

Branch off the updated `main`. The slice order is the one
`2026-07-29-anilist-pool-handoff.md` set, unchanged:

1. **Tag vocabulary cache** — `category` lives there, never on the `Work`.
2. **Pair seeding** — top 5 co-occurring pairs by `Σ engagement × min(rank_a, rank_b)/100`,
   `minimumTagRank: 60`, excluding `Technical` and `Cast-Main Cast`.
3. **The provider + its read-through cache** — never blocks the rail.
4. **Fold into `CompositeCandidateProvider`** and diff
   `Manga-ReaderTests/__Goldens__/foryou-ranking.txt`.

Step 4 stays **last and alone**: ADR-0011 keeps "recover MangaDex's free list-endpoint tags" as
separate unclaimed work precisely so a golden diff has exactly one cause
(`0011-ranked-axis-generation.md:95`).

Two facts from the ADR-0011 grilling, **do not re-derive**: `tag_in` is **AND, not OR** (which is
why a pair at rank ≥ 80 is frequently empty and the threshold is 60), and candidates carry **no
tags at all** (`MangaDexAPI.swift:13-22`) — the reason the axis pays off as *generation on
AniList* rather than as scoring on MangaDex results.

**Worth a look during slice 2, before anything is wired:** the user's tag distribution is
lopsided (see below). The top-5 pairs will be dominated by three or four titles, so the seeded
pairs are worth eyeballing for "does this look like the user's taste" before step 4's golden diff
bakes them in.

## Verified live today (2026-07-30) — do not re-derive

**The ADR-0011 library-seeding blocker is resolved.** The previous handoff called it "the actual
blocker, and it is not a coding task" — the store sat at 1 AniList-resolved Work against a gate
of 3. Pulled from the user's device and run through `scripts/queue-status.sh`:

```
22 works, 14 resolved to AniList
AniList pool gate (needs 3): PASS
suppressed by attempt memory: 8 (8 unmatched)
```

Berserk `ranked=66`, Vagabond 29, One-Punch Man 26, Iruma-kun 21, Eleceed 17 — but also Hidarikiki
no Eren 3 and Sexual Hunter Riot 2. The 8 suppressed are doujin titles that genuinely are not on
MAL; the queue is right to have stopped asking. Store last written 2026-07-29 17:20 PDT, so the
queue has not drained since — relaunch the app after adding titles.

**How to read the real store.** The simulator is useless for this: its `Application Support` has
**no `works.json` at all**, and its `history.entries` contains nothing newer than 07-17 and no
entry carrying a `fraction`. Checking the gate against a simulator would have reported failure.

```sh
xcrun devicectl device copy from --device BE0AB07B-8A4E-5D2C-A674-5698010C4D27 \
  --domain-type appDataContainer --domain-identifier Elias-Magdaleno.Manga-Reader \
  --source "Library/Application Support" --destination <dir>
./scripts/queue-status.sh <dir>/works.json
```

## What shipped on `webtoon-resume-position`

Four commits today, on top of the three already there.

- **`15cdc40`** — a second grilling session closed five holes in ADR-0014, all in capture, all
  amended into decisions 5, 8, 9 and 10 and labelled *(second grill)* to keep them apart from the
  first round's, which share their date. Index of the five is in the older handoff.
- **`e1bbe13`** — capture. `stripPosition` + `recordAction`, 13 tests; `StripMetrics`; per-strip
  `(frame, isDecoded)` through a `PreferenceKey`; the `.onAppear` advance and the view-side latch
  deleted; `advanceProgress(to: Int)` → `recordProgress(_: ReadingPosition)`.
- **`659abf1`** — restore. `settleStep` + `StripAnchor`, 9 tests, the anchor grid, the settle loop
  with step zero replacing ADR-0013's fixed 50ms sleep.
- **`94b3dc4`** — two defects found by the user **on a device**, both fixed with a regression test:
  chapter advances left the reader at the bottom of the chapter they just left (a `ScrollView`
  keeps its content offset when the pages under it are replaced), which put the end-of-chapter
  loader back on screen and **skipped several chapters in a row**; and `restoreTarget` used
  `progressChapterID` to detect whether `didCompleteLoad` had run, but `init` seeds that with the
  chapter id, so on a first open it matched before anything had run.

Every pure function was confirmed red before it was made green, including by stubbing an
already-written implementation back out. The chapter-skip regression is pinned exactly: reverting
`restorePlan` to the old behaviour fails one test and nothing else.

## Deliberately deferred — the user's call, not oversights

- **All eight hand-checks.** The user chose to defer them ("let people report those as bugs later
  when I decide to release"). The list is in
  `2026-07-29-webtoon-resume-position-handoff.md`. What this actually leaves unverified: the unit
  tests establish the *decisions*, not the *measurement*. In particular **nothing has confirmed
  that `.coordinateSpace(.named(…))` on the `ScrollView` yields viewport-relative frames** — if it
  does not, every fraction is meaningless and resume silently does nothing. It would be obvious on
  the first webtoon. Also unverified: whether the anchor grid swallows the chrome-toggle tap
  (`allowsHitTesting(false)` is supposed to prevent it), and cold-cache settle timing.
- **`isDecoded` is `.success` only.** A strip that *failed* to load therefore never reports a
  position, and a chapter whose **last** strip is broken can never be marked `finished` — the
  past-the-end fallback holds the last *decoded* strip, one short of `pageCount - 1`. Faithful to
  what was decided; the open question is that a failed strip's 460pt height is *settled*, which is
  arguably what the gate is really asking. One line to change
  (`if case .empty = phase { false } else { true }`), costs only the retry case.
- **The `page 5/5` report is unresolved.** The user saw a webtoon chapter recorded as finished
  when it was not. It is on the device, which cannot be inspected retroactively, and no simulator
  entry carries a `fraction` — so nothing there was written by the new capture. Most likely the
  old `.onAppear` rule, whose worst case is exactly a short webtoon: five 460pt placeholders fit
  inside a `LazyVStack`'s realization window, so it marks itself finished before any scroll. **The
  experiment that settles it:** on a current build, read one strip, back out, look at History —
  expect `1/N`. If it still reads `N/N`, the suspect is `stripPosition`'s past-the-end fallback
  firing when the covering row is momentarily absent from `frames`, and it should be instrumented
  rather than guessed at. Note that `record`'s max means **the existing bad entry never heals** —
  delete that History row before retesting.
- **One unexplained test failure.** A single full-suite run reported 1 failure of 362 and the test
  name was not captured; three subsequent runs were clean. The failing run took 22.6s against ~7s
  for the others, which smells like a timeout flake rather than anything in this branch —
  unresolved rather than dismissed.

## Gotchas (carried forward, all still true)

- **`xcp` reformatted `project.pbxproj` in the collapse direction again**, stripping
  `lastKnownFileType`/`name` from four unrelated `PBXFileReference` entries. A scripted
  find-and-restore of those four lines is faster than the backup dance; `git diff --stat` must
  read `4 ++++` immediately before `git add`.
- **SwiftLint (via the `agy` hook) deletes an explicit memberwise init** that matches the
  synthesized one — it did this to `StripFrame` *after* the commit landed, leaving the tree dirty.
  Expect it, and `--amend`.
- **The `agy` post-commit hook holds the DerivedData lock for ~2 minutes.** Every `git commit` here
  times out the shell at that point; the commit itself has already succeeded. Verify with
  `git log`, and gate any build on `until ! pgrep -f "agy --model" >/dev/null; do sleep 15; done`.
- **Do not stack PRs.** Merging a base with `--delete-branch` closes the child unrecoverably.
- The **5 remaining SourceKit errors are noise** ("No such module 'XCTest'", "Cannot find type
  'Manga' in scope") on files that compile and test clean. Judge only by `xcodebuild`.
- A full `xcodebuild test` cycle is ~90s including the build; budget for it in red-green loops.

## Still-open threads (older, none blocking)

- **Externally hosted chapters are reported as broken** — they answer `/at-home/server` with 200
  and an empty file list. `ChapterAttributes` (`MangaDexAPI.swift:125-131`) does not decode
  `pages` yet; one field would let the chapter list mark the row before anyone opens it. Still the
  most worthwhile reader follow-up.
- **The 5xx wording** — `readerFailureMessage` rewrites every `MangaDexError.httpStatus` to "This
  chapter isn't available to read from this source", so a transient 503 gets that sentence next to
  a Retry button.
- **`HistoryStore.save()` is an all-or-nothing re-encode** of 500 entries plus read marks. The
  ADR-0014 throttle makes it survivable, not cheap.
- Extending More Like This reverse-resolution beyond MangaDex-only; adding `malId` to
  `LibraryItem` so saved seeds skip the title search.
