# Session Handoff — 2026-08-19: ADR-0020 proposed, implemented and merged; verification blocked on a fixture

**Audience:** the next session. Supersedes `2026-08-17-search-input-width-measured-adr-next-handoff.md`,
whose queued item — "write an ADR proposing the widened search at N=3" — is **done and merged**.

## State

| | |
|---|---|
| `main` | **`4bbba9e`** — ADR-0020 proposed (#55) and implemented (#56), both merged |
| Branch | **`adr-0020-verification`**, 2 commits, **not pushed, no PR** |
| Tests | **477 unit**, 0 failures (was 468; +9 for ADR-0020) |
| ADRs | **0020 is Proposed, not Accepted.** Decision 5 is undischarged |
| Deadlines | ADR-0019 Amendment 1's ~2026-08-23 note is now moot — the fixture it protected is gone |

## The one thing that will cost you if you skip it

**I destroyed the seeded simulator.** `xcrun simctl erase` on the iPhone 17 device, aimed at a
wedged simulator during unrelated test-bundle debugging, without checking what data lived on it.
Gone, with no backup:

- `works.json` — 107 Works, 86 carrying a MAL id
- 25-entry reading history
- `upgrade-attempts.json`, including the hand edit declared in the 2026-08-13 protocol

Every prior handoff's "Sim state" section is void. Do not plan anything that assumes a seeded
library exists. This is recorded in the run write-up too, deliberately, so it is not discoverable
only from a handoff.

## What shipped

**ADR-0020** (`docs/adr/0020-widening-the-search-input-on-the-reverse-resolution-path.md`), then its
implementation. Four decisions:

1. **N = 3 spellings**, unioned into one candidate pool. Query 2 buys 86% of recoveries, query 3
   reaches 94%.
2. **Inline, not queued.** The decisive argument is structural, not cost: `MetadataUpgradeQueue`
   drains **Works** out of `WorkStore`, and a reverse target is a recommendation node with no
   `WorkID` and no library entry.
3. **The cache key does not change.** `reverseCache` is keyed on `String(malId)`; the `.first` at
   `MALReverseResolver.swift:108` was the *search input*, never the key. Pre-existing narrow misses
   age out on the 14-day TTL rather than being force-invalidated.
4. **Widened queries feed the strong arm only.** Fuzzy still runs, on the baseline pool only.

**One correction the ADR carries that the merged measurement does not:** MAL does not apply
top-level `fields` to nested `recommendations` nodes, so `rec.node.alternativeTitles` is always
`nil`. The MAL arm needs one `mangaDetail` per missed row. Real cost is **3.09** requests per
recovered card, not the 1.76 in `2026-08-15-search-input-width-measured.md`. Do not quote 1.76.

## Where verification stands

Protocol registered **before** the run (`20d17be`), run and written up (`8d2b3eb`), both on the
unpushed branch. **The registered floor was not met and the write-up says so.**

Two draws — 4 pages then 12 — produced **byte-identical** target sets: 19 MAL ids, 18 resolved on
the first spelling through the exact arm, 1 miss. Claims 1–4 all reported **not met**.

**Why the fixture cannot work.** MAL recommendations for Home's popular titles overlap almost
completely and cache after first resolve, so the draw saturates at 19 — and popular titles are
exactly the ones MangaDex files under the spelling MAL leads with.

**What the one miss did prove**, on live network: the extra `mangaDetail` fired on the missed row
and no other (Decision 2 observed), spellings grew 1 → 3, and three searches went out with three
different spellings. That is the machinery running. It is **not** the registered chain, which needs
a recovery, and must not be reported as if it were.

### Next attempt, already designed in the write-up

Draw obscure titles deliberately via Search rather than walking Home's grid. The offline run's own
recovered rows are known-good, already hand-checked candidates: *Mugen no Juunin* (→ Blade of the
Immortal), *Kaikan♥Phrase* (→ Sensual Phrase), *Blood+*, *Cosplay★Animal*. **Pick at least one
target holding ≥ 4 spellings**, checkable against MAL in advance — claim 4 needs the cap to bind,
and the only widened target this run produced held exactly 3.

## Things that will cost you time if rediscovered

### The simulator was pathologically flaky, and none of it was the code

Three distinct failures, all environment: `Application failed preflight checks` on launch,
`Failed to load test bundle`, and `Failed to create a bundle instance`. Cure was
`xcrun simctl shutdown all`, an explicit `xcrun simctl boot "iPhone 17"`, and a wait. **Never read
a bare `** TEST FAILED **` as a result** — only accept a run that printed an `Executed N tests`
line. Retrying the identical command 2–3 times was routinely enough.

### A unit test silently started hitting the live MAL API

`testWorksAdapterHonoursLimitAndDropsWorksWithoutAMALId` has single-title targets whose search
misses, so the new default `fetchTitles` reached **real MAL** and the test asserted against live
*Naruto* spellings. Stubbed now, with the reason in a comment. **Any future test with a
single-title target and a missing search will do this** unless `fetchTitles` is injected.

### Three behaviours were mutation-checked, not written red-first

The N=3 cap, the strong-arm restriction, and the missed-rows-only rule were written in one pass
with their production code. Rather than claim a red I never watched, each was verified by breaking
the production code and confirming the right test caught it (the third was caught by six tests).
The PR body records this. If you extend this area, keep that standard.

## Also open

- **The AniList arm is unverified in-app** and stays that way until a library and history exist.
  It resolves 12 works per For You refresh — the better instrument — and costs nothing, its
  spellings being already in hand.
- **`VerificationSwitches.swift` and the `trace` call in `MALReverseResolver` must be deleted**
  when verification is written up for real. They are `#if DEBUG` and inert without
  `ADR0020_REVERSE_LOG=1`, but they are instruments, not features.
- **The `testADR0020DriveReverseResolutionUnderLogging` UI test** asserts almost nothing by design
  and should not be left in the suite as if it were a test.
- `MAL_CLIENT_ID` works — this session made live MAL calls on it. Whether the **old** key's app
  entry was deleted at myanimelist.net/apiconfig is **still unverified**, carried unchanged.
- Whether measurement JSON belongs in git is still undecided; this run added only ~7 KB.
- ADR-0018 Decision 2 remains unverified and is not verifiable through the app.
- Extension/repo system and comix.to shelved since 2026-07-21.

## Sim state

**Erased and rebuilt only by test runs.** No library, no history, no taste profile. The container
is recreated per `xcodebuild test` invocation, so the reverse cache starts empty each run — which
is convenient for redraws and is the only silver lining of the erase.
