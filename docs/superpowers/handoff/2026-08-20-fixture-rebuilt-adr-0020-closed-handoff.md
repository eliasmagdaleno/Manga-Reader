# Handoff — the fixture is rebuildable, ADR-0020 is closed

Session of 2026-08-19/20. **Everything is merged; nothing is in flight.** `main` is at
`3ef656a`, 492 unit tests pass (2 skipped), no open PRs, no open issues.

Six PRs: `c3d5e6b` (#58 seeding tool), `9f10523` (#60 device), `c995a01` (#59 AniList arm),
`5fb35dd` (#61 arm ordering), `665d303` (#62 seed MAL ids), `3ef656a` (#63 agy removal).

## The one-paragraph version

The seeded simulator that `simctl erase` destroyed is rebuildable in minutes, from real data,
by a tool that drives the app's own stores. That unblocked ADR-0020's AniList arm, whose run
closed the one claim the ADR had been accepted without, and surfaced a question about the two
reverse-resolution consumers that was then measured and answered *no change*. Along the way the
project's simulator moved to iPhone 17 Pro (pinned by id, not `booted`), recommendation seeds
stopped throwing away MAL ids the Works already held, and CLAUDE.md stopped telling every
session to read a code-review file that is never written here.

## Re-seeding the simulator

```sh
./scripts/seed-simulator.sh            # refuses if a fixture is already there
./scripts/seed-simulator.sh --force    # replace it
```

Backs the container up to `.simulator-backups/` (gitignored) **before** arming, never calls
`simctl erase`, and reports through `queue-status.sh` afterwards. Device is `iPhone 17 Pro`,
overridable with `SEED_SIMULATOR_DEVICE`.

**How it works, and why it looks odd.** The seeding is a *test*
(`SimulatorSeedTests.testSeedTheSimulatorInPlace`) because only a test can drive `WorkStore`,
`HistoryStore` and `LibraryStore` — hand-rolling `works.json` would be a second definition of
the on-disk shape. The unit test target is hosted by the app, so that test already runs inside
the container it seeds and **writes in place**. The script's whole job is the part a test
cannot do: resolve the device, back up, drop the marker file that arms the run, and report.

The gate is a marker file because **`xcodebuild` forwards no environment into the test
process** — verified with and without the `TEST_RUNNER_` prefix, for unit tests and UI tests
alike. Anything a test needs from outside has to arrive as a file.

The fixture itself is 22 Works harvested from live MangaDex + AniList
(`scripts/harvest_seed_fixture.py`, three stages: `probe` / `fetch` / `emit`).
`scripts/seed-harvest.json` is the committed raw harvest; `SimulatorSeedFixture.swift` is
generated from it and is typed, so a `Row` shape change fails to compile rather than decoding
into something quietly wrong.

## ADR-0020 is fully discharged

The AniList arm ran under [its own protocol](../specs/2026-08-20-adr-0020-anilist-arm-protocol.md)
([results](../specs/2026-08-20-adr-0020-anilist-arm-results.md)), registered before any
instrumented launch as the chain requires.

- **The N = 3 cap claim closed.** *+Anima* held four spellings, issued exactly three searches,
  recovered at query 3 — stopped at the bound rather than spending what it had. That was the
  one registered claim the ADR was accepted without.
- **The AniList arm's own floor stayed unmet**, for a reason worth more than the floor: 10 of
  12 pool targets were already in the shared reverse cache, put there by the MAL arm earlier in
  the same session.
- **The full chain was seen visually for the first time**: *Mugen no Juunin* recovered as
  "Blade of the Immortal" and renders as the first For You card.

That overlap became [its own measurement](../specs/2026-08-20-reverse-arm-ordering.md), verdict
**no change**: the two arms' first spelling is the same one (30 of 32 targets; the two
disagreements both hit anyway), so ordering does not change whether the baseline hits — only
who pays to widen, on a population measured at zero. Harness `scripts/arm_ordering.py`, and
three named conditions would reopen it.

## Gotchas this session paid for

- **`simctl ... booted` is a trap.** It answers about whichever device is booted, and Xcode
  boots others on its own schedule. Two ADR-0020 launches were lost reading an unseeded
  container on the wrong device while everything looked normal. Resolve the udid by name and
  address every call by id — `seed-simulator.sh` now does.
- **`simctl spawn defaults export` reads nothing for a sandboxed container.** It returns an
  empty dict whether or not the domain has contents, which is why an earlier session concluded
  the app's defaults domain "does not exist". Read
  `<container>/Library/Preferences/Elias-Magdaleno.Manga-Reader.plist` instead.
- **CoreSimulator rotates the data container's UUID** when `xcodebuild` reinstalls the app,
  carrying contents across. A path resolved before a test run is stale after it.
- **A stale `entityResolution.reverseCache` silently disables reverse resolution.** 107 answers
  from earlier sessions meant two runs produced an empty log against a fully built pool.
  `SimulatorSeed.clearInheritedState` now clears it during seeding.
- **MangaDex answers a search for a title it does not carry with whatever it does carry.**
  "Monster" returns *Futsuu to Bakemono*. The harvest demands an exact normalized match.
- **Licensed series are unreadable, not absent** — their chapters survive as external links to
  an official reader. Both the harvest and `probe` pass `includeExternalUrl=0`.
- `curl -g` for any MangaDex array parameter; `json.loads(..., strict=False)` for any MangaDex
  description.

## What is worth doing next

Nothing is queued. In rough order of value:

1. **Per-chapter read/unread marks** — the largest item on CLAUDE.md's own "still minimal"
   list, and the seeded fixture now makes it testable against a realistic library.
2. **Prove the recovery path** — `simctl erase` the old `iPhone 17` (which still holds a
   seeded fixture as an accidental backup), re-seed from scratch, and confirm the tool works
   before it is needed in anger.
3. **Backdate seeded history.** `HistoryStore.record` stamps `Date()` with no backdating hook,
   so the fixture reads as one day and the History tab shows a single date header. Order and
   position are correct, which is what the recommender reads, so this is cosmetic until
   something needs realistic dates.
4. **Reverse resolution beyond MangaDex** stays parked — measured and rejected 2026-08-15;
   reopening needs its own registered protocol.
