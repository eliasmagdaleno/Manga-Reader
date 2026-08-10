# ADR-0018 — An authoritative external id is not a resolution question

- **Status:** Accepted (2026-08-10)
- **Related:** ADR-0007 (Work identity, and which file owns what), ADR-0008 (the matcher, the
  ambiguity guard, and `.unmatched` as a remembered answer), ADR-0009 (attempt memory and its
  reopen conditions), ADR-0015 (the notice a permanently-refused Work produces), ADR-0016
  (rejected — reaching MAL *through* MangaDex), ADR-0017 (why refusals happen at all)

## Context

MangaDex returns `links.mal` in the `/manga` response the app already fetches, for free, on a
request it already makes. `MangaAttributes.toManga` decodes it into `Manga.malId`
(`MangaDexAPI.swift:109`), `WorkStore.mint(from:)` absorbs it into `ExternalIDs`
(`WorkStore.swift:114`), and `MALEntityResolver.malId(for:)` short-circuits on it
(`MALEntityResolver.swift:59`). The chain is complete and has been all along.

Except across one boundary. `ReadingEntry` has no `malId` field, so the id is dropped at the point
it is persisted to history. `RecommendationEngine.resolveSignals()` then rebuilds a listing from
each entry with `malId: nil` (`RecommendationEngine.swift:325`), and the Work is minted with no
external id. The upgrade queue subsequently recovers that id by fuzzy-searching MyAnimeList by
title and running the result past a precision-biased matcher with an ambiguity guard — a guard
that, measured in the app under ADR-0017, refuses roughly one title in seven.

**We run a fuzzy match to recover an id the API handed us.**

The second half of the problem is what happens to a Work that was refused *before* it held an id.
`UpgradeAttemptMemory` records that refusal as `.unmatched(knownTitlesCount:)`, fingerprinted on
the title count so that a new synonym reopens it. `suppresses()` compares only that count. Learning
an authoritative `malId` adds no title, so the fingerprint does not move, and the Work stays
suppressed for the remaining fourteen-day TTL **while holding the correct answer**. That
suppression is also read as `tagBlocked` (`AppComposition.swift:114`), which drives ADR-0015's
"cannot be matched" notice and exclusion from the taste profile.

`UpgradeOutcome`'s own documentation already contains the rule this ADR needs, written about the
other case:

> Once a Work carries `mal:123` it has stopped being a resolution case, and a memory keyed on title
> count is about resolution.

`suppresses()` simply never applies it to `.unmatched`.

## Decisions

### 1. History carries the id its source published

`ReadingEntry` gains `var malId: Int? = nil`, populated at the single write site
(`HistoryStore.swift:145`) from the `Manga` it already receives. `resolveSignals()` passes it into
the listing it mints from.

A defaulted `var` on a `Codable` struct, matching how `sourceId` and `fraction` were added before
it: entries already on disk decode unchanged, and the default reads as "this entry predates the
field", which is true.

### 2. `links.mal` is authoritative, not a candidate

When the value is present it is used as the answer. The matcher is not consulted, the ambiguity
guard does not run, and no refusal is possible.

This is not new trust being extended — `WorkStore.mint` has always taken `listing.malId` on faith
as its free dedupe path, and `MALEntityResolver` has always returned `work.externalIds.mal`
unverified. Treating the same value from the same response as merely a *hint* once it passes
through history would make the history path less trusting than the minting path, for no reason.

The exposure, stated plainly: **MangaDex's links are community-edited.** A wrong `links.mal` yields
a confidently wrong `malId`, and therefore wrong tags, invisibly — the exact failure ADR-0016's
Decision 3 argued hardest against. We accept it, because the alternative is verifying a value we
already trust in two other places, and because a wrong link is a data bug at the source that a
title-similarity check would only sometimes catch.

### 3. An unmatched refusal does not survive an authoritative id

`suppresses()` returns, for the `.unmatched` case:

```swift
work.externalIds.mal == nil && work.knownTitles.count == count
```

A read-time guard, not a widened fingerprint. A stored `hasMalId` flag would record what was true
when the refusal happened; the question being asked is what is true *now*. It also needs no
migration of `upgrade-attempts.json`.

**This changes three behaviours, not one.** Beyond the queue reconsidering the Work, `tagBlocked`
stops firing for it — so ADR-0015's unmatchable notice disappears and the Work rejoins the taste
profile (`RecommendationEngine.swift:282`, `:306`), immediately, before any drain. That is the
point rather than a side effect: telling a reader we cannot identify a title whose MyAnimeList id
we are holding is the same false statement, made in a different place.

`.absentFromProvider` is untouched. It is *about* a Work that has an id, so the guard would negate
it entirely.

## Scope

**New reads only. No backfill.** Existing history keeps its `malId: nil` and continues through the
upgrade queue, which already resolves most of it. A backfill would mean re-fetching every historic
manga to read `links.mal` — a second resolution pipeline, with its own pacing and failure modes,
built to fix a problem the first one largely handles. The id arrives naturally as titles are read
again, and the queue's job shrinks over time.

**`LibraryItem` is unchanged.** The handoff that motivated this proposed putting `malId` there, but
`LibraryItem` never reaches `resolveSignals()` — saved-but-unread items are deliberately excluded
from the taste profile. Adding the field there would fix nothing measured.

## Hazards

1. **A wrong `links.mal` is now load-bearing** (Decision 2). Previously a bad link only affected
   detail-view minting; now it also seeds the taste profile.
2. **The notice and profile-exclusion branches have no automated coverage.** That was a deliberate
   decision recorded in `AppCompositionTests`' header, and Decision 3 changes behaviour inside it.
   Verified by unit tests on `suppresses()` itself, which is where the logic lives — but the wiring
   from there to the rendered notice remains untested, as before.
3. **Unmeasured in the app.** Accepted on a traced call chain and unit tests, not on a simulator
   run. Every link in the chain is existing, exercised code; the only new behaviour is one field
   surviving a round-trip. Stated so a later session does not mistake this for a measured claim —
   the recurring lesson of ADR-0015.

## Revisit triggers

- **A recommendation traced to a wrong `malId` that came from `links.mal`** → Decision 2 becomes a
  candidate-with-confirmation instead, and Hazard 1 has fired.
- **Historic history proves not to drain** — Works minted before this that the queue still refuses
  after their TTL → the backfill rejected under Scope is back on the table.
- **A second source starts publishing external ids** → Decision 1 generalises beyond `mal`, and
  `ExternalIDs` already has the shape for it.
