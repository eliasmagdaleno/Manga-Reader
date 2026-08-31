# Session Handoff — 2026-08-03: ADR-0011 slice 2 shipped, slice 3 (the provider) is next

**Audience:** the next session. Supersedes `2026-08-03-adr-0011-slice-1-handoff.md` for **state**
only — that file's *three judgment calls* about the vocabulary cache are still live and slice 2 was
built to honour them. It in turn points at `2026-07-30-webtoon-shipped-adr-0011-next-handoff.md`,
which still holds the **eight deferred hand-checks** and the **`page 5/5` false-finish experiment**.
Neither is affected by this work.

## State

| | |
|---|---|
| `main` | `80bd1f6` — unchanged this session |
| Working branch | **`anilist-ranked-pool`** at **`412072c`** (docs-only, 2026-08-04), tree clean, **not pushed, no PR yet** |
| Unit tests | **389 pass, 1 skipped, 0 failures** — was 373. The skip is the diagnostic, by design |
| ADRs | 0007–0014 accepted; 0011 **amended in place today**; next free number is **0015** |
| Device | iPhone 16 Pro `BE0AB07B-8A4E-5D2C-A674-5698010C4D27` |

## What shipped — slice 2, pair seeding (`d945315`)

`Models/TagPairSeeding.swift` (new, auto-compiled — `Models/` is synchronized) plus
`Manga-ReaderTests/TagPairSeedingTests.swift` (15 tests + 1 diagnostic; needed an `xcp` entry).

- **`TagPair`** — `Hashable`, canonicalises by sorting its two names on init.
- **`SeededTagPair`** — pair + weight. The weight travels with the pair on purpose: slice 3 weights
  its results by it and slice 4's golden is far more readable with the number visible.
- **`seedPairs(works:weights:vocabulary:limit:excludeAdultTags:)`** — pure, synchronous, ADR-0011's
  formula exactly.
- **`minimumSeedTagRank = 60`**, **`seedExcludedTagCategories = [Technical, Cast-Main Cast,
  Demographic]`** — both file-scope so slice 3 and the golden can name them rather than re-type 60.

### Decisions made this session — do not silently reverse

All six are now written into ADR-0011 (amended in place, see its `Measured 2026-08-03` block and the
amendment under the seeds decision). The two that are easiest to undo by accident:

1. **The seeder takes `workWeights`, never a `TasteProfile`.** It is structurally unable to compute
   engagement, which is ADR-0009's rule enforced by signature rather than by comment. If slice 3
   finds it convenient to pass the whole profile, that is the regression.
2. **Exclusions are a deny list.** `category(of:)` returning `nil` means *keep*. Rewriting the
   filter as `guard let category = ... else { continue }` would drop every tag AniList has added
   since the cache was written, and a 30-day-stale vocabulary is the designed steady state. Pinned
   by `testATagMissingFromTheVocabularyStaysSeedable`.

The others: canonicalising `TagPair`; lexicographic tiebreak after weight (Swift's sort is not
stable, and tie blocks spanning the cut are the common case); `excludeAdultTags` as a parameter, not
a constant, so the private branch changes a call site rather than a body; `rank == nil` never seeds.

### Verification actually performed

Strictly red-green this time — the whole suite was observed failing to compile against absent
`TagPair`/`seedPairs` before a line of implementation existed, which closes slice 1's honest gap.
389/389 green afterwards, and green again after the `project.pbxproj` restore described below.

## The evidence pass — what the real store actually says

**`TagPairSeedingDiagnostic` was run against the device.** Its findings are recorded in ADR-0011's
`Measured 2026-08-03` block; do not re-derive them, re-run the diagnostic.

