# Measurement protocol — does a wider search input recover reverse-resolution misses?

**Registered 2026-08-15, before any measurement was taken.** The commit order is the evidence.
Nothing in this document reports a result; the run that fills it in is a separate commit. This
branch must merge with a **merge commit, not a squash** — PR #52's squash collapsed exactly this
evidence for the previous protocol.

## The question

`MoreLikeThis.pickMatch` searches MangaDex with **one** spelling — MAL's primary title — and
resolves against whatever those results contain:

```swift
// MoreLikeThis.swift:19
if let exact = candidates.first(where: { $0.malId == targetMalId }) { return exact }
let byTitle = matcher.bestMatch(
    sourceTitle: malTitle,
    candidates: candidates.map { (id: $0.id, titles: [$0.title]) })
```

Its two callers are `MoreLikeThisProvider.recommendations(for:)` and `MALReverseResolver`, which
also serves the AniList ranked pool (ADR-0011) and drops that pool's title set to `.first`
(`MALReverseResolver.swift:108`, the parked residual).

**The question is reach, not matching.** A second spelling changes which candidates come back, and
therefore whether an entry carrying `links.mal == targetMalId` is present to be found at all. That
is the *strong* arm — the arm that carries this path.

## Why this lever, and not the one that was queued

The 2026-08-15 handoff queued a protocol for **matcher input width** (`allTitles` versus one title
inside `bestMatch`). Reading the code first moved the target, and the reasoning belongs on the
record:

1. **The bridge is already wide on both sides.** `MALEntityResolver` matches with
   `sourceTitles: work.knownTitles` against candidates built from
   `titles(of:) = [title] + altTitles` (`:131`, `:221`, `:227`, `:254`). The premise that ADR-0019's
   path carries a narrow matcher is **false**. Where the fuzzy arm is the only arm, widening is
   already done.
2. **Where the matcher is narrow, it barely fires.** `split.json` from the reverse-reach run:
   **90 of 100** rows resolve through `pickMatch`'s exact-`malId` arm, which short-circuits before
   the matcher runs. Matcher width can only move the other 10 — and it moves the false-match risk
   into the same 10.
3. **The post-hoc 41 → 55 gain is path-bound.** It was measured against WeebCentral candidates,
   which publish no ids, so fuzzy was everything. That is feature A's path, and A is rejected.

So matcher width is **immaterial on shipped paths**, and this protocol goes one lever over: widen
the *search input*, which converts unresolved rows into strong-arm rows rather than fighting for
better fuzzy picks among 10.

The Hard rows in hand say the lever is real. *Mugen no Juunin* and *Rurouni Kenshin: Meiji Kenkaku
Romantan* are both plainly carried by MangaDex; they are unresolved because `searchManga(limit: 20)`
on MAL's romaji spelling did not surface a `links.mal` match in 20 results.

## Design

### Two arms, measured separately

| Arm | Population | Title set |
|---|---|---|
| **MAL recs** | `MoreLikeThisProvider`'s input — MAL per-title recommendations for the sim's library Works | `MyAnimeListManga.allTitles` (primary, en, ja, synonyms) |
| **AniList pool** | The ADR-0011 ranked pool's candidates | `AniListWork.knownTitles` (romaji, english, native, synonyms) |

Reported separately and never fused. The catalogues differ — MAL recs skew toward well-known series
with clean romaji; AniList's pool is ranked by its own signal and carries synonyms MAL does not — so
a pooled rate would describe neither caller.

**Seeds are re-derived, not reused.** Same frame as the reverse-reach run (the sim's 107 Works, 86
carrying a MAL id) and the same derivation, re-run. `recs.json`'s specific rows are already known to
the author, which would make any gate registered against them retrospective.

### Baseline and treatment

- **Baseline** — shipped behaviour. One MangaDex search on the primary title, then `pickMatch`
  unchanged.
- **Treatment** — one search per spelling for the first N spellings, **unioned into a single
  candidate pool** (deduped by MangaDex id), then `pickMatch` unchanged against that pool.

