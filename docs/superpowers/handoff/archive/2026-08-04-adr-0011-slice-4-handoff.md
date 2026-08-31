# Session Handoff — 2026-08-04: ADR-0011 slice 4 shipped; the device check is the only thing left

**Audience:** the next session. Supersedes `2026-08-04-adr-0011-slice-3-handoff.md` for **state**
only — its **gotchas still apply verbatim**, and behind it
`2026-07-30-webtoon-shipped-adr-0011-next-handoff.md` still holds the **eight deferred hand-checks**
and the **`page 5/5` false-finish experiment**, neither touched by this work.

**ADR-0011 is now feature-complete.** All four slices are in. What remains is verification and a PR,
not design.

## State

| | |
|---|---|
| `main` | `80bd1f6` — unchanged |
| Working branch | **`anilist-ranked-pool`** at **`16f3431`**, tree clean, **15 commits ahead of `main`, not pushed, no PR** |
| Unit tests | **417 pass, 1 skipped, 0 failures** — was 416. The skip is `TagPairSeedingDiagnostic`, by design |
| ADRs | 0007–0014 accepted; 0011 **amended again today for slice 4**; next free number is still **0015** |
| Device | iPhone 16 Pro `BE0AB07B-8A4E-5D2C-A674-5698010C4D27` |

## What shipped — read the commits, not a summary of them

Four commits, deliberately shaped. `git log 9dac7db..HEAD` and read the messages; each carries its
own argument and they are not restated here.

| | |
|---|---|
| `99d306d` | `Resolve` takes `[AniListWork]`; new `MoreLikeThisProvider.resolve(works:limit:)` |
| `f32d2f0` | Composite gains `ani:` + `wAniList = 0.6`; agreement generalized to n pools |
| `d4d676e` | The four golden fixture cases |
| `16f3431` | Composition root, launch kick, ADR-0011 amendment, glossary |

The design record is **ADR-0011's four new `###` sections plus one new hazard**
(`docs/adr/0011-ranked-axis-generation.md`, everything marked *Amended 2026-08-04, implementing
slice 4*). Ten decisions were grilled this session; all of them are there with the rejected
alternative and the argument that beat it. **Do not re-derive them.**

### The one thing worth repeating, because it is the instrument

The golden was regenerated **twice, in two separate commits**, and that split is the whole reason
the file is worth anything now:

- `f32d2f0` added the third slot with **no AniList candidates**. The regenerated golden showed only
  a new header and column — **every `agree` and `final` byte-identical, zero rank movement.** That
  is ADR-0011's claim that the generalized geometric mean reduces to `√(tag·mal)` at n=2, proven as
  an artifact instead of inferred from unchanged rows in a busy diff.
- `d4d676e` then added the data, so every moved number has exactly one possible cause.

In the current golden, **Crimson Vow's `agree` staying `0.2500` at n=3** — not 0.75 — is the
rejected pairwise-sum alternative, visible as a single cell.

## Pick up here

### 1. The live two-run device check — blocking, and it is the only detector

`ADR-0011`'s new hazard says it plainly: **nothing automated proves `Manga_ReaderApp.init` hands the
provider *single* long-lived store instances.** The seam test
(`AniListPoolTests.testTheAniListPoolReachesTheComposite`) covers provider→composite; the
composition root is not testable without duplicating the wiring, which would assert the copy.

Run the app, cold. **With the launch kick in place the AniList pool should appear on the *second*
launch.** A third empty run means the capture is wrong and a fresh `AniListPoolStore` is being built
per rail build.

**This number matters more than it looks.** The slice-3 handoff primed its reader to *expect* an
empty first run, which is exactly the expectation that could absorb a real bug. Two is the expected
number now, not "a couple".

Note `RecommendationEngine.load()` is `guard !loadedOnce` — "a build" means an **app launch or a
deliberate pull-to-refresh**, not a tab switch. Tab-switching will never advance the count.