The headline is that **the predicted failure did not happen, for an instructive reason**. The
prediction was that Berserk would own all five seeds. It rested on reading the earlier handoff's
"Berserk `ranked=66`" as engagement dominance — it is a **tag count**. Berserk's engagement is
mid-pack (2.179 against Iruma-kun's 5.005), so its 1035 candidate pairs each land near
`2.179 × [0.6…1.0]`, far below the recurring pairs at 5–8.8. Every one of the top 20 recurs in ≥ 2
Works. **Recurrence beats volume** — which is exactly what the formula claims and had never been
checked. No diversity rule was added.

**Closed 2026-08-04** — the triangle below was measured against live AniList and the overlap is
small (29 distinct titles across 36 slots; 2 titles in all three edges). See ADR-0011's
`Measured 2026-08-04` block. Nothing changed; a revisit trigger was added. The paragraph below is
kept as written for the record.

**The one real finding left open:** the top 5 contains a **triangle** — `Demons∧Magic`,
`Demons∧Found Family`, `Found Family∧Magic`, three edges of one triple over largely the same three
Works. Three of five queries ask nearly the same question and will overlap under AND semantics.
Left in deliberately: a "no tag in more than N of the cut" rule is a guess, and **slice 4's golden
diff is the instrument that shows whether the overlap costs pool breadth.** Look for it there.

`Demographic` was added to the exclusions on this evidence (four demographic pairs in the top 20),
with the cost stated in the ADR: the top 5 is identical with and without it, so there is currently
no evidence the exclusion is *right*, only that it is free.

### How to re-run the diagnostic

```sh
D=/tmp/appdata && rm -rf "$D" && mkdir -p "$D/Library"
xcrun devicectl device copy from --device BE0AB07B-8A4E-5D2C-A674-5698010C4D27 \
  --domain-type appDataContainer --domain-identifier Elias-Magdaleno.Manga-Reader \
  --source "Library" --destination "$D/Library"
TEST_RUNNER_MANGA_READER_APP_DATA="$D" xcodebuild -scheme Manga-Reader \
  -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO \
  test -only-testing:Manga-ReaderTests/TagPairSeedingDiagnostic
```

Four things cost real time to discover:

- **`--source .` is rejected** ("File paths cannot contain '..'"). Use `--source Library`, which
  copies *the contents of* `Library` into the destination — hence the `$D/Library` nesting above.
- **The env var needs the `TEST_RUNNER_` prefix.** Without it the variable never reaches the
  simulator process and the test skips while looking like it ran.
- **Engagement is not persisted.** It is derived from history, which lives in **UserDefaults**, so
  the pulled `Library/Preferences/Elias-Magdaleno.Manga-Reader.plist` is load-bearing — `works.json`
  alone yields zero engagement and an empty result that looks plausible.
- **The device build predates slice 1, so there is no `Caches/anilist-tag-vocabulary.json`.** The
  diagnostic prints a loud warning and continues with an empty vocabulary, which excludes *nothing*
  — the numbers would be wrong in an entirely believable way. Today's run used a vocabulary fetched
  straight from AniList and written into the pulled `Library/Caches/` by hand (425 tags, 66
  `isAdult` — matching ADR-0011 exactly). Once a build carrying slice 1 has run on the device this
  step goes away.

## Pick up here — slice 3: the provider

1. ~~Tag vocabulary cache~~ — done, `51c4cbe`
2. ~~Pair seeding~~ — **done, `d945315`**
3. **The provider + its read-through cache — never blocks the rail** ← next, **now fully designed**
4. Fold into `CompositeCandidateProvider` and diff `Manga-ReaderTests/__Goldens__/foryou-ranking.txt`

Slice 4 stays **last and alone** so a golden diff has exactly one cause.

### Slice 3 is specified — read ADR-0011 before writing anything (`412072c`, 2026-08-04)

A grilling session on 2026-08-04 walked the whole slice-3 decision tree and wrote the results into
ADR-0011 as **three dated `Amended 2026-08-04` blocks**, under the sections they modify:

- under **"The pool is read-through and never blocks"** — the actor, the TTLs, failure policy, the
  fan-out budget, the cache record shape, the vocabulary accessor;
- under **"The pool runs only above 3 AniList-resolved Works"** — what the gate counts and where it
  lives;
- under **"Reason strings name the pair"** — which pair wins when several surfaced a title;
- plus a **new decision section**, "The provider splits into a pure core and an I/O shell, and lands
  unreferenced", covering the test seam and the wiring question.

Also two new hazards and a **Pool cache** glossary entry. Docs only — no code was written, and the
implementation is untouched.

**The four that are easiest to get wrong, or that cost something:**

1. **`SeededTagPair` gains `contributingWorks: Set<WorkID>` — this reopens slice 2.** The ≥ 3 gate
   counts *contributing* Works, not Works with a ranked axis, because a Work can carry ranked tags
   where none clears rank 60 or all sit in excluded categories. Expect churn on the 15 green
   slice-2 tests. This is the only decision here that touches shipped code.
2. **Two TTLs on one cache:** 14 days populated, **24 hours empty**. An empty pool is normal under
   AND *and* is what a transient failure looks like — the short TTL is what stops a hiccup costing
   a fortnight of dark rail. Collapsing them back to one number is the regression.
3. **Score before resolving.** `withinPool` is computable from the AniList response alone, so rank
   all candidates for free and spend MangaDex searches only on the top 12. The *ordering* is the
   decision; `perPairLimit = 12` and the cap of 40 are tunable. Doing it the other way round is not
   fixable without restructuring.
4. **The provider must not call `TagVocabularyStore.vocabulary()`** — it awaits a network fetch on a
   cold *or* 30-day-stale cache (`TagVocabularyStore.swift:105-113`), which stalls the exact path
   read-through exists to protect. Add a non-fetching `cachedVocabulary()` + `refreshIfNeeded()`;
   leave the existing method alone for its current caller.

**Expect the first slice-4 run to look broken.** Slice 3 lands unreferenced, so nothing ever kicks a
refresh — the first Home appearance after slice 4 wires the provider is a cold miss on the pool and
possibly the vocabulary, and the golden will show an empty AniList pool. That is the read-through
rule working. Run it, wait a beat, run it again. Wiring at `wAniList = 0` to pre-warm was considered
and rejected in the ADR (a zero weight still moves the golden via reasons and pool membership).

## Gotchas — all still true, all hit again this session

- **`xcp` reformatted `project.pbxproj` in the collapse direction again** — stripped
  `lastKnownFileType`/`name` from five unrelated `PBXFileReference` entries and collapsed the three
  `PBXFileSystemSynchronizedRootGroup` blocks, turning a 4-line change into 44. What worked in one
  pass: `git checkout HEAD -- Manga-Reader.xcodeproj/project.pbxproj`, then a python script
  inserting the four entries by mirroring `TagVocabularyStoreTests.swift`'s lines (`PBXBuildFile`,
  `PBXFileReference`, the group child, the `Sources` phase). **Re-run the tests after doing this** —
  a hand-edited pbxproj that fails to compile is the obvious risk, and it was verified green here.
  **`git diff --cached --stat` must read `4 ++++` immediately before `git commit`.**
