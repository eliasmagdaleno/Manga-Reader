# Handoff — simulator re-seeding, complete

Branch `simulator-seeding`, rebased onto `main` (ddbb3b7). Seeding commits: `6ae89c1`
(builder + Works), `c6df4a7` (history + library), `8bcf72f` (refusals), `9e162b1`
(in-place run + script), `6da4781` (the harvest). **All six steps are done; the branch is
ready for a PR.**

## Context

The seeded simulator was destroyed by `simctl erase` during the ADR-0020 work. Lost:
`works.json` (107 Works, 86 with a MAL id), a 25-entry history, `upgrade-attempts.json`. The
loss blocks the **AniList arm** of ADR-0020 Decision 5, whose pool needs a taste profile, and
it will block anything else that wants realistic on-device state.

This branch builds a re-seeding tool so the next erase costs minutes, not a subsystem.

## The design (approved)

A Swift seeding routine in the **test target** drives the real store types. Real encoders, so
no drift; no live network, so it is deterministic and fast; tag data comes from a committed
snapshot that is regenerated deliberately.

*Amended at step 3 (see below):* the original plan had the routine write to a temp directory
and a shell script copy the result into the container. It writes **in place** instead — the
test already runs inside the container — and the script's job shrank to backup and arming.

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

### Step 1 — history, library, and the defaults payload (`c6df4a7`)

- `Row` gained `reading: [Read]` (chapterId / number / page / pageCount) and `isSaved`.
- `apply(_:to:history:library:)` drives `HistoryStore.record` and `LibraryStore.toggle` with
  the **same `Manga` listing** it minted from, so reading and saving resolve to the Work the
  AniList upgrade already stamped rather than minting a provisional, snapshot-less twin. A
  test asserts exactly that.
- `history.flush()` after the run: `record` writes through a throttle, so without it the run's
  writes never land. **Mutation-checked** — deleting the flush reddens both defaults tests.
- `SimulatorSeed.seededDefaultsKeys` + `defaultsPayload(from:)` → key -> base64, for the
  script's `simctl ... defaults write -data <hex>` step. Only the three seeded keys travel
  (`history.entries`, `history.readMarks`, `library.items`); the suite also collects
  Foundation's own bookkeeping, and the `taste.*` keys hold explicit user feedback a fixture
  has no business inventing — pre-dismissed titles would silently subtract from every
  recommendation run made against the fixture.

  *`defaultsPayload` was deleted at step 3 — nothing copies defaults any more.
  `seededDefaultsKeys` survives, now as the set the in-place run clears first.*

482 unit tests pass (1 pre-existing skip).

**Known limitation, documented at the call site:** `HistoryStore.record` stamps `Date()` and
offers no backdating hook, so the seeded history reads as a single day — the History tab shows
one date header. Order and position are still correct (`record` prepends; rows apply
oldest-first), and those are what the AniList arm reads. Backdating would mean either a new
seam in `HistoryStore` or hand-writing the entries, and neither is worth it for a date header.

## Superseded: the `simctl defaults` spike

An earlier spike established that `xcrun simctl spawn booted defaults write <domain> <key>
-data <hex>` round-trips real `Data` into a simulator app's defaults, and concluded from an
empty `defaults export` that the app's own domain did not exist. **Both halves are moot and
the second was wrong** — see step 3 below. Nothing writes defaults through `simctl` any more,
and `export` returns an empty dict for a sandboxed container whether or not the domain has
contents.

### Step 2 — upgrade-attempt refusals (`8bcf72f`)

`Row.refusal: UpgradeOutcome?`. A refused row is left **provisional** — the AniList upgrade
is skipped — because a Work carrying both a snapshot and a refusal is a state no drain could
produce. Two refusal rows, one of each shape: `.unmatched(knownTitlesCount: 1)` on a row with
no MAL id, so it genuinely suppresses (an authoritative id would release it, which is the
ADR-0018 behaviour worth having in a fixture), and `.absentFromProvider`. `apply` gained an
`attempts:` parameter and flushes it. Two tests, **mutation-checked** — deleting the flush
reddens the round-trip test.

### Steps 3 and 5 — the in-place run and the script (`9e162b1`)

**The design changed here, with approval.** The run writes straight into the booted
simulator's app container instead of staging files for a script to copy.

Why: the unit test target is **hosted by the app**, so the test process already runs inside
the container the fixture is for. `WorkStore.applicationSupportDirectory()` inside a test
resolves to the simulator container's Application Support, and `UserDefaults.standard` is the
app's own domain — both verified by printing them and matching against
`simctl get_app_container booted Elias-Magdaleno.Manga-Reader data`. That retires
`defaults.json`, the base64 payload and the `simctl defaults write -data <hex>` step.
`defaultsPayload` is deleted; `seededDefaultsKeys` survives as the set the run **clears
first** (seeding onto an existing fixture would merge, not replace) and has its own test
against the suite's persistent domain.

**`SEED_SIMULATOR_OUT` could never have worked.** `xcodebuild` forwards no environment into
the test process — verified empty with the plain name and with the `TEST_RUNNER_` prefix. The
gate is now a **marker file** (`Documents/seed-simulator.marker`) that the script drops into
the container and the test consumes on the way in. CI and ordinary `xcodebuild test` runs
skip, which is the property a destructive run needs.

`scripts/seed-simulator.sh` does only what a test cannot: resolve the container, back it up
(to `.simulator-backups/`, gitignored) **before** arming, run the one test, disarm, and
report through `queue-status.sh`. It refuses to overwrite an existing fixture without
`--force`, treats a skipped test as failure (a skip exits 0, so it greps for the run's own
output line), and never calls `simctl erase`.

**Two corrections found by running it end to end:**

