# ADR-0020 — Widening the search input on the reverse-resolution path

- **Status:** **Accepted (2026-08-19).** Licensed by a measurement whose gates were registered
  before the run, and **verified in the app** on an enriched draw: 14 of 14 rows that missed on
  their first spelling recovered on a widened query, all through the strong arm. Decision 5 is
  discharged with **one registered claim unmet** — the N = 3 bound was never observed *binding* —
  which is recorded below rather than retried
- **Licensed by:** [the 2026-08-15 search-input width measurement](../superpowers/specs/2026-08-15-search-input-width-measured.md)
  and [its protocol](../superpowers/specs/2026-08-15-search-input-width-measurement-protocol.md),
  committed before any request was sent. Harness `scripts/search_width.py`; raw data in
  `docs/superpowers/measurements/search-width/`
- **Related:** [ADR-0018](0018-an-authoritative-external-id-is-not-a-resolution-question.md) (the
  authoritative-id rule that makes the strong arm correct **by construction**, and that judged this
  run's one wrong pick), [ADR-0011](0011-ranked-axis-generation.md) (the AniList pool, one of the two
  callers, and the ADR that parked matcher width), [ADR-0019](0019-bridging-resolution-for-sources-that-publish-no-external-ids.md)
  (the *forward* path's reach fix, and the precedent for queueing expensive resolution — declined
  here, in Decision 2), [ADR-0008](0008-upgrade-queue-resolution-and-drain.md) (the ambiguity guard
  that the union-pool shape preserves)

## The problem, in one sentence

`MALReverseResolver` searches MangaDex with **one** spelling of a title, and when that spelling is
the romaji one MangaDex files under an English name, the entry never comes back — so a series
MangaDex plainly carries is recorded as unresolved and its recommendation card never appears.

*Mugen no Juunin* is on MangaDex as **Blade of the Immortal**. *Kaikan♥Phrase* is **Sensual
Phrase**. Neither is a matching problem. The right entry was never in the pool to be matched.

## What was measured

Baseline is shipped behaviour: one MangaDex search on the primary title, then
`MoreLikeThis.pickMatch`. Treatment adds one search per additional spelling, **unioned into a single
candidate pool** and re-picked. Two arms, never fused: MAL per-title recommendations, and the
ADR-0011 AniList ranked pool.

| Gate (registered before the run) | Floor | MAL | AniList |
|---|---|---|---|
| n | ≥ 60 unresolved | **60** ✓ | **60** ✓ |
| Recovery rate | ≥ 15% | **75.0%** (45/60) ✓ | **65.0%** (39/60) ✓ |
| Extra MangaDex queries per recovered card | ≤ 10 | **1.76** ✓ | **3.0** ✓ |
| Wrong strong-arm picks | 0 | **0** ✓ | **0** ✓ |
| Net recall | positive | **+45** ✓ | **+38** ✓ |

**83 of 84 recoveries came through the strong arm** — an exact `links.mal` hit on an entry the
primary-title search never returned. This is the finding the whole ADR rests on: the win is
**reach**, not matching. Widening the input changes *which candidates exist*; it barely changes which
one gets picked.

**N came out as 2, with 3 as the conservative setting.** Query 2 captures 86% of all recoveries,
query 3 takes it to 94%, and queries 4–5 together buy 5 cards out of 84. `titleSearchLimit = 3` on
the forward path was inherited by convention; this is the first evidence for the number.

### Two things the table does not say, stated here because a later reader will assume otherwise

**1. The cost column excludes the request needed to *obtain* the spellings, and on the MAL arm that
request is real.** The harness prefetched `alternative_titles` for the whole frame as part of frame
construction, so its per-card cost counts MangaDex queries only. In the app the two arms differ:

- **AniList arm — free.** `AniListWork.knownTitles` already carries romaji/english/native/synonyms,
  in hand, from a request already made. `MALReverseResolver.resolve(works:limit:)` throws all but
  `.first` away at `:108`. The spellings are being *discarded*, not fetched.