### 2. Read the agy reviews — they never ran, or never wrote

**`.agy_code_review.md` is stale.** It is still the review of `9dac7db` (the pre-session commit),
timestamped 09:41, and contains a `...waiting for task completion...` line. All four of this
session's commits printed `🤖 [AGY] Triggering...` and **none of them overwrote the file.**

So: either the hook is failing silently, or four reviews are queued somewhere. Worth diagnosing
before trusting the hook again — `2026-08-03-agy-hook-issues.md` is the prior investigation. The
slice-3 handoff's caveat also still stands: trust its pass/fail numbers, read the diff for what
actually changed.

### 3. Then open the PR

One PR of the whole branch to `main`. **Do not stack** — merging a base with `--delete-branch`
closes the child unrecoverably and it gets no CI anyway. CI on `main` builds and runs unit tests, so
the golden runs there; the device check above is a human step **before** opening, not something CI
can do.

## Deliberately still parked

Unchanged by this work, and all argued in ADR-0011 — do not "tidy" these without reading why:

- **`MALReverseResolver`**, the shared extraction collapsing `MoreLikeThisProvider.resolve` and
  `recommendations(for:)`. Now genuinely worth doing — slice 4 duplicated ~25 lines of
  cache-partition/batch-fetch assembly between them — and the golden is finally in place to prove
  nothing moved.
- **`CachedJSONFile<T>`** to collapse `AniListPoolStore`/`TagVocabularyStore` boilerplate, and a
  **`PoolScorer`** value carrying `(contributions, weights)` together.
- **Widening `MoreLikeThis.pickMatch` to take multiple titles.** `AniListWork.knownTitles` carries
  romaji/english/native/synonyms but only the primary reaches the matcher — recorded as a residual
  in ADR-0011. This was a **correction to a wrong claim made during design**; the `Resolve` reversal
  is still right on its cost argument, but the "richer left-hand side" benefit is not real yet.
- **`wAniList = 0.6`** stays until the golden and a real device say otherwise. The composite's
  constants are injectable for exactly this.

## Older open threads (none blocking)

Unchanged: the **eight deferred hand-checks** (load-bearing one: whether `.coordinateSpace(.named(…))`
yields viewport-relative frames — if not, every webtoon resume fraction is meaningless); the
**`page 5/5` false-finish** experiment; **externally hosted chapters** reading as broken because
`ChapterAttributes` doesn't decode `pages` (`MangaDexAPI.swift:125-131`); the **5xx wording** in
`readerFailureMessage`; and **decoding MangaDex's free list-endpoint tags** — which was gated on
"once the AniList pool has been through a golden diff", and that gate is now open. ADR-0011's
revisit trigger applies: if the tag pool stops being provenance-only, the two pools stop being
independent and the agreement term needs re-examining.

## Suggested skills

- **`superpowers:verification-before-completion`** — for the device check. It is the entire
  remaining risk on this branch and the temptation is to declare it fine because the tests are
  green. Evidence before assertions.
- **`run`** — to launch and drive the app for that check.
- **`superpowers:systematic-debugging`** — if the pool does *not* appear on the second launch, or
  for the agy hook not writing its file. Both are "unexpected behaviour", not design questions.
- **`superpowers:finishing-a-development-branch`** — once the device check passes, for the PR.
- **`grill-with-docs`** — only if a *new* fork appears. Slice 4's decisions are settled and recorded;
  re-grilling them would be re-litigating.

Not needed: `brainstorming`, `writing-plans`, `domain-modeling`. ADR-0011 is complete and the
glossary is current.

## Update — 2026-08-04, later session

A grilling session resolved items 2 and 4 below and added one commit. **Sections 2 and "Deliberately
still parked" are amended by this; read this first.**

### The agy hook was not broken — it was four reviews fighting

