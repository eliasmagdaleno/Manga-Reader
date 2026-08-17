# Measured — does a wider search input recover reverse-resolution misses?

**Runs the protocol registered in
[`2026-08-15-search-input-width-measurement-protocol.md`](2026-08-15-search-input-width-measurement-protocol.md)**,
with its two amendments. Harness: `scripts/search_width.py`. Raw data:
`docs/superpowers/measurements/search-width/`.

**Verdict: both arms pass every registered gate.** A wider search input recovers **75%** (MAL) and
**65%** (AniList) of reverse-resolution misses, at **1.76** and **3.0** extra requests per recovered
card against a ceiling of 10. Recovery is overwhelmingly through the **strong arm** — 83 of 84
recoveries came from finding an entry that publishes `links.mal`, not from better title matching.
**N = 3.** One wrong pick in 84 is recorded below, along with the gate phrasing that would have
missed it.

## What was measured, and why it is not what was queued

The 2026-08-15 handoff queued a protocol for **matcher input width** — widening `MALTitleMatcher`'s
inputs from one title to `allTitles`, on the strength of a post-hoc finding that Easy picks went
41 → 55 at no measurable precision cost. Reading the code before designing the run moved the target,
and the reasoning is the more durable half of this document:

1. **ADR-0019's bridge is already wide on both sides.** `MALEntityResolver` matches with
   `sourceTitles: work.knownTitles` against candidates built from
   `titles(of:) = [title] + altTitles` (`:131`, `:221`, `:227`, `:254`). The handoff's premise —
   that the shipped bridge runs a narrow matcher — is **false**. Where the fuzzy arm is the only
   arm, widening was done long ago.
2. **Where the matcher *is* narrow, it barely fires.** `MoreLikeThis.pickMatch` takes one source
   title and one candidate title, but its strong arm is an exact `malId` hit, which short-circuits
   first. On the reverse-reach data that arm resolved **90 of 100** rows. Matcher width can only
   move the other 10 — and it moves the false-match risk into the same 10.
3. **The post-hoc 41 → 55 gain was path-bound.** It was measured against WeebCentral candidates,
   which publish no ids, so fuzzy was everything. That is feature A's path, and A is rejected on a
   ceiling.

So the lever under test became **search-input width**: not how many titles the matcher compares, but
how many spellings are *searched*. A second query changes which candidates come back, and therefore
whether an entry carrying `links.mal` is present to be found at all — feeding the strong arm rather
than fighting for better fuzzy picks among ten rows.

The Hard rows in hand predicted the lever would bite. *Mugen no Juunin* and *Rurouni Kenshin* are
both plainly carried by MangaDex; they were unresolved only because `searchManga(limit: 20)` on
MAL's romaji spelling did not surface a `links.mal` match within 20 results.

## Method

| | |
|---|---|
| **Baseline** | Shipped behaviour — one MangaDex search on the primary title, then `pickMatch` |
| **Treatment** | One search per spelling for queries 2..K, **unioned into a single candidate pool** (deduped by MangaDex id), `pickMatch` unchanged against the pool |
| **Label** | An exact `links.mal` id match — authoritative under ADR-0018, so correctness is definitional, not adjudicated |
| **Arms** | `mal` (MAL per-title recommendations) and `al` (the ADR-0011 AniList ranked pool), never fused |

The union is not an implementation detail: `MALEntityResolver` already fans out this way, because a
per-spelling maximum across independent ranked lists has no runner-up and would route around the
ambiguity guard (ADR-0008). The treatment mirrors the shipped pattern rather than inventing a second
one.

**N was an output, not an input.** The run records which query index first surfaced the
`links.mal`-bearing candidate, so the shipped fan-out limit falls out of the data instead of being
inherited from `titleSearchLimit = 3`.

### The 30 adjudication pairs were not spent

Again — the third consecutive protocol to complete without touching them. The label is an id match,
and the one cell where adjudication could have contributed (a fuzzy recovery onto an entry
publishing no `links.mal`) came back **empty in both arms**. That is luck as much as design, and the
"no adjudicated gate needed" argument turned out to have a hole in it either way; see the wrong pick
below.

## Results

### AniList arm — 20 pairs (pre-extension, n below the registered floor)

Committed before the extension as `measure_al_20pairs.json` / `score_al_20pairs.json`, and reported
here because Amendment 2 requires the pre-extension state to stay visible.

| | |
|---|---|
| Rows | 399 (frame exhausted; the 1500-query cap was untouched) |
| Baseline unresolved | **55** — below the registered floor of 60 |
| Recovered | **36 (65.5%)** |
| Extra requests per recovered card | **2.92** |
| Wrong strong-arm picks | **0** |
| Recovery arm | **35 of 36 via exact `malId`**; 1 fuzzy |
| Recovered by query index | 2: **29** · 3: 4 · 4: 1 · 5: 2 |

**35 of 36 recoveries through the strong arm is the hypothesis confirming itself.** The wider query
surfaced a MangaDex entry publishing `links.mal` that the primary-title search never returned. This
is reach, not matching — and it is the direct evidence that retargeting off matcher width was
correct.