- **MAL arm — one extra request per unresolved row.** MAL does not apply top-level `fields` to
  nested `recommendations` nodes, so `rec.node.alternativeTitles` decodes as `nil`. Getting spellings
  costs one `mangaDetail(fields: alternative_titles)` per row that missed.

Costed honestly, the MAL arm is **(79 MangaDex + 60 MAL) / 45 = 3.09 requests per recovered card**,
not 1.76. That is still under a third of the registered ceiling of 10, so the verdict does not move —
but the number in the measurement is the wrong number to quote for the MAL arm, and quoting it would
understate the cost by 43%.

**2. One recovery in 84 was wrong, and the registered gate could not see it.** `Kyoukaisenjou no
Horizon` (MAL 24464) was recovered by a **fuzzy** match, score 0.96, onto a MangaDex entry publishing
`links.mal = 37783` — MangaDex authoritatively contradicting the match under ADR-0018. The gate was
phrased "wrong **strong-arm** picks", and the first scorer implemented exactly that: it inspected the
one arm where a wrong pick is structurally impossible and reported zero. Decision 4 is what this
finding buys.

## Decisions

### 1. Widen the search input to N = 3 spellings, unioned into one candidate pool

`MALReverseResolver` searches MangaDex once per spelling, up to **three**, and matches against the
**union** of everything returned (deduped by MangaDex id) rather than per-spelling.

Queries 2 and 3 fire **only on rows the primary-title search failed to resolve**. A resolved row
costs exactly what it costs today. That is why the overall cost is ~0.2 extra requests per row while
the per-recovered-card cost looks larger: the fan-out is paid on the ~10–14% of rows that missed.

**The union is not an implementation detail.** A per-spelling maximum across independent ranked lists
has no runner-up, and a match with no runner-up routes around ADR-0008's ambiguity guard. The
union preserves the guard's input. `MALEntityResolver` already fans out this way on the forward path;
this mirrors the shipped pattern instead of inventing a second one.

**N = 3, not 2, and not 5.** N = 2 captures 72 of 84 recoveries and is defensible if the request
budget ever tightens. N = 5 buys 5 more cards while spending, on every unresolved row, as much again
as N = 3 does — the tail is not worth paying for. Three matches the forward path's
`titleSearchLimit`, so the app has one fan-out number rather than two.

### 2. The fan-out fires **inline**, at the existing call sites — not through the upgrade drain

ADR-0019 queued its bridge through `MetadataUpgradeQueue` because that resolution was expensive.
This one is not queued, for two reasons, and the second is structural.

**The cost argument.** One to two extra searches, on a minority of rows, on a host already in the
request path, inside a function that is already `async` and already degrades to fewer cards on
failure. Queueing buys a saving that is not worth its user-visible price: a queued recovery means the
card is **absent on this visit** and appears on some later one. For a "More Like This" rail, a card
that shows up two sessions after you looked is close to no card at all.

**The structural argument, which is the decisive one.** `MetadataUpgradeQueue` drains **Works** out
of `WorkStore` (ADR-0009, ADR-0010). A reverse target is a MAL recommendation node or a pool
candidate — it is **not** a Work, has no `WorkID`, and is not in the library. Routing it through the
drain would mean either minting Works for series the user has never opened (which ADR-0007 exists to
prevent) or building a second, parallel queue. Both are large; neither is licensed by a measurement
about how many spellings get searched.

### 3. The cache key does not change, and the `.first` reduction is not a cache key

The open question inherited from the handoff was "does the cache key widen with the search". Reading
`EntityResolutionStore` dissolves it: `reverseCache` is keyed on **`String(malId)`** (`:53`, `:81`).
The `.first` at `MALReverseResolver.swift:108` is the **search input**, not the key. Widening the
input touches nothing about caching, and there is no spelling-varies-under-the-key hazard to guard
against.

