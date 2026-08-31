# Handoff — the recovery path is proven

Session of 2026-08-20 (afternoon). Follow-on to
[the morning's handoff](2026-08-20-fixture-rebuilt-adr-0020-closed-handoff.md), whose item 2
this discharges. `main` is at `5c83c51`; three PRs merged (#64, #65, #66); no open PRs or
issues.

## The one-paragraph version

The seeding tool rebuilds the fixture from nothing — verified against a device that had
never held the app, rather than by erasing the one device acting as an accidental backup.
It works, with one prerequisite the morning's handoff did not mention. Separately, the
read/unread rule changed the same day (#65), which quietly moved the fixture's read surface
from 18 chapters to 14; anything that verified against the old number will read that as a
regression and should not.

## What was run

```sh
SEED_SIMULATOR_DEVICE="iPhone 17e" ./scripts/seed-simulator.sh
```

**Recovery on a virgin device is two steps, not one.** The script refuses when no container
exists — correctly, and it names the fix:

```
no container for Elias-Magdaleno.Manga-Reader on iPhone 17e.
run the app there once (or xcodebuild test against it) to install it first.
```

So: `xcodebuild test` against the target device to install the app, *then* seed. The script's
own header documents this; the morning handoff's one-line summary of it did not. On the
already-installed `iPhone 17 Pro` the distinction never came up.

## Result

Everything the tool claims to do, it did:

- **22 Works seeded**, 20 resolved to AniList, **AniList pool gate PASS**, attempt memory
  suppressing 2 (1 `absentFromProvider`, 1 `unmatched`).
- **All three defaults keys landed** — 18 `history.entries`, 12 `library.items`, 0
  `history.readMarks`.
- **`entityResolution.reverseCache` is absent.** `clearInheritedState` did its job; a stale
  cache here is what silently produced two empty ADR-0020 logs against a fully built pool.
- Container backed up to `.simulator-backups/2026-08-20-141657` **before** arming.

`iPhone 17 Pro` was not touched. The old `iPhone 17` was left alone during the verification
itself, and erased only afterwards — see below.

## Why not the erase test the morning handoff proposed

It proposed `simctl erase`-ing the old `iPhone 17` and re-seeding it. That risks the asset to
test the tool: erasing is the one irreversible step, and that device was the accidental
backup. Seeding a never-seeded device proves strictly more — a container with *nothing* in it
is the harder case than one with stale state — and destroys nothing.

The fixture's real source of truth was never on any simulator: `scripts/seed-harvest.json`
and the generated, typed `SimulatorSeedFixture.swift` are both committed. Plus
`.simulator-backups/` held four full backups before this run.

The device was erased in the end anyway — but *after* the rebuild was proven, not as the way
of proving it. That ordering is the whole point.

## The finding worth carrying: the fixture's read surface moved

**4 of the 18 seeded history entries are mid-chapter** — `Kingdom` ch492.5 at 3/6,
`Kaguya-sama` ch2 at 3/19, and two others. Under `isRead`'s old meaning (*opened*) all 18
counted as read. Under #65's rule (*read to the end*, `ReadingEntry.isComplete`) **14 do.**

That is the new rule working correctly on realistic data: those four render as in-progress
with resume markers and count toward the unread badge. But any verification that hard-coded
"18 chapters read" against this fixture will now see 14 and read it as a regression. It is
not one.

## The old `iPhone 17` was reclaimed

Erased after the verification above, once the rebuild was proven rather than assumed — which
is the order that matters, since erasing is irreversible and that device had been the
accidental backup.

Its container was copied to `.simulator-backups/2026-08-20-iphone17-preerase/` first (40K:
`works.json`, `upgrade-attempts.json`, `defaults.plist`). Backing up before touching a
container is what `seed-simulator.sh` itself does, and skipping that step is how a previous
session destroyed `works.json`.

Verified afterwards: 0 app data containers, 0 Manga-Reader files, and `iPhone 17 Pro` still
holding its 22 Works. The container had also accumulated one leftover UserDefaults suite per
test run (`test.reverse.*`, `test.minting.*`, `test.history.*`, …); those went with it, which
is the actual reclaim.

## What is worth doing next

1. **Decide what to do with the seeded `iPhone 17e`.** It is a working fixture now, which is
   harmless but makes two seeded devices, and the project pins `iPhone 17 Pro` deliberately
   (`simctl ... booted` picking the wrong device has cost runs before).
2. **Backdate seeded history** — unchanged from the morning handoff: `HistoryStore.record`
   stamps `Date()` with no backdating hook, so the History tab shows one date header. Cosmetic.
3. **Reverse resolution beyond MangaDex** stays parked — measured and rejected 2026-08-15.