**A reader who discounts this to "descriptive, n=55" is not making an error.** That reading is
preserved deliberately.

### AniList arm — 40 pairs (extended frame, Amendment 2)

**The registered stopping rule was satisfied here**: the run stopped on `target-unresolved`, not on
frame exhaustion, with the 1500-query cap untouched at 420.

| | 40 pairs | 20 pairs |
|---|---|---|
| Rows | 420 | 399 |
| Baseline unresolved | **60** ✓ | 55 |
| Recovered | **39 (65.0%)** | 36 (65.5%) |
| Extra requests per recovered card | **3.0** | 2.92 |
| Wrong strong-arm picks | **0** | 0 |
| Recovery arm | **38 of 39 exact `malId`**; 1 fuzzy | 35 of 36; 1 fuzzy |
| Recovered by query index | 2: **31** · 3: 5 · 4: 1 · 5: 2 | 2: 29 · 3: 4 · 4: 1 · 5: 2 |

**The extension changed nothing, which is the strongest thing that could be said for it.** 65.0%
against 65.5%; cost 3.0 against 2.92; zero wrong picks in both. The 21 rows added by pairs 21–40
behaved like the first 399. A frame extension made after seeing results is suspect exactly because
it *could* move the number — this one did not, and both results stay reported so that judgement
remains the reader's.

### MAL arm — hop 2

Frame: **639 rows, 532 of them hop 2, zero skipped** — the backoff fix working, against the first
pass's 107 rows and 108 bogus "merged" skips. Stopped on `target-unresolved` at row 590, cap
untouched.

| | |
|---|---|
| Rows measured | 590 |
| Baseline unresolved | **60** ✓ |
| Recovered | **45 (75.0%)** |
| Extra requests per recovered card | **1.76** |
| Wrong picks | **0** |
| Recovery arm | **45 of 45 exact `malId`** |
| Recovered by query index | 2: **41** · 3: 2 · 5: 2 |

**Every single recovery came through the strong arm.** Not one relied on title similarity. The
mechanism is unambiguous: MAL's romaji primary title fails to surface the MangaDex entry, MAL's
English or Japanese spelling surfaces it, and the entry publishes `links.mal` pointing straight at
the target.

The recovered rows read exactly as the hypothesis predicted:

| Target (MAL primary) | Spelling that found it |
|---|---|
| `Mugen no Juunin` | Blade of the Immortal |
| `Blood+` | Blood Plus |
| `Kaikan♥Phrase` | Sensual Phrase |
| `Cosplay★Animal` | Cosplay Animal |

Two of those — *Mugen no Juunin* and the Kenshin/Blood cluster — are the exact rows the previous
session flagged as "MangaDex plainly carries these; the query is what failed." They are now
recovered, at one extra request each.

### Verdict against the registered gates

| Gate | Floor | MAL | AniList |
|---|---|---|---|
| n | ≥ 60 unresolved | **60** ✓ | **60** ✓ |
| Recovery rate | ≥ 15% | **75.0%** ✓ | **65.0%** ✓ |
| Cost | ≤ 10 requests per recovered card | **1.76** ✓ | **3.0** ✓ |
| Wrong strong-arm picks | 0 | **0** ✓ | **0** ✓ |
| Net recall | positive | **+45** ✓ | **+38** ✓ |

**Both arms pass every registered gate, on the frames the amendments defined.** The recovery rates
clear their floor by more than four-fold, and the cost gate — the one this protocol expected to fail
on, by inheriting feature A's ceiling — comes in at one-sixth to one-third of its ceiling. The
reason A died does not apply: A needed a scraped-source round trip on every detail-page open, and
this needs **one to three extra MangaDex queries on rows that already missed**, on a source already
in the request path.

### One wrong pick, which the registered gate would not have caught

The AniList arm's single fuzzy recovery is **wrong**, and finding it required fixing the scorer:

| | |
|---|---|
| Target | `Kyoukaisenjou no Horizon`, MAL 24464 |
| Recovered via | `境界線上のホライゾン` at query 2, fuzzy, score 0.96 |
| Matched entry | MangaDex `51a29af2…`, which publishes **`links.mal = 37783`** |

MangaDex authoritatively contradicts the match (ADR-0018), so this is a false recovery, not an
unverifiable one.

**The registered gate named "wrong strong-arm picks", and that phrasing has a hole in it.** The
protocol argued no adjudicated precision gate was needed because "the label is an exact `links.mal`
id match, so a recovered card is correct by definition". **That is true only of strong-arm
recoveries.** A widened search can also recover through the *fuzzy* arm, and those carry no such
guarantee. The first scoring pass inspected only strong-arm picks for wrongness and duly reported
zero — a gate passing because it was looking in the one place the failure could not be.

Scoring now classifies every recovery by arm: strong-arm recoveries correct by construction, fuzzy
recoveries wrong when the matched entry publishes a conflicting id, and **unlabeled when it
publishes none** — that last cell being the only place adjudication could have spoken, and it is
empty in both arms (0 rows).

