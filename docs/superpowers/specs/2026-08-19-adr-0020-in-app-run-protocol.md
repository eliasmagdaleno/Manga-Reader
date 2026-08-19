# Protocol — ADR-0020 in the app (MAL arm)

**Registered before the run.** Committed in its own commit, ahead of any instrumented launch, so
that the claims below cannot be adjusted after seeing a log. Same discipline as
`2026-08-13-adr-0019-gate-run-protocol.md` and the search-width protocol before it.

Discharges [ADR-0020](../../adr/0020-widening-the-search-input-on-the-reverse-resolution-path.md)
Decision 5, on **one arm**. See "Scope" for why only one, and what that leaves open.

## Scope, and an honest note about the fixture

**MAL arm only.** Reverse resolution has two callers. `MoreLikeThisProvider.recommendations(for:)`
fires on detail-page open and needs no library at all — its reverse targets are the MAL
recommendations for whatever title is on screen. The AniList pool (ADR-0011) resolves 12 works per
For You refresh, which is a better n, but it needs a seeded library and reading history to have a
taste profile at all.

**The seeded simulator that would have served the second arm was destroyed during this session** —
`xcrun simctl erase` run against a wedged device while debugging an unrelated test-bundle failure,
without checking what data lived on it first. `works.json` (107 Works, 86 with a MAL id), a 25-entry
history, and `upgrade-attempts.json` with its declared hand edit are gone, with no backup. That is
recorded here rather than in a footnote because it is the reason this protocol covers one arm
instead of two, and because a later reader comparing seed sets to the search-width measurement needs
to know they cannot be reproduced.

The AniList arm therefore stays **unverified in the app**. It is also the arm that costs nothing
(its spellings are already in hand), so it is the less interesting one to watch in the wild.

## The instrument

`ADR0020_REVERSE_LOG=1` in the app's launch environment makes `MALReverseResolver` append one
JSON line per reverse target to `Documents/adr0020-reverse.log`:

```
{"malId":…, "spellings":[…], "searched":[…], "outcome":"baseline-resolved|recovered|unresolved",
 "arm":"exact|fuzzy|none", "recoveredAtQuery":2, "mangaDexId":"…", "fetchedTitles":true|false}
```

`#if DEBUG`, read from the environment, no UI or app state can reach it — the
`VerificationSwitches` pattern, deleted when this is written up.

**Unlike ADR-0019's instrument this one is an inline call, not an injected seam.** There is no seam
to inject at: `searchWidening` is where the spelling loop lives, and wrapping the `search` closure
from outside would log queries with no way to attribute them to a target, since up to four targets
run concurrently. The instrument is therefore three lines inside the type it observes, and it logs
what the type decided rather than what a wrapper could infer.

## Registered claims — unadjustable from here

1. **≥ 5 targets are `baseline-unresolved`** across the run. Below that the run establishes nothing
   and is reported as an inadequate fixture, not as a failure of the ADR.
2. **≥ 1 of those recovers through a widened query** (`recoveredAtQuery` ≥ 2).
3. **The full chain is observed at least once**, end to end, in one row: a baseline miss → a second
   search issued **with a different spelling** → a candidate publishing the target `malId` → that id
   recorded `.resolved` → the card present on screen.
4. **The N = 3 bound is observed binding**: at least one target with ≥ 4 spellings issues exactly
   **3** searches. If no target carries 4 spellings, this clause is **not met** and is reported as
   not met — it is not to be waved through on the unit test.
5. **Every recovery is classified by arm, and every *fuzzy* recovery is hand-checked** against the
   matched entry's `links.mal`.

### Why claim 5 is phrased that way, and what it cannot show

The search-width run registered "zero wrong strong-arm picks", implemented exactly that, and so
inspected the one arm where a wrong pick is **structurally impossible**. It reported zero and missed
a false recovery in the other arm.

Repeating that phrasing here would be worse, because ADR-0020 Decision 4 *guarantees* every widened
recovery is an exact `malId` hit. **"0 wrong widened recoveries" is therefore definitional in this
build and is not evidence of anything.** The only recoveries that can be wrong are baseline fuzzy
ones, which this change did not touch. Claim 5 checks those, and the run must say plainly that the
widened arm's precision is carried by construction, not measured here.

## Named failure modes, in advance

- **Empty log.** Nothing established. An empty log is not a pass, and specifically is not evidence
  that widening "didn't need to fire" — it is evidence the instrument or the navigation failed.
- **Every target single-spelling.** If MAL returns no alternative titles for the recommendations
  drawn, the widening cannot fire and claims 2–4 are unreachable. Fixture problem; redraw with
  different detail pages.
- **MAL 30x under load.** The scar from the search-width run: MAL answers `30x` when rate-limited
  and a merged id answers `30x` too. `fetchedTitles:false` on every row is the tell. Assert the
  frame — the number of logged targets should equal the number of recommendations the pages showed —
  before trusting any rate computed from it.
- **A baseline that resolves everything.** If 0 rows miss, the fixture is too easy; redraw.

## Method

1. Instrument added, `#if DEBUG`, plus a UI test that opens N MangaDex detail pages and waits for the
   More Like This rail on each.
2. The UI test sets `ADR0020_REVERSE_LOG=1` in `launchEnvironment`.
3. Log pulled from the app's data container and scored.
4. Recovered ids hand-checked against MangaDex `links.mal` and the series identity.

## What this run does not decide

- The AniList arm, unverified in-app (above).
- Cost in the wild. The extra `mangaDetail` per missed row is *visible* in the log as
  `fetchedTitles`, but one session of detail pages is not a cost measurement and no rate from it
  should be quoted against the offline 3.09.
