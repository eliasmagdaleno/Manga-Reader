# Session Handoff — 2026-08-11 (late): Amendment 1's instrument is built and validated, the run has not started

> **SUPERSEDED, same session, by `2026-08-11-adr-0019-amendment-1-verified-handoff.md`.** The run
> described below as "not started" was run and passed: 25 refusals, 8 recovered, 0 wrong. This file
> is kept only because its "what was built / what was validated" sections are the record of the
> instrument. **Do not work from its pickup list.**

**Audience:** the next session. Supersedes nothing — it is a *mid-task* handoff inside the single
item `2026-08-11-adr-0019-shipped-handoff.md` named as "What to do first". That handoff is still the
context; read it first.

**Nothing has been measured yet. No cohort has been fetched, no Work seeded, no drain run.**

## State

| | |
|---|---|
| Branch | **`adr-0019-amendment-1-run`**, off `0ccde90` |
| Commits | `a635308` — the run protocol, committed before the run *and nothing else* |
| Uncommitted | `VerificationSwitches.swift`, an `AppComposition` hunk, `scripts/adr0019_seed.py`, one UI test |
| Build | **succeeds** (`xcodebuild build`, iPhone 17) |
| Sim | `2A0D54DF-…`, booted, container backed up to the session scratchpad |
| Deadline | unchanged, **~2026-08-23** |

## The protocol is the spec — read it, don't re-derive it

`docs/superpowers/specs/2026-08-11-adr-0019-amendment-1-run-protocol.md`, committed in `a635308`
**before any data was touched**. It fixes the cohort rule, the two-pass method, the seeding
justification, the hand-check, and the failure conditions.

**Do not adjust it after seeing results.** The whole reason Amendment 1 exists is that Decision 6
registered a number the fixture could not produce; a protocol edited mid-run reproduces that failure
one level down. If it turns out to be wrong, amend it in its own commit, before the pass it changes.

The two things most likely to be re-derived incorrectly:

1. **Two passes are not optional.** The bridge is live in shipped code, so refusals the bridge
   recovers never appear as refusals at all. Pass 1 runs with the bridge **off** purely to close a
   cohort; pass 2 runs it on.
2. **`upgrade-attempts.json` must be deleted between passes** — and only that file. A pass-1
   `.unmatched(knownTitlesCount:)` suppresses re-attempt for the full 14-day TTL while the title
   count is unchanged (`UpgradeAttemptMemory.suppresses`, line 100), so pass 2 would otherwise never
   reach the bridge and would report zero recoveries for a reason that has nothing to do with the
   bridge. **That is the single most dangerous way this run can produce a false negative.**

## What was built

**`Manga-Reader/Services/VerificationSwitches.swift`** — `#if DEBUG`, reads two environment
variables, and returns nil when neither is set so the production graph is unchanged:

- `ADR0019_BRIDGE=off` — injects a bridge that finds nothing.
- `ADR0019_BRIDGE_LOG=<path>` — appends one line per bridge query. This is how the gate leg is
  observed: it logs the **request**, because both gate configurations return nil and only the query
  distinguishes "declined to ask" from "asked and found nothing".

`AppComposition` passes it to `MetadataUpgradeQueue(resolver:)`, which was already nil-defaulted.
`Services/` is a synchronized group, so no `project.pbxproj` edit was needed and none happened.

**It is an instrument, not a feature.** Delete it when the run is written up.

## What was validated, and why it matters

The protocol permits planting 80 Works into `works.json` **only if** the planted shape is checked
against one the app really produces. That check is **done and it passed**:

`testMintOneWeebCentralWorkThroughTheRealPath` (UI test, added) minted `Junjou Romantica`
(`01J76XY7HGZVKWMF67BF06HJ1S`) through `Add to Library`. Its stored entry is
`{id, listings: [{weebcentral, ULID}], externalIds: {}, displayTitle, knownTitles: [one title]}` —
identical on every field the resolver reads to what `scripts/adr0019_seed.py` writes. WeebCentral
publishes no alt titles, so the single-element `knownTitles` is not an approximation.

Two incidental findings worth keeping:

- **WeebCentral loaded in the simulator with no Cloudflare challenge**, and `curl` reaches
  `search/data` unchallenged too. Do not budget for the interactive challenge sheet until it
  actually appears.
- **That minted Work acquired a `provider: mangadex` snapshot** with 4 genres and **0 tags** — a
  source-level detail snapshot, *not* a resolution. It has empty `externalIds`. Do not count a
  snapshot as evidence of resolution in this run; count `externalIds.mal`. The 80 planted Works
  carry no snapshot and are all queue-eligible.

## What to do next, in order

1. `python3 scripts/adr0019_seed.py "<container>/Library/Application Support/works.json" 80` —
   container via `xcrun simctl get_app_container 2A0D54DF-… Elias-Magdaleno.Manga-Reader data`.
   **Re-resolve the container path after every build**; installing changes its UUID (ADR-0018's run
   learned this the hard way).
2. **Pass 1**, bridge off: launch with `ADR0019_BRIDGE=off`, drain to quiescence, read
   `upgrade-attempts.json`. **The refusals are the cohort and it closes here.** Fewer than 10 →
   report the shortfall, do not run the comparison as if the floor were met.
3. Delete `upgrade-attempts.json`. Nothing else.
4. **Pass 2**, bridge on, with `ADR0019_BRIDGE_LOG` set. Drain. A pass-1 refusal now carrying
   `externalIds.mal` is a recovery.
5. Hand-check every recovered id at `myanimelist.net/manga/<id>` **against the series**, not against
   MangaDex — MangaDex's `links.mal` produced the id and cannot also confirm it.
6. Gate leg: check the log. If no MangaDex-sourced Work missed on MAL during pass 2, the gate had
   nothing to refuse — **report it as not observed and do not substitute a weaker claim.** The
   protocol registers this in advance precisely so it cannot be quietly downgraded.
7. Write it up as a spec doc, update ADR-0019's status, delete `VerificationSwitches.swift`.

## Carried, unchanged

- The **ADR-0018 Decision 1 in-app leg** is meant to ride along with this seeding — a re-readable
  refused Work is what it has been blocked on for two sessions. The seeded library supplies real,
  openable WeebCentral titles, so it becomes possible for the first time. Not attempted yet.
- The three placeholder refusals (`Qelparre Drift`, `Zurnak Vhelli`, `Bramgot no Yeshu`) are still
  on the sim. They are **invented and unresolvable by construction** — exclude them from the cohort
  denominator explicitly rather than letting them dilute it.
