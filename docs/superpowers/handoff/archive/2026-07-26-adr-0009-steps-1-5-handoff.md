# Session Handoff — 2026-07-26: ADR-0009 written, steps 1–5 of 7 built

**Audience:** a fresh session continuing the upgrade queue. Supersedes
`2026-07-26-adr-0008-and-slice-3-steps-4-5-handoff.md`, which is now merged and historical.

## State

| | |
|---|---|
| `main` | `a7b43b4` — ADR-0008 + ADR-0009 + slice 3 steps 4–5 merged (PRs #21, #22) |
| **`adr-0009-work-weights`** | 5 commits, **unpushed, no PR**. Steps 1–5. |
| **`claude-md-xcp-caveat`** | 1 commit `949431e`, **unpushed, no PR**. Unrelated docs fix. |
| Steps 6–7 | not started |

**248 unit tests pass, 0 failures** (`** TEST SUCCEEDED **`, iPhone 17,
`-parallel-testing-enabled NO`). SwiftLint clean. Working tree clean.

## Read ADR-0009 before writing anything

`docs/adr/0009-upgrade-queue-construction.md`. It exists because ADR-0008 pinned the queue's
*policy* but not what it is wired to, and four of its decisions named values the code could not
supply. Everything below assumes it.

The decisions that shape steps 6–7:

1. **The recommender pushes ordering; the queue never pulls.** `RecommendationEngine.rebuild()`
   hands `profile.workWeights` to `queue.setPriority(_:)`. The queue holds no reference to
   history, library, or the taste store. Pulling would mint Works as a side effect —
   `resolveSignals()` mutates the store (`RecommendationEngine.swift:157-180`).
2. **Poll, don't poke.** One long-lived task, started on `scenePhase == .active`, cancelled on
   `.background`, scanning and sleeping 60s when the scan is empty. The only honest poke site is
   `mint`, which runs on every page turn.
3. **Serial by construction** — one task, one loop, no `TaskGroup`.
4. **`ObservableObject` with zero `@Published`**, same shape as `WorkStore`: it needs
   `@StateObject` ownership in the App struct, and nothing should redraw when it works.
5. **A completed drain does not rebuild the rail.** Output is invisible until pull-to-refresh or
   relaunch. Deliberate (ADR-0008).

## What steps 1–5 built, and the seams they left

Each is one commit on the branch, in dependency order.

| Step | Commit | What it left for step 6 |
|---|---|---|
| 1 | `e094fea` | `TasteProfile.workWeights: [WorkID: Double]` — what `setPriority` receives |
| 2 | `84270b8` | `MALTitleMatcher.bestMatch(sourceTitles:candidates:)` |
| 3 | `5ca1f79` | `MALEntityResolver.malId(for work: Work) async throws -> Int?` |
| 4 | `00a1fd9` | `WorkStore.allWorkIds()`; reindex merges; merge keeps the better snapshot |
| 5 | `64e1b1d` | `UpgradeAttemptMemory` — `record`/`suppresses`/`forget`/`flush` |

**The two signatures step 6 must respect:**

- `MALEntityResolver.malId(for:)` **throws**, unlike the per-Listing method. `nil` means
  *searched, nothing cleared the threshold* → record `.unmatched(work.knownTitles.count)`. A
  throw means *transient* → **record nothing**. Getting this backwards poisons the memory for
  14 days.
- `UpgradeAttemptMemory.suppresses(_ work: Work, now:)` takes the whole Work, so the caller
  cannot pair the wrong title count with the wrong id.

**The eligibility predicate**, which lives entirely in the queue:

```
eligible = (work.snapshot == nil || work.snapshot!.isStale(now: now))
        && !memory.suppresses(work, now: now)
```

**The order of operations inside an upgrade**, which is load-bearing:

1. `resolver.malId(for: work)` — or skip if `work.externalIds.mal != nil`.
2. `works.setExternalIds(ExternalIDs(mal: id, anilist: nil), on: work.id)` — **before** the
   fetch. This may trigger a merge; that is fine and intended.
3. `rateLimiter.run { try await anilist.work(malId: id) }`.
4. `works.apply(result, to: work.id)` — pass the **original** id. `apply` resolves aliases
   (`WorkStore.swift:191`), so if step 2 merged, the snapshot lands on the survivor by itself.
5. `memory.forget(work.id)`.

Writing the id at step 2 rather than after step 3 is what makes step 4 safe: the merge happens
before a snapshot exists, so there is nothing to lose. Deferring it would fire the merge one line
*after* the snapshot was written and eat it.

## Steps 6 and 7

**Step 6 — `Services/MetadataUpgradeQueue.swift`.** Scan (`allWorkIds` → filter → sort by pushed
weights descending, no-weight tail last by `WorkID`), drain, pace with `AniListRateLimiter`. Owns
`AniListAPI`, `AniListRateLimiter`, `MALEntityResolver`, `WorkStore`, `UpgradeAttemptMemory`.

Needs a new test file → **`xcp add-file`** (see the caveat below). It is the only remaining step
that touches `project.pbxproj`.

The genuinely hard part is **testing the drain loop deterministically without wall-clock sleeps**.
Everything else is assembly. Consider injecting the idle interval and a clock; a 60-second
`Task.sleep` in a test suite is not acceptable.

**Step 7 — wiring.** `@StateObject` in `Manga_ReaderApp`, start/cancel next to the existing
`works.flush()` in the `.onChange(of: scenePhase)` block (`Manga_ReaderApp.swift:55-60`), and the
`setPriority` push from `RecommendationEngine.rebuild()`. Small.

## Gotchas found this session

- **Don't read `git diff` right after an `xcp` write.** The reformat CLAUDE.md warns about is
  real, but it is not stable: if Xcode has the project open it rewrites `project.pbxproj` back to
  one-line form on its own schedule, so the same `xcp add-file` shows 31 insertions immediately
  and 4 insertions minutes later with nothing in between having touched the file. Neither
  `xcodebuild build` nor `xcodebuild test` does this. Check `git diff --stat` immediately before
  `git add`. This session got it wrong in the other direction first — saw a clean 4-line diff,
  concluded the caveat had stopped applying, and said so in step 5's commit message; that message
  has since been reworded and CLAUDE.md now documents the instability (merged as #23).
- **`ExternalIDs.absorb` never overwrites a known id** (`Work.swift:52`), so one Work can only
  ever hold one MAL id. A chained merge needs *two providers* (mal + anilist), not two MAL ids. A
  test premised on the latter was written and had to be corrected.
- **The candidate pool must be sorted before matching.** `MALEntityResolver` sorts by `malId`
  because dictionary iteration order is randomized per process and `bestMatch`'s sort is not
  stable — tied candidates would otherwise resolve differently between launches.
- **`allWorkIds()` order is unspecified** for the same reason. The queue must sort.
- **SourceKit false alarms remain constant** ("No such module 'XCTest'", "Cannot find type
  'WorkID' in scope"). Judge only by `xcodebuild`.
- **The `agy` post-commit hook makes `git commit` take >2 minutes.** Run commits with
  `run_in_background: true` or they time out.

## TDD note, stated honestly

Only steps 1, 3, 4 and 5 had a genuine red phase, and step 4's was the only *behavioural* one —
the ADR-0008 Solo Leveling trace failed on four assertions before the fix. Elsewhere the first
test per step was red because the method did not exist yet, and the remaining tests were written
after the implementation as regression guards. The commit messages say which is which. Step 6 is
new behaviour and genuinely wants red-green.

## Model note

Step 6's difficulty is deterministic async testing, not design — ADR-0009 already pinned the
design. Continuity matters more than raw reasoning here, so it does not obviously want a fresh
agent. If the drain-loop test resists, *that* subtask is well-isolated enough to dispatch on its
own.
