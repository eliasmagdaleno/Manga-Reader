# Handoff — Cross-Source Recommendations (MyAnimeList track)

**Audience:** a fresh session continuing this initiative. This file is self-contained —
you should not need the prior chat.

## Mission

Build a Netflix-style **"More Like This"** tab on the manga detail page, and eventually
extend the on-device recommendation engine past MangaDex-only. Both depend on a
source-independent notion of "this is the same manga," which MyAnimeList (MAL) provides
as the canonical identity/metadata backbone.

This is a **three-subsystem** effort. Subsystem 1 is done; subsystems 2 and 3 are not
started.

1. **Read-only MAL client — DONE**, merged to `main` at commit `41e192c`.
2. **Cross-source entity resolution — NOT STARTED.** This is the next thing to build.
3. **"More Like This" UI + extending the recommendation engine — NOT STARTED.**

## Start here

1. Read the roadmap memory for full context and the reasoning behind this priority:
   `~/.claude/projects/-Users-eliasmagdaleno-xcode-Manga-Reader/memory/recommender-roadmap.md`
   (also see `multi-source-roadmap.md` in the same directory — it records why the
   Paperback/Aidoku-style extension system and comix.to were explicitly shelved in favor
   of this track).
2. Read the MAL client's design spec, which subsystem 2 builds directly on:
   `docs/superpowers/specs/2026-07-20-mal-client-design.md`
   and the plan (has a documented mid-implementation correction worth knowing about):
   `docs/superpowers/plans/2026-07-20-mal-client.md`
3. Use **superpowers:brainstorming** to design subsystem 2 (entity resolution) as its own
   spec before writing any code — it has real open design questions (see below), not just
   an implementation to transcribe.
4. Then **superpowers:writing-plans** → **superpowers:subagent-driven-development**
   (this is how subsystem 1 was built; the pattern worked well — task brief → implementer
   → task reviewer → next task → final whole-branch review → finishing-a-development-branch).

## Repo state (as of 2026-07-21)

- `main` (commit `41e192c`, pushed to `origin/main`) has: the full multi-source reading
  loop, on-device MangaDex-only recommendations, and now the read-only MAL client.
- No entity-resolution or "More Like This" code exists yet.
- `Secrets.xcconfig` (gitignored, at repo root) holds `MAL_CLIENT_ID` — already wired into
  the build; nothing to set up there.
- A throwaway `#if DEBUG` verification screen (`Views/MyAnimeListDebugView.swift`,
  reachable from Settings → "MyAnimeList Client" in debug builds) still exists. **Delete
  it once the real "More Like This" UI ships** — it was left in deliberately as a
  stepping stone, not a permanent feature.
- A throwaway live-network UI test (`Manga_ReaderUITests.testMyAnimeListDebugScreenLiveVerification`)
  also still exists. It's slow (~150s, widened timeouts to tolerate MAL's rate limiting)
  and was flagged by the final whole-branch review as **not fit for a permanent CI
  suite** — exclude it from any future CI test plan (e.g. `throw XCTSkip` unless an env
  flag is set) before this project has real CI, or delete it alongside the debug screen.

## What subsystem 2 (entity resolution) needs to solve

- **Input:** a `Manga` (has `sourceId`, source-native `id`, `title`) from any registered
  source (currently MangaDex, WeebCentral; nhentai exists on a private branch — see
  `nhentai-private-branch` memory, never merge it to `main`).
- **Output:** a MAL id for that manga, if one can be determined with reasonable
  confidence.
- **MangaDex is the easy case:** `/manga` payloads carry external-id links
  (`attributes.links.mal`, likely also `.al` for AniList, etc.) for most entries — check
  `Models/MangaDexAPI.swift`'s existing decode of `MangaAttributes`/`links` to see what's
  already captured vs. discarded. This may be close to free.
- **Scraped sources (WeebCentral, others) are the hard case:** no external MAL id
  available from the source itself. Options to weigh in the brainstorming session:
  title-based fuzzy matching via `MyAnimeListAPI.searchManga(title:)` (already built),
  confidence thresholds, caching resolved matches (where? a new store, or extend
  `LibraryStore`/a new `EntityResolutionStore`?), and what to do when no confident match
  exists (omit from "More Like This" entirely, rather than guess wrong).
- **This was flagged as the recommender roadmap's known weak point before any of this
  session's work started** — it's not a new risk, just now the actual next thing to
  solve rather than a deferred one.

## What subsystem 3 (UI + recsys extension) needs

- A "More Like This" tab/section on the manga detail page (`Views/MangaDetailView.swift`),
  driven by `MyAnimeListAPI.mangaDetail(id:).relatedManga` /`.recommendations`, each
  entry resolved back to whichever registered source(s) carry it via subsystem 2.
- Decide whether to fold this into the existing `RecommendationEngine`/`TasteProfile`
  machinery (currently MangaDex-only by design, since tag data quality is only trusted
  for MangaDex) or keep it as a separate, per-title, MAL-driven feature parallel to the
  on-device "For You" rail. This is a real design fork — bring it to the user as prose
  discussion rather than deciding unilaterally (see `works-discussion-at-forks` memory:
  this user prefers that at architecture-level forks).

## Gotcha worth knowing before you touch Info.plist / build settings again

`INFOPLIST_KEY_<Key>` (with `GENERATE_INFOPLIST_FILE = YES`) only synthesizes Xcode's own
fixed set of recognized Info.plist keys — it does **not** expose arbitrary custom keys.
Confirmed empirically while wiring `MAL_CLIENT_ID` in subsystem 1. If you need another
custom build-setting-to-Info.plist value later, use the pattern already in place: a small
partial `Info.plist` (see `Manga-Reader/Info.plist`, currently just the one
`MALClientID` key) + `INFOPLIST_FILE` pointing at it, kept alongside
`GENERATE_INFOPLIST_FILE = YES`. Don't reach for `INFOPLIST_KEY_*` for a custom key — it
silently no-ops.

## Testing convention (unchanged, still applies)

No tap tool in this environment, and no network-mocking harness for either `MangaDexAPI`
or `MyAnimeListAPI`. Established split: unit-test the pure/decoding logic (fixture JSON
→ DTOs), verify live network/UI behavior via a throwaway XCUITest method (assertions +
`XCTAttachment` screenshots, not manual tapping) — see `ui-verification-technique`
memory and how subsystem 1's Task 3 did it
(`Manga_ReaderUITests.testMyAnimeListDebugScreenLiveVerification`) for the concrete
recipe. Always `-destination 'platform=iOS Simulator,name=iPhone 17'
-parallel-testing-enabled NO` — no iPhone 16 simulator on this machine, and parallel
test clones are unwanted (see `no-parallel-test-clones` memory).