- **The `agy` post-commit hook was rewritten on 2026-08-03 and now behaves differently.** It runs
  **detached**, so `git commit` no longer blocks for minutes. While a review is in flight it holds
  **`.agy_review_running`** in the repo root — **check that file is absent before starting an
  `xcodebuild`**, or you get "database is locked". It now writes to a temp file and only replaces
  `.agy_code_review.md` on success, so a failed run no longer destroys the previous review.
  Completed reviews start with `# agy review — <SHA> — <TIMESTAMP>` and end with
  `# agy review complete — exit 0`; **a missing footer means the run aborted** and the contents
  belong to an older commit. It targets `iPhone 17`, matching `CLAUDE.md`. The failure modes that
  prompted the rewrite are in `docs/superpowers/handoff/archive/2026-08-03-agy-hook-issues.md` — still worth
  reading, because it documents *why* the sentinels exist.
- **Slice 2 was reviewed and passed.** The verdict arrived late, from the pre-rewrite hook (no
  sentinels, ran on `iPhone 17 Pro`, conversational preamble still at the top of the file — a live
  example of the problem the rewrite fixes). It reports 389 passed / 0 failed, 0 compiler errors,
  0 style violations, 0 violations in the new files, and its architectural notes restate the four
  load-bearing decisions without contradicting any of them. Independently reproduced here: 389
  tests, and SwiftLint clean on both new files (the 35 repo-wide warnings are pre-existing, 23 in
  `Manga_ReaderTests.swift`, which is also over `type_body_length` at 2007 lines against 1800).
- **SourceKit errors are noise** — "No such module 'XCTest'", "Cannot find type 'Work' in scope" on
  files that compile clean. Judge only by `xcodebuild`.
- **Do not stack PRs.** Merging a base with `--delete-branch` closes the child unrecoverably.

## Still-open threads (older, none blocking)

Unchanged from the slice 1 handoff: the **eight deferred hand-checks** (the load-bearing one being
whether `.coordinateSpace(.named(…))` yields viewport-relative frames — if not, every webtoon resume
fraction is meaningless); the **`page 5/5` false-finish** experiment; **externally hosted chapters**
reading as broken because `ChapterAttributes` doesn't decode `pages` (`MangaDexAPI.swift:125-131`);
the **5xx wording** in `readerFailureMessage`; and **decoding MangaDex's free list-endpoint tags**,
which stays unclaimed until the AniList pool has been through a golden diff.