Diagnosed. `.agy_code_review.md` was stale because `agy` **failed on the last four commits**, and the
hook's fail-safe correctly kept the good review rather than overwriting it with junk. The stale file
is a *complete* review of `9dac7db` — header, body, and the `# agy review complete — exit 0`
terminator. Nothing was lost.

Cause: commits landed at 10:34, 10:44, 10:48, 10:52 — four in 18 minutes, each detaching an `agy`
that runs a full `xcodebuild test` under a 20m timeout. Every run after the first collided with one
already holding the build database lock. `9dac7db` is in the file because it is the only commit that
ran alone (55 quiet minutes after it). **The hook wrote `.agy_review_running` but never read it** —
the prior investigation's Issue 5 fix published the lock for others and ignored it itself.

Fixed in `.git/hooks/post-commit`: an atomic `noclobber` lock acquisition that exits 0 if a review is
already running, plus a 25m stale-lock reap (> the 20m timeout, so it can never kill a live run). A
burst of commits now yields one review instead of N failures. **This file is not version-controlled
and rides in no commit** — it exists only on this machine, and a fresh clone will not have it.

Rejected: *queue-on-exit* (re-run against the new `HEAD` when the current review finishes) would
review the **last** commit of a burst rather than the first, which is the one you actually want — but
it needs real stale-lock handling and was out of scope for a timeboxed, non-blocking diagnosis. It is
the better behaviour if this ever annoys you.

### The tag-decoding gate is closed again — do not read "gate open" as a green light

`04c1073` amends ADR-0011's first revisit trigger. Section "Older open threads" below says decoding
MangaDex's free list-endpoint tags "was gated on the AniList pool having been through a golden diff,
and that gate is now open." **True, and not sufficient.** The ADR now says so in place.

The binding condition is independence: decoding those tags takes the tag pool off provenance-only,
and the two pools stop being independent observers. The agreement term rewards independent
convergence, so over correlated pools it inflates confidence rather than measuring it — and **the
golden cannot adjudicate that.** It pins outputs; every output would move, each move would have a
plausible story, and the broken invariant is statistical. Reopen the agreement term first, as its own
decision. This applies to a provenance-only decoding too unless scoring genuinely never reads it.

### Also settled, not yet done

- **`MALReverseResolver` lands after the merge, not on this branch.** The extraction is worth doing
  and the golden is in place to prove it moved nothing — but the branch's riskiest claim is the
  untestable one (single long-lived stores), and touching `recommendations(for:)` gives a failed
  device check two candidate causes instead of one. That single-cause property is what the two-commit
  golden split bought; do not spend it on a 25-line cleanup that is not decaying.
- **The device check's gate is the on-disk pool cache, not the rail.** The hazard is object identity,
  and a rail blended at `wAniList = 0.6` can move subtly enough that reading rank order off a
  screenshot proves nothing either way. Populated store after run one, candidates flowing on run two.
  Screenshot the rail as corroboration only.

## Gotchas

All of the slice-3 handoff's still apply. Confirmed again today:

- **SourceKit errors are noise** — "Cannot find type 'Work' in scope", "No such module 'XCTest'" on
  files that compile clean. Judge only by `xcodebuild`. This fired constantly this session.
- **The `agy` hook runs `xcodebuild` and holds the build lock.** Check `.agy_review_running` before
  starting a build or you get "database is locked".
- **`project.pbxproj` churn was avoided entirely this session** by putting the new seam test in the
  existing `AniListPoolTests.swift` rather than a new file. Keep doing that — it is the single
  biggest time sink on this repo, and one test does not justify the four-entry dance.
- Regenerate the golden with `TEST_RUNNER_REGENERATE_GOLDENS=1`. The `TEST_RUNNER_` prefix is
  required and stripped by xcodebuild; a bare `REGENERATE_GOLDENS=1` is silently ignored.
- Full `xcodebuild test` including UI targets takes **>10 minutes** and will blow a 600s tool
  timeout. Run `-only-testing:Manga-ReaderTests` (~15s) during iteration; run the full suite in the
  background before the PR.