- **CoreSimulator rotates the data container's UUID when `xcodebuild` reinstalls the app**,
  carrying the contents across. The path resolved before the run is stale afterwards — the
  first run reported "no such works.json" about a container it had just seeded correctly.
  The script re-resolves after the run.
- **Last session's spike conclusion — "the app's defaults domain does not exist" — was
  wrong.** `simctl spawn booted defaults export <bundle-id> -` returns an empty dict for a
  *sandboxed* container: it reads nothing, rather than reporting an empty domain. The seeded
  keys are visibly in the container's own
  `Library/Preferences/Elias-Magdaleno.Manga-Reader.plist` (`history.entries`,
  `history.readMarks`, `library.items`). Do not use that command to check whether seeding
  worked; read the plist.

Verified end to end with `--force`: 5 works seeded, `queue-status.sh` reports 3 resolved to
AniList, **AniList pool gate PASS**, 2 suppressed by attempt memory (1 `absentFromProvider`,
1 `unmatched`). The app launches against the seeded container and renders Home. 485 unit
tests, 2 skipped (the seeding run plus the pre-existing one).

### Step 4 — the harvest (`6da4781`)

`scripts/harvest_seed_fixture.py`, three stages: `probe` (availability, no writes),
`fetch` (live pull -> `scripts/seed-harvest.json`), `emit` (-> the generated
`Manga-ReaderTests/SimulatorSeedFixture.swift`, no network). Two files committed so the
Swift can be regenerated offline after a shape change, and generated **Swift** rather than
a JSON resource so a `Row` change fails to compile instead of decoding into something
quietly wrong.

22 Works: 9 read (18 chapters), 12 saved, 2 refused. `Row` gained `coverURL` —
`ReadingEntry` and `LibraryItem` each persist one, so a fixture without covers is a
Library of grey rectangles.

**Three things the harvest taught, each now enforced in the script:**

- **An exact normalized title match or nothing.** MangaDex answers a search for a title it
  does not carry with whatever it *does* carry — "Monster" returns "Futsuu to Bakemono",
  "Blame!" returns "Black Jack Alive". The first run seeded both without complaint. The
  picker now aborts with the candidate list instead of taking the top result.
- **Licensed series are unreadable, not merely absent.** Their chapters survive as external
  links to an official reader the app cannot open, so both `probe` and the harvest pass
  `includeExternalUrl=0`. Vinland Saga, Death Note, JJK, Frieren, Spy x Family and Solo
  Leveling have **zero** readable English chapters — they are in the fixture as saved or
  browsed rows, and the reading half was authored around what is actually readable
  (Berserk, Vagabond, Chainsaw Man, Dorohedoro, Hunter x Hunter, Made in Abyss, Horimiya,
  Kaguya-sama, Kingdom).
- `curl -g` is required, or every MangaDex array parameter (`includes[]`,
  `translatedLanguage[]`) fails as a glob before a request is made; and `json.loads(...,
  strict=False)`, or one control character in a description rejects the whole response.

Two tests guard the generated file, since `sampleRows` covers the builder and nothing else
would notice a regenerated fixture arriving empty, coverless or pointing at ids that 404:
real UUID manga ids and covers on every row, both refusal shapes, reading that contains
both a finished chapter and an in-progress one, and >= 5 tag pairs clearing the gate.

### Step 6 — verified

`./scripts/seed-simulator.sh --force`: 22 works seeded, 20 resolved to AniList, pool gate
PASS, 2 suppressed by attempt memory. The app launches against it and **For You populates
with real basis lines** — "Because you read Made in Abyss", "Because you read Chainsaw
Man". 487 unit tests, 2 skipped.

## Left to do

Nothing on the tool. Open the PR, and the ADR-0020 **AniList arm** is now unblocked — that
run was what the fixture was rebuilt for.

Worth knowing before that run: the seeded history all carries today's date
(`HistoryStore.record` stamps `Date()` and offers no backdating hook), so the History tab
shows a single date header. Order and position are correct, which is what the arm reads.

## Gotchas worth carrying

- `WorkStore` is `@MainActor`-isolated — test helpers that build one must be too.
- **SwiftUI ships its own `LibraryItem`,** and `@testable import Manga_Reader` re-exports it,
  so decoding the library half needs `Manga_Reader.LibraryItem` — unqualified, it fails as
  "ambiguous for type lookup".
- **`flatMap(\.reading)` and friends do not compile here.** Key-path shorthand over
  `SimulatorSeed.Row` produced "cannot infer key path type from context" (and once, a
  compiler "failed to produce diagnostic" crash report); plain closures work.
- Both git branch creation and `gh pr merge` were blocked by the permission classifier this
  session; simple single commands worked where compound ones did not.
- **`xcodebuild` forwards no environment into the test process** — not plainly, not with the
  `TEST_RUNNER_` prefix. Anything a test needs from outside has to arrive as a file.
- **Test suites leak plists into the app container.** Every isolated `UserDefaults(suiteName:)`
  leaves an emptied plist in `Library/Preferences/`; `removePersistentDomain` empties it but
  does not delete it. The script sweeps `seed-*.plist` so the fixture ships clean.
- **PR #57 (ADR-0020 accepted) is merged** — `ddbb3b7` on `main`, branch deleted. This branch has
  been rebased onto it, so it is current; nothing is stacked.
- **The rebase conflicted once, in `project.pbxproj`,** and will again if this branch is rebased
  after another `xcp` write lands on `main`. Resolution both times: keep `main`'s normalized file
  reference (no `name =`, no `lastKnownFileType`) and add only the new file's entry. Those keys are
  the churn CLAUDE.md says Xcode strips on its own schedule — re-adding them is what creates the
  conflict, not anything about the seeding work. Post-rebase the pbxproj delta against `main` is
  exactly the 8 lines for the two new files, and 479 unit tests pass.