**What does change is the meaning of an already-cached miss.** An `.unresolved(checkedAt:)` written
before this ships records "the *narrow* search missed", and it suppresses re-searching for the
14-day `missTTL` — so the widened search would not run on precisely the rows it was built for, for
two weeks after the update.

**Decision: let the TTL age them out. Do not add a cache version to force-invalidate.** The recovery
is delayed, not lost; every affected row re-searches within 14 days, wide. Against that, a version
key is new persisted state, a migration path, and a foot-gun the next schema change has to
remember — for a one-off, self-healing staleness. If in-app verification (Decision 5) is blocked
*by* this — a seeded sim whose reverse cache is already full of narrow misses — clear the cache in
the fixture, which is a test-fixture problem and not an app one.

### 4. The widened queries feed the **strong arm only**. Fuzzy matching stays on the baseline pool

Candidates returned by queries 2 and 3 may resolve a row **only** by an exact `malId` hit. The fuzzy
matcher continues to see exactly the pool it sees today — the primary-title search results — and
nothing more.

Concretely, `pickMatch`'s two arms stop taking the same input: the exact-id check runs over the
union, `matcher.bestMatch` runs over the baseline pool.

**The evidence points one way and is thin in the other, and this decision ships the thick half.**
83 of 84 recoveries were strong-arm; widening the fuzzy arm produced 1 recovery and 1 false one, on
n=1 in both directions. Restricting the new candidates to the strong arm keeps 83 of 84 recoveries,
removes the only observed failure mode, and — this is the part worth stating plainly — **changes
nothing about shipped matching behaviour.** A user seeing a wrong card cannot tell it came from a
widened search; they see the app confidently linking the wrong series. ADR-0019 already set the
standing rule that a false link is worse than a refusal, and precision-bias is not negotiable.

**This is deliberately not a claim that the fuzzy arm is bad.** It is a claim that we have 83-of-84
evidence for widening one arm and none for widening the other, so we ship the one we measured. If a
later run shows fuzzy recovering meaningfully on widened pools **without** false links, this
decision is the thing to reopen — it is one condition in one function.

### 5. Acceptance evidence, registered now and unadjustable

Per Amendment 1 of ADR-0019, the registered claim and the planned instrument must be **the same kind
of thing**. The measurement produced a *rate* on a sampled cohort; an in-app run exercises a
*mechanism* on whatever library it has. So what is registered here is mechanical:

- **On a library where at least 5 reverse targets are unresolved under the narrow search, at least 1
  recovers, and 0 recovered ids are wrong.** Every recovered id hand-checked.
- The full chain observed once, end to end: unresolved row → query 2 issued with a *different*
  spelling → candidate carrying `links.mal` appears in the union → id matched → card rendered.
- **The N = 3 bound is observed binding**: a row that exhausts three spellings issues **three**
  searches, not four.
- **Decision 4 is observed holding**: a widened-pool candidate that matches only fuzzily is **not**
  picked. If no such row occurs naturally, this is exercised by a unit test rather than declared
  verified — a condition that never fires is indistinguishable from an absent one (the lesson
  ADR-0019 paid for twice).

A run recovering **zero** on five-plus unresolved rows falsifies the mechanism in the app, whatever
the offline rates say.

#### Discharged 2026-08-19 — met on mechanism, unmet on the cap

Two runs, both under protocols committed before launch. Run 1 walked Home's grid and saturated at
19 targets with a single baseline miss against a floor of 5 — an inadequate fixture, reported as
such ([run 1](../superpowers/specs/2026-08-19-adr-0020-in-app-run.md)). Run 2 replaced the
navigation with Search over 13 seeds fixed in advance, each pre-checked to carry a target the
offline measurement had already scored `baseline-unresolved`
([Amendment 1](../superpowers/plans/2026-08-19-adr-0020-in-app-run-protocol-amendment-1.md),
[results](../superpowers/specs/2026-08-19-adr-0020-in-app-run-enriched.md)).

Against the bullets above:

