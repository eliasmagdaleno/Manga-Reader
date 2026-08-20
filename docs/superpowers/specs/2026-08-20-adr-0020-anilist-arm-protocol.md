# Protocol — ADR-0020 in the app (AniList arm)

**Registered before the run.** Committed in its own commit, ahead of any instrumented launch, so
the claims below cannot be adjusted after seeing a log. Same discipline as
[the MAL arm's protocol](2026-08-19-adr-0020-in-app-run-protocol.md), its
[Amendment 1](2026-08-19-adr-0020-in-app-run-protocol-amendment-1.md), and the ADR-0019 chain
before them.

Closes the half of [ADR-0020](../../adr/0020-widening-the-search-input-on-the-reverse-resolution-path.md)
Decision 5 that its 2026-08-19 discharge left open: *"The AniList arm is therefore **unverified in
the app** and blocked on a fixture."* The fixture exists again (PR #58), so the block is gone.

## What is different about this arm

Both arms funnel into the same `MALReverseResolver.searchWidening` — `AppComposition` builds one
resolver and hands it to both consumers — so this is not a second implementation. Three things
about the *inputs* differ, and they are why the arm is worth watching separately:

1. **The spellings are already in hand.** `AniListWork.knownTitles` is romaji + english + native +
   synonyms, de-duped. `fetchTitles` therefore never fires on this arm, so it spends **no extra
   `mangaDetail` request** — the cost half of Decision 2 that the MAL arm carries does not exist
   here. `fetchedTitles:false` on every row is the *expected* reading, not the rate-limit tell it is
   on the MAL arm.
2. **More spellings per target.** The MAL arm's run had to hand-pick five targets carrying >= 4
   spellings and still saw none of them reach a third query. Four-spelling targets are ordinary
   here. This is the arm where the N = 3 cap has a real chance of being seen binding.
3. **The targets are drawn by the app, not by us.** `AniListCandidateProvider` ranks its pool and
   reverse-resolves the top `poolResolveLimit` (12) per refresh. There is no seed list to choose,
   which removes the selection worry that shaped the MAL arm's Amendment 1 — and removes the lever
   that let that run reach its floor.

## The fixture, and why it is not selected on the outcome

The 22-Work fixture was harvested and committed **before this protocol was written**, for the
general purpose of having a realistic library (`scripts/harvest_seed_fixture.py`,
`scripts/seed-harvest.json`, merged in #58). Its titles were chosen for a plausible reading
history and for MangaDex chapter availability. Nothing in it was chosen with reverse resolution in
mind, and no row of it is a reverse target: the targets are AniList pool candidates the app derives
from the fixture's tag pairs.

**The pool cache must be cold.** `anilist-pool.json` lives in Caches, is not seeded, and is keyed by
seed pairs with a 24h TTL. A warm cache means zero reverse resolution and an empty log. The run
deletes the app's Caches directory immediately before launching, and reports having done so.

## The instrument

Restored from `9b1b01d^` unchanged: `VerificationSwitches.logReverse` plus the three `trace` calls
inside `searchWidening`. `#if DEBUG`, read from `ADR0020_REVERSE_LOG=1` in the launch environment,
one JSON line per reverse target appended to `Documents/adr0020-reverse.log`:

```
{"malId":…, "spellings":[…], "searched":[…], "outcome":"baseline-resolved|recovered|unresolved",
 "arm":"exact|fuzzy|none", "recoveredAtQuery":2, "mangaDexId":"…", "fetchedTitles":true|false}
```

It is deleted again when this run is written up, exactly as it was after the MAL arm.

## Registered claims — unadjustable from here

1. **The frame is asserted first.** The number of logged rows must equal the number of targets the
   app actually resolved this session (`poolResolveLimit` per pool refresh, minus targets already
   answered by `EntityResolutionStore`). A row count that does not reconcile is reported as an
   instrument failure and **nothing is computed from it** — the lesson the MAL chain records having
   learned three times.
2. **>= 5 targets are baseline-unresolved.** Below that this run establishes nothing about recovery
   and is reported as an **inadequate fixture**, not as a failure of the ADR. This is the MAL arm's
   floor, kept deliberately: a lower one would be choosing the bar after seeing the arm.
3. **Given claim 2 is met, >= 1 of those recovers through a widened query** (`recoveredAtQuery` >= 2).
   Zero recoveries on five-plus misses falsifies the mechanism on this arm.
4. **The full chain observed at least once, end to end, in one row:** baseline miss → a further
   search issued **with a different spelling** → a candidate publishing the target `malId` →
   recorded resolved → **the card present on screen**, evidenced by a screenshot attachment framed
   on the For You rail. The MAL arm could only meet this in the log; the rail here is on Home, so
   the visual half is reachable.
5. **The N = 3 bound, reported either way.** If any target carrying >= 4 spellings issues exactly 3
   searches, the bound is observed binding and ADR-0020's open claim closes on this arm. If none
   does, that is reported as **not met**, with the spelling distribution given so a reader can see
   whether the cap was untested or merely unreached. It is not to be waved through on the unit test,
   and a target that issues 3 searches because it *holds* exactly 3 spellings does not count — that
   is spending what it has, not being stopped, the shape that disqualified rows in both MAL runs.
6. **Precision is reported by arm, and the widened arm's is declared structural, not measured.**
   Decision 4 makes every widened recovery an exact `malId` hit, so "0 wrong widened recoveries" is
   definitional in this build and is evidence of nothing. Any *baseline fuzzy* resolution is
   hand-checked against the matched entry's `links.mal`; those are the only ones that can be wrong.

## Named failure modes, in advance

- **Empty log.** Nothing established. Specifically **not** evidence that widening was unnecessary —
  it is evidence that the pool did not refresh (warm cache, gate not cleared, no network) or that
  the instrument did not fire.
- **The pool gate not cleared.** `AniListCandidateProvider` runs only above 3 AniList-resolved
  Works. The fixture clears it (20 resolved, >= 5 tag pairs at the >= 3-contributing-Works gate,
  asserted by unit test), but if the gate blocks at runtime the log is empty for a reason that has
  nothing to do with widening. Distinguished by checking the rail rendered at all.
- **Every target single-spelling.** Would make claims 3–5 unreachable. Unlikely on this arm, and if
  it happens it is a finding about `AniListWork.knownTitles`, reported as such.
- **A baseline that resolves everything.** Fixture too easy for this question; reported as claim 2
  unmet. Not retried by redrawing the fixture — that would be selecting on the outcome.
- **AniList 429.** It reports rate limiting as a JSON error body, not a transport failure, so a
  throttled pool query can look like a small pool. Cross-checked against the pool size the run
  observes.

## Method

1. Instrument restored (`9b1b01d^`), protocol committed — this file, before any instrumented launch.
2. A UI test launches the app with `ADR0020_REVERSE_LOG=1`, waits for the For You rail to be
   **hittable** (not merely to exist — the MAL run's screenshots were useless for exactly that
   reason), and attaches a screenshot framed on it.
3. The app's Caches directory is deleted immediately before launch, so the pool is cold.
4. Log pulled from the data container and scored; the frame reconciled before anything is computed.
5. Any baseline fuzzy resolution hand-checked against MangaDex `links.mal`.

## What this run does not decide

- **Cost in the wild.** This arm spends no extra request by construction; that is an argument from
  the code, not a measurement, and one session's pool refresh is not a cost measurement either.
- **Anything about the MAL arm**, which is already discharged.
- **The offline recovery rate.** This is a mechanism run on one library, exactly as the MAL arm's
  was, and no rate computed from 12 targets describes anything.
