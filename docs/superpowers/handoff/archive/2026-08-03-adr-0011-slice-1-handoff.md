# Session Handoff — 2026-08-03: ADR-0011 slice 1 shipped, slice 2 (pair seeding) is next

**Audience:** the next session. The reader work is finished and merged; the live thread is the
AniList ranked-tag pool, ADR-0011, and it is now one slice in.

Supersedes `2026-07-30-webtoon-shipped-adr-0011-next-handoff.md` for **state** — PR #31 is merged
and slice 1 is done. That file remains the record of *why the reader looks the way it does* and
holds two things not repeated here: the **eight deferred hand-checks** (still owed, still the
user's explicit deferral) and the **`page 5/5` false-finish experiment**. Neither is affected by
this work.

## State

| | |
|---|---|
| `main` | `80bd1f6` — PR #31 merged (webtoon resume, ADR-0014) |
| Working branch | **`anilist-ranked-pool`** at **`51c4cbe`**, branched off `main`, tree clean, **not pushed, no PR yet** |
| Unit tests | **373 pass, 0 failures** (iPhone 17, `-parallel-testing-enabled NO`) — was 362 |
| UI tests | 11 pass; a full `test` run including them is ~5½ minutes |
| SwiftLint | clean (confirmed by the `agy` post-commit hook, which also re-ran all 373) |
| ADRs | 0007–0014 accepted; next free number is **0015** |
| Device | iPhone 16 Pro `BE0AB07B-8A4E-5D2C-A674-5698010C4D27`. The user tests on **hardware** |

## What shipped — slice 1, the tag vocabulary cache (`51c4cbe`)

Two files added/changed plus tests. ADR-0011's "`category` lives in a cached tag vocabulary, never
on the Work" decision, implemented as written.

- **`AniListAPI.tagVocabulary()`** — the `MediaTagCollection` query (`name category isGeneralSpoiler
  isAdult`), one request for all 425 tags.
- **`AniListAPI.perform<Payload: Decodable>(query:variables:)`** — the request path is now generic,
  with `GraphQLEnvelope<Payload>` and two payload types (`MediaPayload`, `TagCollectionPayload`).
  The vocabulary therefore inherits the media path's 429-retry and its deliberate *inspect the body
  before the status code* mapping, so a proxy's HTML 502 is `.httpStatus(502)`, not a
  `DecodingError`. `work(malId:)` now owns its own "missing payload ⇒ `.notFound`" decision, which
  the vocabulary does not share.
- **`Services/TagVocabularyStore.swift`** — `TagVocabularyEntry`, `TagVocabulary` (30-day TTL,
  case-insensitive `category(of:)` / `isGeneralSpoiler(_:)` / `isAdult(_:)`), and an `actor`
  `TagVocabularyStore` persisting `Caches/anilist-tag-vocabulary.json`.

### Three judgment calls the ADR did not settle — do not silently reverse these

1. **A *stale* vocabulary is served in preference to none.** ADR-0011's skip-rather-than-degrade
   rule is about *unfiltered* seeding; a 31-day-old vocabulary is still filtered correctly. So
   `vocabulary(now:)` returns `nil` only when there is nothing at all, and **a failed fetch is never
   written back** — an empty vocabulary cached for thirty days would read as "AniList has no tags."
   Pinned by `testAFailedRefreshFallsBackToTheStaleVocabulary`.
2. **Unknown tags are permissive.** `category(of:)` is `nil` for a name the vocabulary lacks, and
   both flags default `false`. The exclusion set is a **deny list**, so an unknown tag stays
   seedable rather than silently vanishing. **Slice 2 must not invert this** — writing
   `guard let category = vocabulary.category(of: tag) else { continue }` would drop every tag
   AniList added since the cache was written.
3. **30 days, not the 14 everything else in this subsystem uses.** Fourteen means "a negative answer
   is worth re-asking eventually"; a vocabulary is not a negative answer. The reasoning is at the
   constant so it does not read as a slip.

### Verification actually performed

373/373 green, and the tests were confirmed to *pin* behaviour rather than merely pass: mutating
the stale-fallback `return cached` to `return nil` fails **exactly one** test and nothing else.
The `agy` hook independently re-ran the suite and SwiftLint after the commit.

**Honest gap:** the tests were written before the implementation but were never observed red as a
whole — only the one mutation check above was run. If slice 2 is done strictly red-green, that is a
tightening, not a change of practice.

## Pick up here — slice 2: pair seeding

Still the slice order from `2026-07-29-anilist-pool-handoff.md`, now with step 1 done:

1. ~~Tag vocabulary cache~~ — **done, `51c4cbe`**
2. **Pair seeding** ← next
3. The provider + its read-through cache — never blocks the rail
4. Fold into `CompositeCandidateProvider` and diff `Manga-ReaderTests/__Goldens__/foryou-ranking.txt`

Slice 2 is a pure function over the Work store plus the vocabulary — no network — so it is the
easiest slice in the plan to do strictly test-first.

```
pairWeight(a,b) = Σ over Works w carrying both a and b at rank ≥ 60:
                     engagement(w) × min(rank_a, rank_b) / 100
```

Top 5 pairs. Pairs must **co-occur within a single Work** (rank is a per-Work number; a conjunction
assembled across Works is a claim nobody made). Exclude categories `Technical` and `Cast-Main Cast`
from **seeding only** — they stay available for scoring — and exclude the 66 `isAdult` tags from
seeding on `main`.

**Before wiring anything, eyeball the seeded pairs against the real store.** The user's tag
distribution is lopsided — Berserk `ranked=66`, Vagabond 29, One-Punch Man 26, Iruma-kun 21,
Eleceed 17, against Hidarikiki no Eren 3 — so the top 5 will be dominated by three or four titles.
Look at them and ask "does this read like the user's taste" *before* slice 4's golden diff bakes
them in. Slice 4 stays **last and alone** so a golden diff has exactly one cause.

## Facts verified live — do not re-derive

**From ADR-0011 (2026-07-28):** `tag_in` is **AND, not OR** (which is why a pair at rank ≥ 80 is
frequently empty and the floor is 60); candidates carry **no tags at all**
(`MangaDexAPI.swift:13-22`), which is why the axis pays off as *generation on AniList* rather than
as scoring on MangaDex results; `pageInfo.total` is junk (a flat 5000).

**From 2026-07-30:** the library-seeding gate is **PASS** — 22 Works, 14 AniList-resolved against a
gate of 3. The 8 suppressed are doujin titles genuinely not on MAL. Read the real store off the
**device**; the simulator has no `works.json` at all and checking the gate there reports a false
failure:

```sh
xcrun devicectl device copy from --device BE0AB07B-8A4E-5D2C-A674-5698010C4D27 \
  --domain-type appDataContainer --domain-identifier Elias-Magdaleno.Manga-Reader \
  --source "Library/Application Support" --destination <dir>
./scripts/queue-status.sh <dir>/works.json
```

## Gotchas — all still true, all hit again this session

- **`xcp` reformatted `project.pbxproj` in the collapse direction again.** It stripped
  `lastKnownFileType`/`name` from **five** unrelated `PBXFileReference` entries and collapsed the
  three `PBXFileSystemSynchronizedRootGroup` blocks to one line each — a 44-line diff for a 4-line
  change. A scripted restore (pull the original lines out of `git show HEAD:…` and substitute by
  UUID, then restore the whole synchronized-group section by regex) took one pass and got it to
  `4 ++++`. **`git diff --cached --stat` must read `4 ++++` immediately before `git commit`.**
- **The `agy` post-commit hook runs a full build + test.** `git commit` blocks for minutes and may
  time out the shell — the commit has already succeeded; verify with `git log`. Do not start a
  build until it exits, or you get "database is locked".
- The **SourceKit errors are noise** — "No such module 'XCTest'", "Cannot find type
  'TagVocabularyEntry' in scope" on a file that compiles clean. Judge only by `xcodebuild`.
- **Do not stack PRs.** Merging a base with `--delete-branch` closes the child unrecoverably.

## Still-open threads (older, none blocking)

- **The eight deferred hand-checks**, in `2026-07-29-webtoon-resume-position-handoff.md`. The
  load-bearing one: nothing has confirmed `.coordinateSpace(.named(…))` on the `ScrollView` yields
  viewport-relative frames. If it does not, every fraction is meaningless and webtoon resume
  silently does nothing. Obvious on the first webtoon.
- **The `page 5/5` false-finish report** is unresolved; the experiment that settles it is written
  out in that same file. Note the existing bad History row never heals — delete it before retesting.
- **Externally hosted chapters read as broken** — they answer `/at-home/server` with 200 and an
  empty file list. `ChapterAttributes` (`MangaDexAPI.swift:125-131`) does not decode `pages`; one
  field would let the chapter list mark the row before anyone opens it. Still the most worthwhile
  reader follow-up.
- **The 5xx wording** — `readerFailureMessage` rewrites every `MangaDexError.httpStatus` to "This
  chapter isn't available to read from this source", so a transient 503 gets that sentence next to
  a Retry button.
- **Decoding MangaDex's free list-endpoint tags** stays deliberately unclaimed until the AniList
  pool has been through a golden diff — that is ADR-0011's own revisit trigger.