- **Floor and recovery: met.** 14 rows missed on their first spelling; **14 recovered**, 0 wrong.
  Every recovery came back through the exact-`malId` arm, so no recovered id needed hand-adjudication
  — the strong arm makes correctness structural, per ADR-0018.
- **The full chain: met in the log, not visually.** Each of the 14 carries the MangaDex id its
  widened query returned. The screenshots do **not** show the rendered cards: the test's scroll loop
  stops when the rail header `exists`, which XCUITest reports true while the element is still below
  the fold. The rendering half of that bullet rests on the rail having been built and resolved, not
  on a picture of it.
- **The N = 3 bound binding: NOT met.** The amendment deliberately chose five targets carrying ≥ 4
  spellings so a third search could be seen stopping at the cap. **All five recovered on their
  second query.** The run's only 3-search row, *Red*, holds exactly three spellings — it spent what
  it had rather than being stopped, the same shape that disqualified run 1's Katanagatari.
- **Decision 4 holding: not observed, covered by unit test.** No widened-pool candidate matched only
  fuzzily, so the restriction never fired. Per this decision's own wording that is declared as
  test-covered, not as verified.

**Why this is accepted rather than re-run.** The unmet claim is about a *bound*, and the run
explains why it could not fire: recovery is concentrated at query 2, and a target that needs a third
spelling and still succeeds appears rare enough that a cohort built specifically from known misses
does not contain one. Chasing it would mean drawing seeds until a late recoverer appears — selecting
the fixture on the outcome the claim is meant to test, which is the failure mode this protocol chain
exists to prevent. The cap's arithmetic is covered by unit test; what the in-app run was for is the
mechanism, and the mechanism is observed.

**The practical consequence is a cost correction in our favour.** The offline 3.09 requests per
widened row is an **upper bound**, not a typical case: 13 of 14 recoveries spent 2 searches, not 3.
No rate here describes the wild — this cohort was assembled from known misses — but the *shape* of
the distribution is not an artefact of that selection, since selecting for misses does not select
for which query resolves them.

## What would reverse this

- **Any wrong recovered id.** Precision-bias, unchanged from ADR-0019.
- **In-app recovery of zero** against Decision 5's floor — the offline harness modelled something
  the app does not do.
- **Cost coming in materially above the offline figures** — most plausibly on the MAL arm, where the
  extra `mangaDetail` per unresolved row is the half the measurement did not count.
- A second measurement finding query 2 buys far less than 86%, which would make N = 3 a tail-chasing
  setting rather than a conservative one.

## Revisit triggers

- **If Decision 4's restriction is observed costing real recoveries** — widened-pool candidates
  matching fuzzily, correctly, on rows the strong arm cannot reach — re-run the precision question
  with a gate that classifies **by arm** from the start.
- **If feature A (scraped-source candidates) ever reopens**, matcher width becomes live again. This
  ADR argues matcher width is *immaterial on shipped paths*, not that it is refuted; on a path where
  fuzzy is the only arm, the post-hoc 41 → 55 finding needs its own registered protocol.
- **If MAL starts populating `alternative_titles` on nested recommendation nodes**, the MAL arm's
  extra request disappears and the cost argument in Decision 2 gets stronger, not weaker.
- **If a widened row is ever seen recovering at query 3 in the wild**, the N = 3 bound becomes
  observable binding and the claim left unmet above can be closed on real traffic rather than on a
  drawn cohort. Until then the cap is unit-tested and unwitnessed.

## The lesson this chain has now learned three times

Every instrument failure in the run that licensed this ADR had the same shape: **a confident number
computed over a fabricated frame, with nothing raised.** MAL answers `30x` under sustained load and
a merged id also answers `30x`, so 108 live ids were filed as merged and the frame lost its entire
hop-2 population. AniList reports `429` as a JSON error body rather than a transport failure. And the
wrong-pick gate inspected the one arm where a wrong pick is structurally impossible.

**Assert the frame you got is the frame you asked for — row count, hop distribution, pair count,
and which population a gate is actually looking at — before trusting anything computed from it.**
