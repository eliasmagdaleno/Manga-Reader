# Handoff — "More Like This" (Cross-Source Recommendations, subsystem 3)

**Audience:** a fresh session continuing this initiative. Self-contained — you should not
need the prior chat.

## Where this sits

Three-subsystem effort to ship a Netflix-style **"More Like This"** rail on the manga
detail page, backed by MyAnimeList (MAL) as the cross-source identity/metadata backbone.

1. **Read-only MAL client — DONE**, merged to `main`.
2. **Cross-source entity resolution (`Manga → MAL id`) — DONE**, merged to `main` and pushed
   to origin (merge commit `8750630`). See `recommender-roadmap` memory + spec
   `docs/superpowers/specs/2026-07-21-cross-source-entity-resolution-design.md`.
3. **"More Like This" UI + reverse resolution — SPEC APPROVED, NOT YET PLANNED.** ← you are here.

## Immediate next step

The spec is written, self-reviewed, user-approved, and committed
(`docs/superpowers/specs/2026-07-21-more-like-this-design.md`, commit `c3b2338`). The user
approved it with "lock it in and write the spec," then asked for this handoff before the
plan.

**Resume by invoking `superpowers:writing-plans`** to turn that spec into an implementation
plan at `docs/superpowers/plans/2026-07-21-more-like-this.md`. Then execute with
`superpowers:subagent-driven-development` (the pattern used for subsystems 1 and 2 — it
worked well: haiku implementers transcribing complete plan code, sonnet task reviewers, one
opus whole-branch review at the end, all tests via iPhone 17 sim `-parallel-testing-enabled
NO`). Do the implementation on a feature branch off `main` (e.g. `feature/more-like-this`),
not on `main` directly, then finish via `superpowers:finishing-a-development-branch`.

## The design that was locked in (read the spec for full detail)

- **Separate feature**, NOT folded into the home `RecommendationEngine` (that one is
  personalized/tag-based/MangaDex-only/home-level; this is per-title/non-personalized/
  MAL-collaborative). They share only the reusable rail UI. `TasteProfile` untouched.
- **Recommendations-only for v1.** Use MAL `recommendations` (top ~8 by `numRecommendations`);
  `related_manga` deferred (same fetch, cheap to add later).
- **MangaDex-only reverse resolution.** MAL returns `(malId, title)`; each must become an
  openable MangaDex `Manga`. MangaDex search results carry `malId` (subsystem 2), so reverse
  resolution is **precise**: accept the search result whose `malId == target`; fuzzy title
  fallback via a generalized `MALTitleMatcher`; omit on no confident match (precision > recall).
- **New pieces:** `Services/MoreLikeThisProvider.swift` (`@MainActor`,
  `recommendations(for:limit:) async -> [Manga]`), a pure testable `MoreLikeThis.pickMatch(...)`,
  `Models/MoreLikeThisViewModel.swift`, and a bottom-of-page rail in `MangaDetailView` (reuses
  `MangaRail`, loads via `.task`, hidden when empty).
- **Reverse cache:** extend `EntityResolutionStore` with a `reverseCache` (MAL id → MangaDex
  manga id, `ReverseResolution` enum, same 14-day miss TTL) + a `static let shared` so the
  cache persists across detail-page opens. On cache hit, batch-render via
  `MangaDexAPI.fetchMangaByIdsWithCovers` (currently `private` — expose it).
- **Matcher refactor (DRY):** extract `MALTitleMatcher`'s scoring into a generic
  `bestMatch<ID>(sourceTitle:candidates:)`; existing `decide` delegates to it; its 7 tests
  are the refactor's safety net.

## Concrete implementation anchors (verified this session)

- `MangaDetailView.swift` body is `ScrollView > VStack(spacing: Gutter.section)` with
  `hero / actionRow / tags / description / chapters`. The new rail section goes **last**
  (after `chapters`). The view uses `@StateObject vm` (created in `init`) + `@EnvironmentObject`
  stores; add a `@StateObject moreLikeThis = MoreLikeThisViewModel()` and a `.task`.
- `MangaDexAPI.searchManga(title:)` already routes results through `toManga`, so each result
  carries `malId` — this is what makes precise reverse matching possible.
- `MangaDexAPI.fetchMangaByIdsWithCovers(ids:)` is at ~`MangaDexAPI.swift:527`, `private static`
  — make it `static` (internal).
- Bounded concurrency: reuse the sliding-window `TaskGroup` pattern from
  `LibraryStore.refresh` (cap 4).
- `EntityResolutionStore` (`Services/`) mirrors `TasteProfileStore`: `@MainActor
  ObservableObject`, UserDefaults+Codable, `init(defaults:)`. `missTTL` is already
  `nonisolated static let` (a Swift-6 fix from subsystem 2 — keep new `isFresh` helpers
  nonisolated too). `MALResolution` lives here and is the model for the new `ReverseResolution`.

## Testing convention (unchanged)

No network-mock harness for `MangaDexAPI`/`MyAnimeListAPI`. Split: unit-test the pure pieces
(`MoreLikeThis.pickMatch`, the generic `bestMatch`, reverse-cache round-trip/TTL, the
sort/take-top-N selection), live-verify the network orchestration via (a) a throwaway
`MyAnimeListDebugView` "More Like This" probe + live UI test, and (b) a live UI test on the
real detail-page rail (open a popular Home title → scroll to bottom → assert the "More Like
This" header + ≥1 card). Always iPhone 17 sim, `-parallel-testing-enabled NO` (no iPhone 16
sim on this machine; parallel test clones unwanted — see `no-parallel-test-clones` memory).
Expect SourceKit/LSP "Cannot find X in scope" / "No such module 'XCTest'" false alarms from
the standalone indexer — judge correctness by the `xcodebuild test` run.

## Cleanup owed (from subsystem 2, do at subsystem 3's finish)

The throwaway `MyAnimeListDebugView` + its live UI tests (`testMyAnimeListDebugScreenLiveVerification`,
`testMALEntityResolutionLiveVerification`) were left in deliberately as verification
stepping-stones. Retire the debug screen + those tests once the real "More Like This" rail
is proven in-app (the spec keeps a debug probe during subsystem 3, then it all goes). The
rail on the real detail page is the permanent feature.

## Gotchas worth keeping

- `EntityResolutionStore.missTTL` must stay `nonisolated static let` (referenced from
  nonisolated `isFresh`); a plain `static let` on the `@MainActor` class is a Swift-6 compile
  error. Any new freshness helper follows the same rule.
- `[Int: X]` JSON-encodes oddly in Swift — key the reverse cache by `String(malId)`, matching
  the forward map's string keying.
- `main` merged locally AND pushed to origin already for subsystem 2 — no outstanding push.
- Adding files to `Services/`/`Models/` is free (synchronized groups); **`Views/` is NOT
  synchronized** — but `MangaDetailView.swift`/`MyAnimeListDebugView.swift` already exist, so
  editing them needs no `project.pbxproj` change. Only a brand-new `Views/` file would.
