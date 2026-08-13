# ADR-0018 Decision 1 — verified in the app (2026-08-13)

Closes the last open leg of ADR-0018's Hazard 3. Predictions were registered before the run in
`2026-08-13-adr-0018-decision-1-run-protocol.md`; all three held, unchanged, and are reproduced
here against what the app actually wrote.

**Scope of the claim.** This verifies **Decision 1** — history carries the id its source published.
Decision 3 was verified on 2026-08-11 (`2026-08-11-adr-0018-in-app-verification.md`). **Decision 2
is not verified by this run and cannot be** — that a *wrong* `links.mal` becomes a confidently wrong
answer is Hazard 1, accepted by name, and nothing here tests it.

## Result

| Leg | Route | Predicted | Observed |
|---|---|---|---|
| **A** | Berserk, opened from Search | entry carries `malId: 2` | **`malId: 2`**, `mangadex / 801513ba-…` |
| **B** | Othello (TSUKAMOTO Youichi), WeebCentral | `malId: null`, Work still refused | **`malId: null`**, `externalIds: {}`, `.unmatched(1)` intact |
| **C** | Berserk resumed from History | a **new** entry, still `malId: 2` | **3 new entry UUIDs**, all `malId: 2` |

History went 10 → 19 entries across the three runs. The seeded pre-0018 Berserk entry
(`64F92C46-…`, `malId: null`) is still on disk beneath the new ones, under the same `mangaId` — so
the before-state is on record rather than asserted, and the pair is the whole of Decision 1 in two
lines of JSON:

```
{"mangaTitle":"Berserk","mangaId":"801513ba-…","malId":null,"id":"64F92C46-…"}   # seeded, pre-0018
{"mangaTitle":"Berserk","mangaId":"801513ba-…","malId":2,   "id":"422BDD2B-…"}   # written today
```

That is also ADR-0018's Scope claim demonstrated rather than argued: **a re-read backfills one Work
for free**, which is why no backfill pipeline was built.

### Leg C is the one that needed care

`record` updates the newest entry in place when manga and chapter match, so resuming a title that is
already at the top of history rewrites nothing and `malId` survives *because nothing touched it* — a
pass that proves nothing. Leg B's WeebCentral read was scheduled between A and C precisely to
displace Berserk, and the check is on the **entry UUID being new**, not on the value:

| | |
|---|---|
| Berserk entry ids before leg C | `4534D7F8`, `84A0B6EE`, `F81D9A8D`, `64F92C46` |
| After leg C | `422BDD2B`, `8D9F3750`, `3661E9CA` — **none of them the same** |

These came through `ReadingEntry.asManga`, the exact line Amendment 1 found hardcoding `malId: nil`.
The fix holds on the route a re-read actually takes.

### An extra the run gave away

The six swipes in each test crossed a chapter boundary (386 → 385 → 386), so entries were written by
the **chapter-advance** path as well as by the ordinary open — and those carry the id too. Not
predicted, so it is reported as an observation rather than a verified claim.

## What leg B is and is not worth

WeebCentral publishes no external ids; that is ADR-0019's whole premise. So "the id its source
published" is *none*, and `malId: null` is the correct answer rather than a missed one. **Leg B on
its own would verify nothing anyone doubted** — it shows the write happens on the scraped-source
path and that nothing invents an id, and it supplies leg C's displacement. Leg A carries the claim.

This matters for how the three-session block on this leg should be remembered: what was actually
missing was not "a re-readable refused Work" but "a re-readable Work whose source publishes an id."
Berserk was available the whole time. The seeded WeebCentral library unblocked the weaker half.

## Method

Three UI tests in `Manga_ReaderUITests`, run one at a time in A→B→C order, each pressing home before
returning (`HistoryStore` flushes on `.background`; a run that just ends loses its own evidence).
They are **instruments, not CI tests** — pinned to the seeded sim and to live network.

Verification is by reading `history.entries` out of the app's `UserDefaults` plist, because
`ReadingEntry.malId` is never rendered anywhere in the UI. **The sim's data container UUID changes on
each install** — resolve it by newest mtime rather than pinning the path, which cost a confusing
`FileNotFoundError` mid-run that looked briefly like wiped fixture state.

`upgrade-attempts.json` was deliberately **not** deleted — unlike the ADR-0019 run, nothing here
needs a closed cohort, and deleting it would have destroyed leg B's refusal.

Leg B's fixture expires with its TTL, on or about **2026-08-23**. Leg A's does not expire.

## Disposition of the instruments — decided 2026-08-13, after the run

The PR that carried this run left one question open: whether tests pinned to a seeded sim, live
network and expiring fixtures should stay in the tree past their expiry. Resolved as follows, and
the resolution is *per leg* rather than for the set — the legs did not have the same shelf life.

**Leg B is deleted.** It was the only leg whose fixture genuinely expired: it needed a WeebCentral
title *still under refusal*, which is a 14-day property, so keeping it meant hand-picking a fresh
refused title every fortnight for a leg that was already the weaker half — it showed the scraped
path writes no id, not that an id survives. Its result stands recorded above. `git show 7f434b8`
recovers the test if the scraped path ever needs re-checking; expect to source a new fixture.

**Leg C is now standalone and no longer expires.** It had depended on leg B running between A and C
purely to displace Berserk from the top of history, so deleting B would have quietly broken it —
`record` updates in place on a manga+chapter match, and an undisplaced resume writes nothing new
while still reading `mal 2`. It now displaces Berserk itself with a MangaDex title.

**Leg A is unchanged.** Its fixture is Berserk; it never expired.

### The rewrite was re-run, not just re-compiled

A displacer needs *readable* chapters, which is not the same as existing. The first candidate was
Wind Breaker, already in the sim's library: search found it and the detail page opened correctly,
but that entry carries `0 AVAILABLE / No chapters yet.` in English — nothing to open, nothing
displaced, and the failure surfaced as a chapter-row timeout that reads like a network flake.
Junjou Romantica was checked against `/chapter` with `translatedLanguage[]=en` (134) *before* being
used, as were both titles its search returns, since the test taps result 0.

The rewritten leg C then ran green, and the plist confirms it still measures rather than merely
passing — three **new** Berserk UUIDs, all `malId: 2`, above the displacer's own entries and
distinct from the earlier run's:

| Time (UTC) | Title | Ch | malId | Entry |
|---|---|---|---|---|
| 23:14:26 | Berserk | 386 | 2 | `CB91A512` |
| 23:14:21 | Berserk | 385 | 2 | `DA2FE17A` |
| 23:14:12 | Berserk | 386 | 2 | `9F98E169` |
| 23:13:54 | Junjou Romantica | 100.96 | 765 | `E78D6907` (displacer) |
| 22:08:51 | Berserk | 386 | 2 | `422BDD2B` (earlier run) |

History is now 25 entries; the sim gained Junjou Romantica reading history it did not have before.