The union is not an implementation detail. `MALEntityResolver` already fans out this way in the
forward direction and documents why: one match per spelling is a maximum across independent ranked
lists, which has no runner-up and therefore routes around the ambiguity guard (ADR-0008). The
treatment mirrors the shipped pattern rather than inventing a second one.

### N is an output, not an input

`titleSearchLimit` defaults to 3 on the forward path (`MALEntityResolver.swift:73`). This protocol
does **not** inherit that number. The run records, for every recovered row, **which query index
first surfaced the `links.mal`-bearing candidate**. N then falls out of the cost gate. If spelling 3
recovers nothing across both arms, the shipped default lands at 2 with evidence behind it. The
requests spent are identical either way; only the bookkeeping differs.

### What is recorded per row

Recall alone would hide two ways this can lose:

- **Fuzzy-arm regressions.** A larger pool gives the ambiguity guard more to trip on, so a row the
  baseline picked fuzzily can become a refusal under treatment. Counted and reported separately from
  gains.
- **Strong-arm displacement.** Two pool entries agreeing on the target `malId` are harmless
  (`candidates.first` takes either). A wider query surfacing a *different* entry whose `links.mal` is
  wrong is ADR-0018 Hazard 1. Recorded by MangaDex id and hand-checkable.

Outcomes stay three-valued — **pick, refusal, search-failure** — per `MALReverseResolver`'s
cache-write discipline. Collapsing the last two is how the ADR-0019 gate run produced a believable
wrong answer on its first attempt.

## Sampling — a stopping rule, not a fixed n

**Draw until 60 baseline-unresolved rows accumulate, capped at 1500 baseline MangaDex queries.**
Whichever binds first.

The previous protocol fixed 100 slots, got 10 Hard rows, and both Hard gates died on n. The
population under test is the same one — rows the baseline fails to resolve — and it is roughly 10%
of whatever is drawn. Fixing the slot count again would reproduce the same inconclusive run. Sizing
on the population under test is the fix.

The AniList arm is expected to reach n faster, its catalogue being wider than MangaDex's. That is a
prediction, not an assumption; the run reports each arm's unresolved rate.

## Amendment 1 (2026-08-15) — the frames cannot reach the registered n

**Written before the run, not after it.** The sampling rule above registered 60 unresolved rows per
arm without checking what the frames hold. They do not hold it:

| Arm | Frame at shipped parameters | Expected unresolved at ~10% |
|---|---|---|
| MAL recs | **107 rows** — 86 seeds, of which 49 return no recommendations at all (`recs.json`, 2026-08-15) | ~10 |
| AniList pool | **60 media** — 5 seeded pairs × `poolPerPairLimit = 12`; only `poolResolveLimit = 12` resolve per refresh | ~6 |

This is ADR-0019 Amendment 1's lesson recurring: **a registered claim the planned instrument cannot
produce.** Running as written would guarantee a second consecutive inconclusive verdict, which is
not a measurement — it is a way of spending requests to learn nothing.

### What changes

Only the frames. **The gates are untouched.**

- **MAL arm draws at hop 2.** The library's recommendations become seeds, and *their*
  recommendations are the rows. The unit is unchanged — a MAL recommendation slot — one hop out
  from the library.
- **AniList arm draws from the top 20 seeded pairs at `perPage: 50`**, rather than 5 × 12. Same
  conjunctive `tag_in` query, same rank-60 floor, deeper into each pair's popularity ordering.

### The bias this introduces, and its direction

Both widenings sample **further down the tail**, where MangaDex's coverage is thinner. Expect the
unresolved rate to rise (which is what makes n reachable) and the **recovery rate to fall**, because
a tail title is more often genuinely absent from MangaDex than merely mis-searched.

**So the recovery gate becomes conservative.** A pass on this frame is a stronger result than a pass
on the shipped head would have been. A failure is correspondingly *weaker* evidence, and the
write-up must say so rather than reporting a bare miss — the honest reading of a sub-15% result here
is "not demonstrated on a tail-heavy frame", not "the lever does not work".

### Harness departures from the app, declared

