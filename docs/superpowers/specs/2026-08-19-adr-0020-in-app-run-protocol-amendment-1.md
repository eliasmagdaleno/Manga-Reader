# Protocol Amendment 1 — ADR-0020 in the app: an enriched draw

**Registered before the second run**, in its own commit, ahead of any instrumented launch.
Amends [`2026-08-19-adr-0020-in-app-run-protocol.md`](2026-08-19-adr-0020-in-app-run-protocol.md),
which stands unchanged except where this document says otherwise.

Discharges [ADR-0020](../../adr/0020-widening-the-search-input-on-the-reverse-resolution-path.md)
Decision 5 on the MAL arm — the same scope, the same instrument, a different fixture.

## Why the first fixture could not work

Run 1 drew detail pages by walking Home's grid, twice — 4 pages, then 12. Both draws produced
**byte-identical** target sets: 19 MAL ids, 18 baseline-resolved on the first spelling, 1 miss.
The registered floor was 5 baseline misses, so claims 1–4 were reported **not met**
(`docs/superpowers/specs/2026-08-19-adr-0020-in-app-run.md`).

The saturation is structural, not bad luck. MAL's recommendations for Home's popular titles
overlap almost completely and the reverse cache holds after the first resolve, so more pages add
no new targets. Worse, popular titles are exactly the ones MangaDex files under the spelling MAL
leads with — the cohort is selected *against* the effect under test.

## The change: seed by search, from targets already known to miss

Navigation moves from Home's grid to **Search**, and the seeds are chosen rather than encountered.
Each seed is a MangaDex title whose MAL top-8 recommendations contain at least one target that the
offline measurement recorded as `baseline-unresolved` and recovering at query ≥ 2
(`docs/superpowers/measurements/search-width/measure_mal.json`).

Both halves of every row below were **checked live against MAL and MangaDex on 2026-08-19, before
the run**, and the checks are the reason the seed list is fixed here rather than discovered during
it:

- the seed resolves on MangaDex with `links.mal` equal to the id shown, so forward resolution does
  not depend on the fuzzy matcher; and
- the target is still inside the seed's top 8 by `num_recommendations`, which is the same slice
  `MoreLikeThisProvider.topRecommendations` takes.

| Seed (MangaDex title) | seed MAL | Known-missing target in its top 8 | target MAL | spellings | recovered at |
|---|---|---|---|---|---|
| Vagabond | 656 | Mugen no Juunin | 658 | 4 | 2 |
| Golden Kamuy | 85968 | Mugen no Juunin; Red | 658; 12713 | 4; 3 | 2; 3 |
| Meitantei Conan | 1061 | Kindaichi Shounen no Jikenbo; Q.E.D. | 393; 3153 | 4; 5 | 2; 2 |
| Tenshi Kinryouku | 448 | X | 27 | 2 | 2 |
| Kimi wa Pet | 392 | Futago; The One | 16732; 3715 | 4; 2 | 2; 2 |
| Eden: It's an Endless World! | 731 | Shinseiki Evangelion | 698 | 3 | 2 |
| BLOOD+ A (Adagio) | 782 | Blood+ | 747 | 2 | 2 |
| Ai wo Utau yori Ore ni Oborero! | 2686 | Kaikan♥Phrase | 678 | 4 | 2 |
| Kaichou-san Chi no Koneko | 19205 | Cosplay★Animal | 5734 | 5 | 2 |
| Hotaru no Hikari | 4270 | Otoko no Isshou | 21659 | 4 | 2 |
| Miunohri to Swan | 13059 | Ahiru no Ouji-sama | 714 | 3 | 2 |
| Never Give Up! | 103 | The One; Teppen! | 3715; 10776 | 2; 3 | 2; 2 |
| Kaikan Phrase | 678 | Love♥Monster | 1237 | 2 | 2 |

Thirteen seeds, **15 distinct known-missing targets**, five of them carrying ≥ 4 spellings — which
is what claim 4 needs and what run 1 never had (its single widened target held exactly 3).

**Rurouni Kenshin was dropped** despite carrying two of these targets: its MangaDex entry has no
`links.mal`, so the seed itself would resolve through the fuzzy matcher and a failure there would
be indistinguishable from the effect under test.

## What an enriched draw can and cannot show — stated before the numbers exist

This cohort is **deliberately biased toward misses**. It is assembled from rows a previous
measurement already scored as baseline-unresolved with the same matcher. Therefore:

- **No rate computed from this run means anything about the wild.** Not the miss rate, not the
  recovery rate, not requests per recovery. The offline 3.09 remains the only cost figure, and this
  run must not be read as confirming or contradicting it.
- **What it can show is mechanism**: that the widening implemented in `MALReverseResolver` fires
  in the real app, on live network, through the real UI, and converts rows that genuinely miss into
  cards that genuinely appear. That is what Decision 5 asks for and all it asks for.
- **A target that now baseline-resolves is not a failure.** MangaDex's catalogue moves; some of the
  15 may have gained a matching title since the offline run. Those rows drop out of the denominator
  and are reported as such, not as recoveries and not as losses.

## Registered claims

Claims 1–5 of the base protocol carry over **unchanged in wording and in threshold**. Two
additions, specific to a chosen cohort:

6. **The seed list is not adjusted after seeing a log.** If the run under-delivers, the remedy is
   more seeds drawn by the same published rule — top-8 membership plus a `links.mal` seed — appended
   in a further amendment committed before the re-run, never a swap of the rows that disappointed.
7. **Every row is reported against the table above.** Each of the 15 targets lands in exactly one
   of: recovered at query ≥ 2, baseline-resolved (catalogue moved), unresolved after 3 spellings,
   or never observed (seed failed to open, or target left the top 8 between the pre-check and the
   run). Rows that never appeared are named, not silently dropped from the count.

## Named failure modes, additional to the base protocol

- **A seed that fails to forward-resolve** produces an empty rail and zero log lines. It is a
  missing row under claim 7, not a miss.
- **Cache carry-over between seeds.** Mugen no Juunin sits in the top 8 of two seeds and The One in
  two more; the first resolve caches it, so the second seed logs nothing for that id. Expected, and
  the reason the target count (15) exceeds neither the row count nor the claim-1 floor by accident.
- **MAL 30x under load.** Unchanged from the base protocol: `fetchedTitles:false` on every row is
  the tell, and the frame must be asserted before any rate is computed — though under this
  amendment no rate should be computed at all.
