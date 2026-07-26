# Session Handoff — 2026-07-26: ADR-0008 written, slice 3 steps 4–5 implemented

**Audience:** a fresh session continuing ADR-0007/0008. Supersedes
`2026-07-25-slice-3-steps-4-5-handoff.md`. That file's traps list still stands and is not
repeated here — read it for those.

## State

| | |
|---|---|
| Slice 3 steps 1–3 | merged (PRs #18, #19, #20) |
| **ADR-0008** — upgrade queue design | committed `9208bba`, branch `adr-0008-upgrade-queue`, **no PR yet** |
| **Step 4** — retire `taste.tagCache` | implemented + green, **uncommitted** |
| **Step 5** — `flush()` on `scenePhase` | implemented + green, **uncommitted** |
| Upgrade queue itself | not started — ADR-0008 is the spec |

`main` is at `7f1805e`. **223 unit tests pass, 0 failures** (`** TEST SUCCEEDED **`, iPhone 17,
`-parallel-testing-enabled NO`), plus the 14 UI tests. Baseline was 224; the net −1 is three tests
deleted, one renamed, two added.

## ADR-0008 — read it before writing the queue

`docs/adr/0008-upgrade-queue-resolution-and-drain.md`. It exists because ADR-0007's queue
**could not have worked**: a Work minted from a scraped source has no external id,
`AniListAPI` only looks up by MAL id, and provisional snapshots are permanently stale — so the
queue could dequeue those Works and have nothing to send.

Eight decisions, each with its rejected alternative. The ones that shape the code:

1. Resolution goes **MAL → malId → AniList**. AniList is never asked to search.
2. Resolution is **Work-level**; `knownTitles` is passed *into* the matcher as the source side, so
   each candidate scores over the title cross-product. **Do not** loop the existing single-title
   matcher and take the max — that routes around the ambiguity guard.
3. **Attempt memory** in the queue's own file, `WorkID → (checkedAt, outcome)` where outcome is
   `.unmatched(knownTitlesCount)` or `.absentFromProvider(malId)`. Transient failures record
   nothing. `.absentFromProvider` exists because otherwise the *fetch* stage has no memory and a
   Work whose malId AniList 404s is re-requested on every drain forever.
4. `TasteProfile.build` must expose `workWeights: [WorkID: Double]` — the ordering ADR-0007
   specified is currently unreadable outside the profile. Untagged Works sort last.
5. Own service (`Services/MetadataUpgradeQueue.swift`), **continuous foreground drain**, not
   batch-on-rail-build.
6. A completed drain does **not** rebuild the rail.
7. `reindexExternalIds` must **merge, not overwrite** — incumbent survives. See below.

**Verified live 2026-07-26, do not re-derive:** MyAnimeList publishes no rate-limit headers and
did not throttle 90 sequential `/v2/manga?q=` requests in 21s (~4.3 req/s). AniList's 30/min is
8.6× stricter. **No MAL limiter is built.**

## The live bug ADR-0008 documents but does NOT fix

`WorkStore.reindexExternalIds` (`WorkStore.swift:289-294`) assigns `externalIdIndex[key] = id`
unconditionally, reached from both `apply` and `setExternalIds`. If AniList returns `idMal: 123`
for Work A while `mal:123` already points at Work B, A wins the index and B survives with its own
Listings, unreachable by external id — the profile then counts two Works for one manga.

**This is unreachable today** and becomes reachable the moment Work-level resolution ships, because
nothing currently learns an external id after mint. **Fix it in the same change as the queue, not
after.** The fix is a merge with the incumbent surviving.

## What steps 4 and 5 actually did

### The contradiction I had to resolve

The previous handoff's step 4 said both "delete `TasteProfileStore.tagCache`" *and* "keep the
`tagCache` seeding branch in `resolveSignals()` for one release, it **is** the migration". Those
can't both happen — the branch reads the property.

**Resolved as: the cache became read-only legacy data.** Renamed `tagCache` → `legacyTagCache`,
`private(set)`, loaded at launch, **never written** (`save()` deliberately omits its key). Every
write path is gone; the read dies next release.

### Changes

- `TasteProfileStore` — `recordTags` and `mangaIdsMissingTags` deleted, `tagCache` →
  read-only `legacyTagCache`, `save()` no longer writes `taste.tagCache`.
- `MangaDetailView` — the `sourceId == "mangadex"` dual-write is gone, and with it the
  `tasteProfile` `@EnvironmentObject`. `works.noteListingTags` stays.
- `RecommendationEngine` — `scheduleBackfill()`, `backfill(ids:)`, `backfillBatch` deleted;
  `resolveSignals` reads `legacyTagCache`. Header comment now points at ADR-0008.
- `Manga_ReaderApp` — `@Environment(\.scenePhase)` + `.onChange` calling `works.flush()` on
  `.background`. (Step 5, whole thing.)
- Tests — engine tests now seed through the **real** path (`makeWorkStore()` + `tagRead()` helper:
  `noteListingTags` stages, `resolveSignals`'s mint consumes) instead of `taste.recordTags`.
  `makeEngine` gained a `workStore:` parameter. `DetailStubSource` and the backfill test deleted.
  Two new tests: `testLegacyTagCacheLoadsButIsNeverWrittenBack` and
  `testLegacyTagCacheSeedsWorksSoTheProfileSurvivesUpgrade`.

### Method note, stated honestly

Step 4 is a **deletion refactor, not red-green TDD** — once `recordTags` is gone, "nothing writes
the cache" is a compile-time fact, not a testable behavior. The discipline that applied was a
characterization test pinning the migration before deleting around it. Don't let the absence of a
red phase here get read as skipped TDD; the queue itself is genuinely new behavior and *does* want
red-green.

## Next

1. Commit steps 4–5, open the PR for `adr-0008-upgrade-queue` (docs + steps 4–5 together, or split —
   CI only runs on PRs targeting `main`, so **don't stack**).
2. Build the queue per ADR-0008, including the `reindexExternalIds` merge fix.

## Gotchas found this session

- **The previous handoff's "four manual pbxproj edits" trap is now obsolete.** `xcp`
  (XcodeProjectCLI 1.2.1) is installed and CLAUDE.md documents the command. Verified
  end-to-end: added a probe test file, it compiled and ran, `delete-file` removed all four
  entries. One caveat, also in CLAUDE.md — every `xcp` write reformats the three
  `PBXFileSystemSynchronizedRootGroup` entries to multi-line (~27 lines of unrelated diff).
  This matters immediately: splitting `Manga_ReaderTests.swift` is on the list.
- **`CLAUDE.md` was already dirty at session start** — a condensing edit that is not mine and is
  deliberately excluded from every commit here. Don't sweep it in.
- **The `@MainActor` orphan.** Editing out a function body whose attribute sits on its own line
  leaves the attribute attached to whatever you insert next — produced "declaration can not have
  multiple global actor attributes ('MainActor' and 'MainActor')". Check the line above your anchor.
- **SourceKit false alarms remain constant** ("No such module 'XCTest'", "Cannot find type 'Tag' in
  scope"). Judge only by `xcodebuild`.
- `/grilling` and `/domain-modeling`, which `.claude/skills/grill-with-docs` delegates to, are
  **not installed on this machine**. The session ran the workflow from the convention the existing
  ADRs establish. Installing them would make future `/grill-with-docs` runs faithful.
- **User feedback, now in memory:** lead with the short question; supporting evidence goes behind
  it, not in front. Long option-analysis preambles bury the ask.