`scripts/search_width.py` reconstructs the AniList arm's seeded pairs outside the app and cannot
reach two inputs: `TasteProfile.workWeights` (so every Work votes 1.0 for engagement rather than its
read-weighted value) and AniList's cached tag vocabulary (so `seedExcludedTagCategories` is applied
as a flat name list). Both affect *which* pairs seed, not how a row is resolved, which is what the
gates measure.

## Pre-registered gates

Per arm. Each is a number the run produces and which can come out either way.

| Gate | Floor | Why this number |
|---|---|---|
| **Recovery rate** | **≥ 15%** of unresolved rows, over **≥ 60** | Mirrors feature A's yield gate. Below it the extra queries do not pay for themselves. Data in hand suggests ~20% (2 of 10), so 15% can genuinely fail |
| **Cost** | **≤ 10** extra requests per recovered card, at the chosen N | ADR-0019's own bridge gate, verbatim; it measured 5.2 against that ceiling |
| **Wrong strong-arm picks** | **0** | ADR-0018 Hazard 1. Any occurrence stops the run and is reported — never traded off against recall |
| **Net recall** | **positive** after fuzzy-arm regressions are subtracted | A gain that nets out flat is not a gain |

### No adjudicated precision gate, deliberately

The label is an exact `links.mal` id match, authoritative under ADR-0018. A recovered card is
correct by definition rather than by judgment, so precision needs no human pass. **The user's 30
adjudication pairs stay unspent** — the second protocol running to completion without touching them.
That is an asset held, not an omission.

### Inconclusive — declared now, not later

If an arm reaches the 1500-query cap with **< 60 unresolved rows**, it reports its n and renders
**no verdict**. Naming this before the numbers exist is what stops it becoming an escape hatch when
they come back ugly.

### This protocol does not expect to pass

The recovery ceiling is **inherited, not escaped**: the lever tops out at the same ~10% of
recommendation slots that killed feature A. Its case is entirely cost — one or two MangaDex queries
on rows that already missed, against A's scraped-source round trip on every detail-page open. **If
the cost gate fails, this is rejected on the same ceiling A was.** Read the gates as a real test,
not as a formality before shipping.

## Execution notes — scars from the last three runs

1. **Assert MAL responses contain a `data` key.** A request without a client id returns a body with
   no `data`, which a naive script reports as a clean confirmed miss. `Secrets.xcconfig` is at the
   **repo root**. `MAL_CLIENT_ID` was rotated 2026-08-15 and the new key verified live; the *old*
   key's deletion at myanimelist.net/apiconfig is unconfirmed.
2. **Percent-encode UTF-8 bytes in query strings.** Python's `str.isalnum()` is true for CJK, so a
   hand-rolled "keep alphanumerics" encoder puts raw multibyte on the wire and MangaDex answers 400 —
   on precisely the Japanese-titled rows this measurement most needs.
3. **MAL answers 307 on some merged ids and following the redirect hangs.** Abort loudly; a long run
   can otherwise die 90 rows in.
4. **The AniList arm has no precedent in `scripts/reverse_reach.py`.** That harness never pulled
   AniList, so this grows a stage rather than reusing the script wholesale. AniList is a GraphQL
   endpoint with its own rate limiting.
5. **MangaDex's `/manga` search must carry `includes[]=cover_art`** to match what the app parses, and
   `limit: 20` must match `searchManga`'s shipped default — the whole point is that 20 is where the
   misses come from.

## What this protocol does not decide

- **Whether the fan-out fires inline or through the upgrade drain.** A cost question, answerable once
  the recovery rate is known.
- **Whether `MALReverseResolver.resolve(works:limit:)` keeps its `.first` reduction on the *cache*
  key** even if the search widens. A design question for the ADR that follows a passing run.
- **Matcher width**, which this protocol argues is immaterial on shipped paths. If feature A ever
  reopens, the post-hoc `allTitles` finding in
  `2026-08-15-reverse-resolution-beyond-mangadex-measured.md` becomes live again and needs its own
  registered protocol. It is not closed — it is out of scope.
- **Feature B (affinity)** in any respect.
