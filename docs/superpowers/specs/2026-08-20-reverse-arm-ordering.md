# Does it matter which arm reverse-resolves a shared target first?

**Answer: no, and the change it would license is not worth making.** Measured 2026-08-20;
harness `scripts/arm_ordering.py`, raw output in
[`../measurements/arm-ordering/`](../measurements/arm-ordering/).

## Where the question came from

The [ADR-0020 AniList-arm run](2026-08-20-adr-0020-anilist-arm-results.md) found the two
reverse-resolution consumers asking about the same titles: **10 of 12** AniList pool targets
were already answered when the pool got there, put in the shared cache by the MAL arm earlier
in the same session. Only 2 pool targets ever reached `searchWidening`.

That looked like it might be costing requests, because the arms **pay differently**.
`searchWidening` fetches extra spellings only when it holds fewer than two:

| | first spelling comes from | on a baseline miss |
|---|---|---|
| MAL arm | MAL's primary title (nested recommendation nodes carry exactly one) | fetches titles — **one extra `mangaDetail`** — then up to 2 more searches |
| AniList arm | `AniListWork.knownTitles`: romaji, english, native, synonyms | up to 2 more searches, **no extra request** |

So if the arms disagree about the first spelling, whoever asks first decides whether the
baseline hits — and if the loser is the arm that would have hit for free, the app pays a
`mangaDetail` it did not need to.

## First, the mechanism is a race, not a sequence

Nothing orders the pools. `CompositeCandidateProvider.candidates` runs all three under
`async let` and awaits them together. The MAL arm simply wins: its targets come straight out
of per-seed recommendation fetches, while the AniList pool must load the Works, build seed
pairs, run five AniList queries, rank the result, and only then resolve. The pool arrives
late because its critical path is longer.

**Making the pool ask first therefore means serialising two concurrent pools** — waiting for
the slower one before starting the faster one — which delays the rail on every refresh. That
is the price of any fix here, and it is paid on every launch, not only on the rows it helps.

## What was measured

For each target, compare the two arms' **first** spelling, and — where they differ — ask
MangaDex whether each spelling returns the entry publishing that `malId`. Strong arm only
(an exact `links.mal` hit), which is what ADR-0020 Decision 4 restricts widened candidates
to and what every recovery in the in-app run came back through; re-implementing the fuzzy
matcher here would be a second definition of shipped behaviour, and the question does not
need it.

The MAL arm's own first spelling and baseline outcome are already in the committed run log,
so no MAL key is needed. Targets are identified by spelling count: MAL's carry exactly one.

| population | targets | same first spelling | differ | differ, both baselines hit | differ, only one hits |
|---|---|---|---|---|---|
| shared by both arms (the question's own population) | 10 | **10** | 0 | — | 0 |
| every target the MAL arm resolved | 32 | **30** | 2 | 2 | **0** |

The two disagreements are cosmetic — `7 Seeds` vs `7SEEDS`, and two spellings of the JoJo
Part 8 subtitle — and MangaDex answers both spellings with the right entry.

## Why this is not an artefact of one session

MAL's primary title and AniList's romaji are *the same field by another name*: both are the
romanised Japanese title. They agree except on punctuation and subtitle style, which is what
the two disagreements above are.

The cases ADR-0020 exists for — *Mugen no Juunin* filed on MangaDex as **Blade of the
Immortal** — are **not** disagreements between the arms. Both arms start from the romaji
title and **both miss**. What differs is only what happens next, and there the AniList arm is
strictly cheaper.

So the population where ordering could matter is narrower than it first looked: shared
targets **whose baseline misses**. In the run, that set was empty — all 10 shared targets
resolved on their first search, and all three observed baseline misses were targets only one
arm held (`658` and `38` MAL-only, `149` pool-only).

That emptiness has a structural reason, not just a small-n one. **Shared targets are popular
titles** — a series has to be both recommended for the user's seeds *and* rank in a tag-pair
query to be shared — and popular titles are exactly the ones MangaDex files under a name the
romaji search finds. Baseline misses concentrate on the obscure and the English-retitled.
The two populations are close to disjoint by construction.

## Verdict

**No change.** Serialising the pools would cost latency on every refresh to save a
`mangaDetail` on a population measured at zero and argued to be structurally rare. The
current behaviour — whoever is ready first answers, everyone else takes the cache hit — is
also the one that renders the rail soonest.

Recorded rather than acted on, so the next reader who notices the overlap does not have to
re-derive this.

## What would reopen it

- **A shared target seen widening.** That is the case this measurement found empty. If one
  shows up — a title both arms surface *and* whose romaji baseline misses — the saving
  becomes real and the population can be counted rather than argued.
- **MAL populating `alternative_titles` on nested recommendation nodes.** Then the MAL arm
  stops paying its extra `mangaDetail`, the asymmetry disappears, and the question closes for
  good. ADR-0020 already lists this as a revisit trigger for its own cost argument.
- **A cheaper fix than serialising.** The whole cost here is the serialisation; if the pool's
  critical path ever shortens enough that it wins the race on its own, the question answers
  itself at no cost.
