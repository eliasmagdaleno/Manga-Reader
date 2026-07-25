# ADR-0001 — A manga is a *Work*; a source's copy of it is a *Listing*

- **Status:** Accepted (2026-07-24)
- **Supersedes:** nothing
- **Related:** ADR-0002 (catalog authority), ADR-0003 (extension substrate),
  ADR-0004 (fulfillment routing), ADR-0007 (Work shape and lifecycle — resolves this ADR's
  open "move to the Work key *or carry a mapping*": the edges stay Listing-keyed)

## Context

Today the app has exactly one manga type: `Manga`, whose `id` is **source-scoped** and whose
`sourceId` names the source that produced it. Consequences already visible in the code:

- The same manga read on MangaDex and on WeebCentral are two unrelated objects. Nothing can
  dedupe them, so a title you finished on one source can be recommended to you from another.
- `RecommendationEngine` hardcodes `mangaDexSource`, and `MangaDetailView.swift:56` guards
  `manga.sourceId == "mangadex"` before recording tags. A manga read on WeebCentral therefore
  gets no tags → no engagement weight in `TasteProfile.build` (which skips untagged manga
  before computing weight) → it can neither contribute tag signal nor become a MAL seed.
  **Non-MangaDex reading is structurally invisible to the recommender.**
- `malId` is the only cross-source identity the app has, and scraped sources always leave it
  `nil`.

The product goal that forces the change: recommendations come from an external catalog
(MyAnimeList today), and the app must find *whichever installed source can serve that title*.
MangaDex alone has coverage gaps for mainstream licensed titles, which is the whole reason
more sources are wanted.

## Decision

Split identity from availability.

- A **Work** is the manga itself, independent of any source. It owns identity, external ids,
  and the metadata recommendations are ranked on.
- A **Listing** is one source's copy of a Work — a source id, that source's own manga id, its
  chapter availability, and its cover. `Manga` as it exists today *is* a Listing.
- **The recommender ranks Works, not Listings.** Taste profile, candidate pools, exclusion
  sets, and feedback (`Not interested` / `More like this`) all key on Work identity.
- Resolving Work → Listing is a separate concern with its own policy (ADR-0004) and its own
  cache.

## Consequences

- `Manga.id` stops being the recommender's key. `TasteProfile`, `CandidateProvider`,
  `ScoredManga`, `HistoryStore`, `LibraryStore`, and `TasteProfileStore` all currently key on
  it; each needs to move to the Work key or carry a mapping.
- `EntityResolutionStore` is currently keyed by `malId` in both directions. Under this ADR the
  Work key becomes the spine and `malId` becomes one external id among several — see ADR-0002,
  which is the reason not to make `malId` itself the Work key.
- The tag backfill and the `sourceId == "mangadex"` guard become a **metadata-provider**
  concern: a Work's tags come from whatever provider knows it, not from the source you happened
  to read it on.
- Every non-MangaDex Listing must be linked to its Work by fuzzy title match
  (`MALTitleMatcher`, precision-biased, `nil` on no-confident-match). Failures are **silent**:
  the Listing simply never appears. A manual link/override path is an open problem.
- Migration: existing `HistoryStore` and `LibraryStore` entries are Listing-keyed and must be
  back-resolved to Works, or the user's history is orphaned on first launch after the change.

## Alternatives rejected

- **`malId` as the Work key.** Cheapest, and the code half-does it already. Rejected because it
  caps the catalog at what MyAnimeList knows (weak for manhwa/manhua/webtoons) and makes adding
  a second metadata provider such as AniList a rewrite rather than an addition.
- **Keep source-primary, dedupe opportunistically at the UI layer.** Rejected: the invisibility
  bug above is in the profile-building layer, not the UI, so a UI-level dedupe cannot fix it.
