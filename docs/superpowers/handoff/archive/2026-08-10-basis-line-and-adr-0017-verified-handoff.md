# Session Handoff — 2026-08-10: the basis line shipped, ADR-0017 verified in the app

**Audience:** the next session. Supersedes `2026-08-10-adr-0016-rejected-0017-shipped-handoff.md`,
whose pickup list is drained: item 1 (push `mal-novel-filter`) merged as #37, item 2 (watch the
remaining refusals) is answered below with live data.

## State

| | |
|---|---|
| `main` | **`59da811`** — "Stop novels refusing their own adaptations (ADR-0017) (#37)", clean |
| PR **#38** `foryou-basis-count` | 3 commits, **CI green both jobs**, unmerged — merge this first |
| Branch **`mangadex-alt-titles`** | **now pushed to `origin`** (`19a6ecd`). Still rejected, still do not merge |
| ADRs | 0001–0015 Accepted (0015 amended 7 & 8), 0016 Rejected, 0017 Accepted **+ verified** |
| Tests | 445, 1 skipped, 0 failures |

## What shipped (PR #38, three commits)

1. **`RailState.ready(tagged:of:)`** and a line under the For You rail: *"Based on 6 of 10 titles
   you've read."* Recorded as ADR-0015 **amendment 7**. Hidden at parity — an unconditional line
   becomes wallpaper.
2. **ADR-0015 amendment 8** — the ceiling test needed a reading precondition. Amendment 3 claimed
   the ceiling test *subsumed* the "enough read Works" clause; it deletes it, so zero reading gave
   `noTaggableSignal` and a first-launch reader was told their history couldn't be matched.
3. Docs recording the in-app verification below.

## The finding: ADR-0017 works, measured in the app

Simulator seeded with seven real MangaDex titles read, alongside the three untaggable WeebCentral
placeholders already present. The app's own upgrade queue resolved them live against MAL; every
resolved id was checked against MangaDex's `links.mal` for that title.

**6 correct, 0 wrong, 1 refused.** The refusal is `Wind Breaker` — Hazard 1, exactly as specified.

The mechanism, not just the outcome — MAL's raw candidates today:

```
Jeonjijeok Dokja Sijeom  →  143441 novel  "Omniscient Reader's Viewpoint"  ← ranked FIRST
                            132214 manhwa "Omniscient Reader's Viewpoint"
Wind Breaker             →  133081 manga  "Wind Breaker"
                            103237 manhwa "Wind Breaker"        ← two comics, no novel to filter
```

ORV's novel twin is still there, still identically titled, still ranked above the manhwa — so the
ambiguity guard would still tie without the filter, and the app resolved it correctly with one.
Wind Breaker's collision is two comics, which the filter cannot and must not touch, and it refused.

**Hazard 2 is undiminished.** Seven titles, same author, three lifted from the original twelve. The
mechanism is confirmed to run in the app on live data; the sample is not wider.

**ADR-0016 stays rejected, now with positive evidence.** Its revisit trigger is refusals where the
top MAL candidate scores *below 0.90* rather than tying. The one refusal produced was a tie. Second
independent observation pointing the same way; `mangadex-alt-titles` stays parked (and is now on
`origin`, so it is no longer single-copy on one disk).

## What to do first

1. **Merge PR #38.** CI green, nothing blocks it.
2. **Then `malId` on `LibraryItem`** — and the seeding run sharpened the argument for it. MangaDex
   returns `links.mal` in the response the app *already fetches* (Berserk → 2, ORV → 132214, all
   seven, free). `resolveSignals()` throws it away: it rebuilds every `Manga` from a history entry
   with `malId: nil`, so the queue re-derives by fuzzy title search, through the matcher, with an
   ambiguity guard that refused 1 in 7. **We run a fuzzy match to recover an id the API handed us.**

## The mistake worth carrying forward