Net effect on the verdict: **AniList's 39 recoveries are 38 correct and 1 wrong**; MAL's 45 are all
strong-arm and all correct. The gates still pass, on both the literal reading (zero wrong
strong-arm picks) and the stricter one this finding argues for (1 wrong pick in 84, 98.8%
precision). Reported both ways because the literal reading is the registered one and the stricter
one is the honest one.

## What N came out as: 2, with 3 as the conservative setting

| Query index | MAL recoveries | AniList recoveries | Cumulative share of 84 |
|---|---|---|---|
| 2 | 41 | 31 | **86%** |
| 3 | 2 | 5 | **94%** |
| 4 | — | 1 | 95% |
| 5 | 2 | 2 | 100% |

**One extra spelling buys 86% of everything available.** A second buys 8 points more. Queries 4 and
5 together recover 5 cards of 84 while costing as much as query 3 does across every unresolved row —
the fan-out's tail is not worth paying for.

`titleSearchLimit = 3` on the forward path (`MALEntityResolver.swift:73`) was inherited by
convention. It turns out to be the right number, and this is the first evidence for it: **N = 3
captures 79 of 84 recoveries.** N = 2 captures 72 and is defensible if the request budget is tight.

## Instrument failures — one shape, twice, and it is the dangerous one

Both APIs said **"slow down"** in a costume that a naive harness reads as a terminal answer. Neither
failed loudly. Both would have produced a smaller, believable, wrong frame.

1. **MAL answers 30x under sustained load, and a 30x is also how a merged id answers.** The previous
   runs' scar list recorded only the second reading — "merged id, do not follow". The first MAL pass
   here took that reading, classified **108 unique ids as merged**, and silently produced **no hop-2
   rows at all**: the entire frame expansion the amendment existed to create vanished into a skip
   list, and the run reported a clean exit. Every one of those ids answered `200` on a quiet retry
   seconds later. The tell was visible in the artifact — id 583 appeared as both a successful row
   *and* a skip — and it was not checked before launching. **Fixed:** 30x/429/503 retry with
   exponential backoff and are only called merged after surviving all of it.
2. **AniList reports 429 as a JSON error body, not a transport failure.** The 40-pair draw aborted
   at pair 30. Its limit is per-minute, so backoff has to be measured in tens of seconds, not
   milliseconds. **Fixed:** retry with 20s/30s/45s backoff, pair collection paced at 1.5s.

**The general rule worth carrying: a rate limit wearing another status code is indistinguishable
from a real answer, and the failure mode is a fabricated frame rather than an exception.** Assert
that the frame you got is the frame you asked for — the row count, the hop distribution, the pair
count — before trusting anything computed from it. After the fix the MAL frame came back **639 rows,
532 of them hop 2, zero skips**, which is what a correct run looks like next to the first pass's 107
and 108.

3. **A gate that inspects only one arm reports zero because it cannot see the other.** The
   wrong-pick scorer looked at strong-arm recoveries only, and the one wrong recovery in the run came
   through the fuzzy arm. This is the same family as the first two: not an exception, a confident
   number computed over the wrong population.

## Sample honesty

One library, one day, two catalogues. The AniList arm's frame is tail-heavy by construction
(Amendment 1), which biases the recovery rate **downward** — a tail title is more often genuinely
absent from MangaDex than merely mis-searched. The harness also reconstructs the pool's seeded pairs
outside the app and cannot reach `TasteProfile.workWeights` or AniList's cached tag vocabulary, so
*which* pairs seed differs from what the app would choose; that affects the frame, not how any row
resolves.

## What follows from this

A passing measurement is not a design. What the numbers license is an **ADR proposing the widened
search on the reverse-resolution path**, at N = 3, with these questions still open and deliberately
not answered here:

- **Where the fan-out fires.** Inline on detail-page open, or queued through the upgrade drain
  (ADR-0019's precedent for expensive resolution). At 1.76–3.0 extra requests *per recovered card*
  and roughly 0.2 extra requests per row overall, inline is now arguable where it was not before.
- **What happens to `MALReverseResolver.resolve(works:limit:)`'s `.first` reduction.** The search
  widens; whether the cache key does is a separate question, and getting it wrong means either
  re-searching resolved rows or caching under a spelling that varies.
- **Whether the fuzzy arm should be reached at all once the search widens.** The one wrong pick in
  this run came from it, and 83 of 84 recoveries did not need it. Disabling fuzzy on the *widened*
  path would have cost 1 recovery and prevented 1 false one. That is n=1 on both sides and settles
  nothing — but it is the cheapest question this data raises, and an ADR should not skip it.

## What this does not decide

- **Whether the fan-out fires inline or through the upgrade drain.** A cost question, now answerable.
- **The cache key.** Whether `MALReverseResolver` keeps its `.first` reduction on the cache key even
  when the search widens.
- **Matcher width**, which this document argues is immaterial on shipped paths — not closed, but out
  of scope. If feature A ever reopens, the post-hoc `allTitles` finding becomes live again and needs
  its own registered protocol.
- **Feature B (affinity)** in any respect.
