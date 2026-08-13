# ADR-0018 Decision 1 — in-app run protocol (2026-08-13)

Registered **before** any fixture was opened in the app, so the run can fail. Companion to
`2026-08-11-adr-0018-in-app-verification.md`, which closed Hazard 3 for **Decision 3** and
explicitly did **not** verify Decision 1.

## What is actually being verified

Decision 1: *history carries the id its source published* — `ReadingEntry.malId`, populated at
`HistoryStore.swift:160` from the `Manga` the reader was handed.

The leg has been blocked for three sessions on "no refused Work on this sim is re-readable". The
ADR-0019 Amendment 1 seeding fixed that — the sim now holds 17 real, still-refused WeebCentral
titles. **But a WeebCentral read is the weaker half of this claim, not the whole of it.**
WeebCentral publishes no external ids at all (that is ADR-0019's entire premise), so the id its
source published is *none*, and the entry is expected to carry `malId: nil`. A run that only does
that verifies nothing anyone doubted.

So the run has three legs, and **leg A is the substantive one**:

| Leg | Route | The claim |
|---|---|---|
| **A** | MangaDex title read from Search | the entry carries the published id |
| **B** | WeebCentral refused title read | the entry is written on the scraped-source path with no id, and the Work stays refused |
| **C** | Leg A's title resumed from History | Amendment 1's `asManga` fix holds on the resume route |

Leg C needs leg B to run in between: `record` updates the newest entry in place when the manga and
chapter match, so Berserk must be displaced from the top of history before resuming it, or the
resume writes nothing new and the leg is vacuous. **The WeebCentral read is the displacer.** That
ordering is load-bearing, not incidental.

## Fixtures, pinned now

| | |
|---|---|
| Sim | `2A0D54DF-5961-4286-A2B6-F24B4F7537B4` (iPhone 17), 105 Works, 20 refused |
| Leg A/C | **Berserk**, `801513ba-a712-498c-8f57-cae55b38cc92`, `links.mal = 2`, 425 English chapters |
| Leg B | **Othello (TSUKAMOTO Youichi)**, `weebcentral / 01J76XYARAEA516XZTK1R29HSW`, 4 chapters, refused `.unmatched(knownTitlesCount: 1)`, `externalIds: {}` |

Berserk is deliberately a title **already in history from the pre-0018 seeding**, carrying
`malId: null` under the same `mangaId`. The before-state is therefore on record rather than
asserted, and the run reads as a backfill-by-re-read — the exact mechanism ADR-0018's Scope leans
on when it declines to backfill.

MangaDex search returns `Boushoku no Berserk` (mal 113958) ahead of the target for the query
`Berserk`. The test must exclude it by label or it will verify the wrong manga's id.

## The predictions

Registered as falsifiable statements. Numbers are what the plist must show afterwards.

1. **Leg A.** After reading a Berserk chapter reached from Search, the newest `history.entries`
   record has `mangaId: 801513ba-…`, `sourceId: mangadex`, **`malId: 2`**.
2. **Leg B.** After reading an Othello chapter on WeebCentral, the newest record has
   `sourceId: weebcentral` and **`malId: null`**, and Othello's Work still carries `externalIds: {}`
   and its `.unmatched` refusal.
3. **Leg C.** After resuming Berserk from the History tab, a **new** record exists (not an in-place
   update) still carrying **`malId: 2`**.

**A failure mode that would look like success:** if leg C's resume updates the existing entry in
place instead of prepending, `malId` survives because nothing rewrote it — and the leg proves
nothing about `asManga`. The check is therefore on the **entry `id` (UUID) being new**, not on the
value alone.

**What this run cannot verify:** that a *wrong* `links.mal` is caught. It is not — Decision 2
accepts that exposure by name (Hazard 1), and nothing here tests it.

## Method

Three UI tests, run one at a time, with the plist dumped between runs:

- history lives in `UserDefaults`, key `history.entries`, in
  `.../Data/Application/B32F0B8D-…/Library/Preferences/Elias-Magdaleno.Manga-Reader.plist`
- `HistoryStore` throttles writes and flushes on `.background`, so **every test must press home
  before it ends** or the entry it was verifying is lost. This already bit the ADR-0018 run.
- do not delete `upgrade-attempts.json` — unlike the ADR-0019 run, nothing here needs a closed
  cohort, and deleting it would destroy leg B's refusal fixture.

Both refusal fixtures expire when the TTL ages out, **on or about 2026-08-23**.