I reported a bug that wasn't the one I'd observed. I dumped the simulator's prefs plist, saw no
`history.entries` key, and told the user the app was showing the dead-end notice to a reader with no
history. The key was absent because `cfprefs` hadn't flushed and because I'd read the *pre-reinstall*
container. The live value, printed from `rebuild()`, was 3 — three WeebCentral placeholders, all
unmatchable, so `noTaggableSignal` was **correct** and the screenshot showed the feature working.

The underlying defect was real and is fixed (a unit test goes red on the old engine), but it was
found by reasoning and proved by test, **not** by the observation I claimed. This is ADR-0015's
recurring failure again — *a claim about current behaviour is not verified until the line asserting
it has been opened.* **A `plutil` dump is not that line.** ADR-0015 amendment 8 records both the
defect and the false story, deliberately.

## Method worth reusing: seeding the simulator

This is the thing that finally made in-app verification possible, and it is cheap:

- Write `history.entries` straight into the sim's defaults:
  `xcrun simctl spawn <UDID> defaults write Elias-Magdaleno.Manga-Reader history.entries -data <hex>`.
  It is a JSON blob of `ReadingEntry`; `updatedAt` is a Double in **Apple epoch** (2001-01-01).
- Read it back with `defaults export <domain> -` piped to `plistlib`. **Do not** read the container
  plist off disk — that is what caused the misdiagnosis above.
- The app mints the Works itself on launch and the upgrade queue resolves them. Give it ~60s, then
  **relaunch** — the rail only rebuilds on `load()`/refresh, so the first launch shows the pre-tag
  state.
- `works.json` in `Library/Application Support/` is the ground truth for what got tagged:
  `externalIds.mal` and `snapshot.genres`.
- Verify ids against MangaDex's own `links.mal`. A recovery count that includes false matches is
  worse than no measurement (the prior session's lesson, still true).
- `api.mangadex.org` still rejects Python's `urllib` TLS; shell out to `curl`. MAL's client id is in
  `Secrets.xcconfig` (gitignored).
- Keep untaggable entries in the seed. A *mixed* library is what makes the basis line say anything.

The simulator (`iPhone 17`, `2A0D54DF-…`) still holds this seeded history, so the rail stays open
there for future checks.

## Gotchas

Prior handoffs' lists still apply. New or reconfirmed:

- **`project.pbxproj` churned 34 lines during an `xcodebuild` run** with Xcode open and was reverted
  before staging. The CLAUDE.md warning is accurate and was earned again this session.
- **`ForYouBasisNotice.swift` needed no `pbxproj` edit** — `Views/Components/` is synchronized.
- **Diagnostic `print` in `rebuild()` + `simctl launch --console-pty`** is how the live state was
  finally obtained. `timeout` does not exist on this machine; background the launch and sleep.
- The mutation check promised for the basis denominator **cannot go red**: `resolveSignals()` builds
  every signal from a history entry, so `!$0.entries.isEmpty` is vacuous. Documented as vacuous in
  code and ADR rather than presented as verified. The load-bearing half (excluding saved items) does
  go red.

## Also open, unchanged

- More Like This reverse-resolution beyond MangaDex-only.
- No automated coverage of `HomeView`'s rail branch or `MangaDetailView`'s notice branch — both
  deliberate, reasoning in `AppCompositionTests`' header. The new basis line is in the same
  uncovered branch, by the same decision.
- **The mixed-library question is now askable but unasked.** The three WeebCentral entries are
  placeholders with invented titles, so their untaggability proves nothing about WeebCentral.
  Reading three *real* WeebCentral titles would show whether that source is resolvable at all —
  which is the actual content of `noTaggableSignal` and untouched by any measurement so far.
- **ADR-0015's mixed-library hazard** is now *partly* addressed: the thinness is reported, not
  fixed. The rail can still be built from an eighth of the taste; the reader is merely told so.
- **Standing constraint:** the extension/repo system and comix.to are shelved since 2026-07-21.
