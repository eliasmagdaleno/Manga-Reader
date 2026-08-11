# Can WeebCentral titles be resolved to MyAnimeList? — measurement, 2026-08-11

**Question.** ADR-0015's `noTaggableSignal` says "nothing you've read can be matched". Every
observation of it so far came from a simulator seeded with three WeebCentral *placeholders* whose
titles were invented, so their untaggability proved nothing about the source. Is WeebCentral
resolvable at all?

**Answer.** Yes. **47 of 64 real titles resolved, 47 correct, 0 wrong.** A real WeebCentral library
tags fine; the placeholder library was an artifact of its own fake titles.

**And a second finding that was not the question:** 15 of the 16 refusals are *threshold misses*,
not ambiguity ties — which is ADR-0016's revisit trigger firing, on a source ADR-0016 was never
measured against. See "What this implies".

## Method

Offline harness (`scripts/wc_resolve.py`), not in-app. The question is a property of *title data*
versus MAL's index, not of app wiring — and app wiring is the half ADR-0017 already verified live.
Offline buys a sample size in-app seeding cannot.

- **Titles:** WeebCentral's own `search/data` endpoint, `curl` with the pinned UA. Reachable
  without a Cloudflare challenge on this date; no WebView needed.
- **Matcher:** `MALTitleMatcher` ported to Python — same normalization (diacritic folding, noise
  tokens `manga/season/part/cour`), same Levenshtein similarity, same 0.90 threshold and 0.05
  ambiguity margin, same title cross-product scoring. Plus ADR-0017's `excludingNovels`.
- **Ground truth:** MangaDex's `links.mal` for the same title, matched at ≥0.90 by the same
  normalizer (37 titles). Where MangaDex had no id (10 titles), each resolution was checked by hand
  against MAL's own record.
- **Sampling:** two machine-picked cohorts, no hand selection — popularity top page, and a deep
  slice at `offset=400`. WeebCentral returns 32 rows per page regardless of the `limit` parameter.

### Port validation

The port was checked against four results **the app itself produced** in the ADR-0017 in-app run
before it was trusted for anything:

| Title | Harness | App (2026-08-10) |
|---|---|---|
| Jeonjijeok Dokja Sijeom | 132214 (top 0.96 / runner 0.71) | 132214 |
| Wind Breaker | refused (top 1.00 / runner 1.00) | refused |
| Berserk | 2 | 2 |
| Vinland Saga | 642 | 642 |

Including the refusal, and including its exact 1.00/1.00 tie shape. A harness that reproduces the
app's refusals is worth more than one that only reproduces its successes.

## Results

| Cohort | n | Resolved | Refused | Search failed | **Wrong** |
|---|---|---|---|---|---|
| Popularity, top page | 32 | 21 | 10 | 1 | **0** |
| Popularity, offset 400 | 32 | 26 | 6 | 0 | **0** |
| **Total** | **64** | **47** | **16** | **1** | **0** |

Correctness was established for **all 47**: 37 against MangaDex's `links.mal`, 10 by hand. A
recovery count that includes false matches is worse than no measurement, so none is reported here
without a check behind it.

The deep slice resolved *better* than the popular page (26/32 vs 21/32), which is the opposite of
the prediction. Not explained away: the popularity page is heavy with BL and doujinshi-adjacent
titles, which MAL indexes thinly. It does mean "popular titles are the easy case" is false here.

### The apparent duplicate is not one

Two WeebCentral series both resolved to MAL 7946 at similarity 1.00:

```
The Gorgeous Life of Strawberry-chan   -> 7946
The Super-Cool Life of Strawberry-chan -> 7946
```

MAL 7946 is `Strawberry-chan no Karei na Seikatsu`, whose `en` title is "The Gorgeous Life of
Strawberry-chan" and whose synonyms include "The Super Cool Life of Strawberry-chan". They are one
series under two names, and two Listings collapsing into one Work is Work identity (ADR-0007)
doing its job — not a false match.

### The refusals

