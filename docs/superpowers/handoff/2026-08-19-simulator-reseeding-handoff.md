# Handoff — simulator re-seeding, first slice done

Branch `simulator-seeding`, based on `main` (4bbba9e). One commit: `d48c0dc`.

## Context

The seeded simulator was destroyed by `simctl erase` during the ADR-0020 work. Lost:
`works.json` (107 Works, 86 with a MAL id), a 25-entry history, `upgrade-attempts.json`. The
loss blocks the **AniList arm** of ADR-0020 Decision 5, whose pool needs a taste profile, and
it will block anything else that wants realistic on-device state.

This branch builds a re-seeding tool so the next erase costs minutes, not a subsystem.

## The design (approved)

A Swift seeding routine in the **test target** drives the real store types against a temp
directory; a shell script copies the result into the simulator container. Real encoders, so no
drift; no live network, so it is deterministic and fast; tag data comes from a committed
snapshot that is regenerated deliberately.

Rejected: hand-writing the JSON (drifts from `Work`'s shape silently) and driving the whole
thing through XCUITest (minutes per run, live-API dependent).

## Corrections to the design made while reading the code

- **`works.json` and `upgrade-attempts.json` live in Application Support, not Documents.**
- **`anilist-pool.json` and `anilist-tag-vocabulary.json` live in Caches and must NOT be
  seeded** — they rebuild themselves. The file half of the fixture is two files, not four.
- The UserDefaults half is `history.entries`, `history.readMarks`, plus the library and taste
  profile keys.

## Done

`Manga-ReaderTests/SimulatorSeed.swift` + `SimulatorSeedTests.swift` (both added to the target
with `xcp`; the pbxproj diff was a clean 8 lines).

- `SimulatorSeed.Row` — a Listing plus the AniList record that upgrades it.
- `SimulatorSeed.apply(_:to:)` — mints through `WorkStore.mint`, upgrades through
  `WorkStore.apply`, the same route `MetadataUpgradeQueue` takes.
- Two tests: per-row bookkeeping, and that the seed clears `TagPairSeeding`'s ≥ 3-contributing-
  Works gate. **The gate test was mutation-checked** — dropping one Tragedy rank 70 → 40, under
  the ≥ 60 floor, collapses the best pair to 2 and reddens it.

479 unit tests pass.

## Verified mechanism (spike)

`xcrun simctl spawn booted defaults write <domain> <key> -data <hex>` round-trips real `Data`
into a simulator app's UserDefaults — wrote a 49-byte JSON payload to a throwaway domain and
read the exact bytes back. This is how the history half gets written. The app's own domain
(`Elias-Magdaleno.Manga-Reader`) currently **does not exist**, confirming the defaults half of
the fixture is empty.

## Left to do

1. **History and library rows** — extend `Row`/`apply` to emit `ReadingEntry` values and library
   items, encoded by the real Codables, into a `defaults.json` (key → base64).
2. **Upgrade attempts** — 2–3 rows including one refusal, so the ADR-0018 guard has something to
   release.
3. **`SEED_SIMULATOR_OUT` run** — the test that writes `works.json`, `upgrade-attempts.json` and
   `defaults.json` to a directory, skipped unless that env var is set.
4. **The harvest** — a one-time live pull of real AniList tags/ranks for ~20 titles into a
   committed snapshot, replacing `sampleRows` as the real fixture. `sampleRows` stays for unit
   tests.
5. **`scripts/seed-simulator.sh`** — locate the booted iPhone 17 and the container, run the test,
   copy into Application Support, apply the defaults, **back up the existing container first**,
   refuse to overwrite without `--force`, and never call `simctl erase`.
6. **Verify** by launching the app and confirming For You populates; then the AniList arm run.

## Gotchas worth carrying

- `WorkStore` is `@MainActor`-isolated — test helpers that build one must be too.
- Both git branch creation and `gh pr merge` were blocked by the permission classifier this
  session; simple single commands worked where compound ones did not.
- **PR #57 (ADR-0020 accepted) is green and mergeable but NOT merged.** This branch is based on
  `main` without it, deliberately, so nothing stacks.
