# ADR-0017 — Excluding novels from MAL resolution candidates

- **Status:** Accepted (2026-08-10)
- **Supersedes:** [ADR-0016](0016-mangadex-as-a-resolution-bridge.md), rejected on the measurement
  that produced this one
- **Related:** ADR-0008 (the precision-biased matcher and the ambiguity guard, both unchanged here),
  ADR-0009 (`.unmatched(knownTitlesCount)` — what a refusal is remembered as), ADR-0015 (the notice
  a permanently-refused Work eventually produces)

## Context

A Work whose source publishes no `malId` gets one: `MALEntityResolver` searches MyAnimeList by
title and hands the candidates to `MALTitleMatcher`, which accepts at 0.90 similarity and rejects
when the runner-up is within 0.05. A refusal is recorded as `.unmatched` and the Work stays
untagged — invisible to the recommender, and eventually the subject of ADR-0015's notice.

ADR-0016 assumed those refusals were a **reach** problem: MAL's search coping badly with romaji /
English / native spellings. It proposed routing around MAL's search entirely, via MangaDex. That
was built, and then measured, and the measurement said something else.

**Every refusal was an ambiguity-guard rejection. None was a threshold miss.** And the tie was
usually one specific thing:

```
Solo Leveling    121496 manhwa  vs  119184 novel   ← same title
ORV              132214 manhwa  vs  143441 novel   ← same title
Mount Hua        146878 manhwa  vs  161366 novel   ← same title
Wind Breaker     103237 manhwa  vs  133081 manga   ← two real comics
```

**MAL files novels under `/manga`, and a comic adaptation carries its source novel's title.** Two
candidates, identical similarity, and the matcher refuses — which is exactly what a precision-biased
matcher should do when it cannot tell two candidates apart. The matcher is not the problem. The
candidate list is.

Measured over twelve scraping-style titles against the live API:

| Configuration | Refused |
|---|---|
| Today | 6 / 12 |
| ADR-0016's bridge (two to five extra requests per refusal) | 3 / 12 |
| **Novels dropped from the candidate list** | **2 / 12** |

Every recovered id was verified to be the right series.

## Decisions

### 1. Drop `novel` and `light_novel` from MAL search results

`MyAnimeListManga` gains `mediaType`, `searchManga` requests the `media_type` field, and
`excludingNovels(_:)` filters the response before it reaches the matcher.

A novel is never a correct answer for this app. Its `malId` fetches a novel's tags, which is wrong
for every consumer downstream — the taste profile, the rail, "More Like This". So this is not a
tuning knob traded against recall: it removes candidates that could only ever be wrong, and the
recall it buys is a side effect of that.

**Thresholds are untouched.** ADR-0016's Decision 3 argued at length against loosening them, and
that argument survives its parent ADR intact: a wrong `malId` produces confidently wrong tags,
which is worse than the absent tags it replaces and is invisible to the reader. Nothing here
loosens anything — a smaller, cleaner candidate list is doing the work.

### 2. Filter in the API client, not the resolver

`MALEntityResolver`'s search seam takes `[MALCandidate]`, which carries no media type, so a filter
there would need the seam widened for a fact only one caller cares about. Resolution is
`searchManga`'s only caller, and its results are only ever used for resolution.

The cost, stated plainly: **a test that injects the resolver's `search` closure bypasses this
filter entirely.** That is why `excludingNovels` is a separate pure function with its own tests
rather than an inline `.filter` — the policy is testable on its own, and a resolver test can still
show *why* it exists by passing the novel through and watching the guard fire.

### 3. An absent or unrecognised `media_type` is kept

`mediaType` is optional and only the two known prose values are excluded.

This filter exists to remove a known-bad candidate, not to demand proof that a candidate is good.
If MAL adds a media type or omits the field, the failure mode is a candidate that should have been
dropped surviving — a refusal, which is today's behaviour — rather than a correct candidate silently
vanishing, which would be a new and invisible failure.

## Verified in the app (2026-08-10)

Accepted on a Python harness; **since confirmed running in the app**, on a simulator seeded with
seven real MangaDex titles read alongside three untaggable WeebCentral placeholders. The upgrade
queue resolved them live against MAL, and every resolved id was checked against MangaDex's own
`links.mal` for that title:

| Read title | App resolved | MangaDex ground truth | |
|---|---|---|---|
| Berserk | 2 | 2 | match |
| Vinland Saga | 642 | 642 | match |
| Vagabond | 656 | 656 | match |
| Jeonjijeok Dokja Sijeom (ORV) | 132214 | 132214 | match |
| Return of the Blossoming Blade | 146878 | 146878 | match |
| Na Honjaman Level Up: Ragnarok | 172429 | 172429 | match |
| Wind Breaker | — | 133081 | refused |

**6 correct, 0 wrong, 1 refused.**

The refusal is Hazard 1, behaving exactly as this ADR says it should. Querying MAL directly for the
same three titles shows the mechanism rather than just the outcome:

```
Jeonjijeok Dokja Sijeom  →  143441 novel   "Omniscient Reader's Viewpoint"   ← ranked FIRST
                            132214 manhwa  "Omniscient Reader's Viewpoint"
Return of the Blossoming Blade → 146878 manhwa + 161366 novel "Return of the Mount Hua Sect"
Wind Breaker             →  133081 manga  "Wind Breaker"
                            103237 manhwa "Wind Breaker"              ← two comics, no novel
```

ORV's novel twin is still there, still identically titled, and still returned *above* the manhwa —
so the ambiguity guard would still tie without this filter, and the app resolved it correctly with
one. `Wind Breaker`'s collision is two comics, which the filter cannot and must not touch, and it
refused. **This is the predicted behaviour on both sides of the line.**

Hazard 2 stands undiminished: this is seven titles, chosen by the same author, three of them lifted
from the original twelve. It confirms the mechanism operates in the app on live data; it does not
widen the sample.

## Hazards

1. **Two real comics can still share a title.** `Wind Breaker` names both a Japanese manga and a
   Korean manhwa; this filter does not touch that case and must not. It is refused today, is refused
   after this, and the guard is right both times.
2. **The sample is small and skewed.** Twelve hand-picked titles, weighted toward Korean webtoons —
   exactly where novel adaptations are common, and so exactly where this collision would dominate.
   The effect is real; its *size* on a different library is not established.
3. **A test that stubs `search` does not exercise this** (Decision 2).

## Revisit triggers

- **Refusals persist with a top MAL candidate scoring below 0.90** rather than tying — that is a
  reach failure, not a collision, and it is the evidence ADR-0016 needed and never had. Reopen it.
- **A wrong recommendation traced to a resolved id** → check whether the id is a comic at all
  before touching thresholds.
- **MAL gains server-side `media_type` filtering** on `/manga` → this moves into the query and
  `excludingNovels` goes away.