| Title | top | runner | MangaDex `links.mal` |
|---|---|---|---|
| Xia Ke Xing | 1.00 | 1.00 | 18497 |
| Yoruhime-sama | 0.85 | 0.46 | — |
| The Vigilante of the Kingcraft Paradise | 0.82 | 0.33 | 90759 |
| Junjou Romantica | 0.75 | 0.62 | 765 |
| Sweet HR | 0.75 | 0.70 | — |
| Vairocana | 0.67 | 0.67 | — |
| Beyond Virtual | 0.64 | 0.60 | — |
| Kin no Tamago (Katsuwo) | 0.62 | 0.62 | — |
| Koi Inu | 0.60 | 0.56 | — |
| Sozo no Eterunite | 0.53 | 0.32 | — |
| Together with Zun-chan! | 0.50 | 0.44 | — |
| Brothers (NARUSE Yoshiki) | 0.48 | 0.48 | — |
| The Grandmaster of Demonic Cultivation | 0.47 | 0.47 | 137200 |
| Miquiztli | 0.44 | 0.44 | — |
| Level 1 kara Hajimaru Shoukan Musou: … | 0.41 | 0.28 | 146287 |
| Ling Bao Zhi | 0.27 | 0.25 | — |
| Lilith's Cord | — | — | MAL search returned no usable response |

**Exactly one refusal (`Xia Ke Xing`) is an ambiguity tie** — the Wind Breaker pattern, two real
comics sharing a title, which the guard is right to refuse. **The other fifteen never came close
to the 0.90 threshold.** Those are reach failures: MAL has the series, under a name the search did
not surface from the query WeebCentral gave us. `Módào Zǔshī` is the clean example — WeebCentral
calls it "The Grandmaster of Demonic Cultivation" and MAL files it under neither spelling.

**MangaDex holds a verified-correct id for 5 of the 16.**

## What this implies

ADR-0017 wrote down ADR-0016's revisit trigger verbatim:

> Refusals persist with a top MAL candidate scoring **below 0.90** rather than tying — that is a
> reach failure, not a collision, and it is the evidence ADR-0016 needed and never had. Reopen it.

That is what this measurement found: 15 of 16, on a source where MangaDex can supply 5 of the
missing ids outright.

**This does not contradict the two observations that rejected ADR-0016.** Both of those were made
on **MangaDex-sourced** titles — which carry `links.mal` in the response the app already fetches
(ADR-0018) and therefore never needed a bridge in the first place. ADR-0016 was measured on the
one source for which it was structurally unnecessary. This is the first measurement of the case it
was actually designed for.

So the correct reading is narrow: **a MangaDex bridge is worth reconsidering for sources that
publish no external ids of their own.** ADR-0016 stays Rejected — the record of why it was rejected
on MangaDex evidence is worth keeping intact. A revival belongs in a new ADR that supersedes it.

### What is still unmeasured, and blocks that ADR

**Cost.** ADR-0016 was rejected partly on 2–5 extra requests per refusal, and nothing here touches
that number. This measured *recoverability only*. Writing the revival ADR on half the ledger would
repeat ADR-0016's original mistake — it was built before it was measured. The next step, if this is
pursued, is a cost measurement against these same 16 refusals.

**The eleven with no MangaDex id.** A bridge recovers 5 of 16. The other 11 are titles MangaDex
either does not carry or carries without a `links.mal`, and they stay refused under any version of
this proposal.

## Hazards

1. **One source, one day, one sort.** Both cohorts came from WeebCentral's popularity ordering.
   A different sort or a different source is not covered.
2. **The ground truth is itself a fuzzy match.** MangaDex rows were selected by the same normalizer
   at ≥0.90. The five refusal ids in the table above were each re-checked by hand against the
   MangaDex title; the 37 agreeing ids were not, because agreement with an independently-derived id
   is already the check.
3. **The harness is a port, not the app.** It reproduces four app results exactly (above), which is
   evidence and not proof. A divergence between `MALTitleMatcher.swift` and `wc_resolve.py` would
   be invisible from here.
4. **`Lilith's Cord` is uncounted, not resolved.** MAL's search returned no usable response for it;
   it is excluded from both numerators and denominators rather than being scored as a refusal.
