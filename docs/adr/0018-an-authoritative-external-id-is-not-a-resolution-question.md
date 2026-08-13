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
3. ~~**Unmeasured in the app.**~~ **Fully closed 2026-08-13.** Decision 1's leg is verified in
   `docs/superpowers/specs/2026-08-13-adr-0018-decision-1-verified.md`: a Berserk read reached
   through Search wrote `malId: 2` onto the new history entry, above the seeded pre-0018 entry for
   the same manga that still reads `malId: null`; resuming it from History prepended new entries
   still carrying the id, which is `ReadingEntry.asManga` — the line Amendment 1 fixed — holding on
   the resume route. A WeebCentral read wrote `malId: nil`, correctly: that source publishes no ids.
   **Decision 2 remains unverified and unverifiable this way** — a wrong `links.mal` is Hazard 1,
   accepted by name. Original note, for Decision 3, follows. **Closed 2026-08-11** for Decision 3 — see
   `docs/superpowers/specs/2026-08-11-adr-0018-in-app-verification.md`. On the seeded simulator a
   refused `Wind Breaker` Work acquired `mal: 133081` through an ordinary library add, and the next
   launch cleared its refusal and left it holding 28 AniList tags; the placeholder control was
   untouched. ~~**Decision 1's in-app leg is still unverified** — no refused Work on that simulator
   is re-readable — and remains unit-tested only.~~ **Superseded 2026-08-13**, and its reasoning was
   wrong in a way worth keeping: what the leg needed was not a re-readable *refused* Work but a
   re-readable Work whose *source publishes an id*. Berserk qualified the whole time.

## Revisit triggers

- **A recommendation traced to a wrong `malId` that came from `links.mal`** → Decision 2 becomes a
  candidate-with-confirmation instead, and Hazard 1 has fired.
- **Historic history proves not to drain** — Works minted before this that the queue still refuses
  after their TTL → the backfill rejected under Scope is back on the table.
- **A second source starts publishing external ids** → Decision 1 generalises beyond `mal`, and
  `ExternalIDs` already has the shape for it.

## Amendment 1 — what actually triggers Decision 3 (2026-08-11)

Decision 3 was accepted without naming the sequence that fires it. Asked directly — *how does a
refused Work ever acquire a `mal` id?* — the first answer traced looked like **none**, which would
have made the guard correct but dormant. That answer was wrong, and the real one matters enough to
record, because it also tells you the guard is common rather than exotic.

**The three writers of `externalIds` on an existing Work** are `WorkStore.mint(from:)` via
`absorb`, `WorkStore.setExternalIds` (the queue's success path), and `WorkStore.apply` (AniList).
The latter two only run on a Work that has *already* resolved, so neither can produce
"refused, then holding an id". That leaves `mint`.

`mint` looked like a dead end because a MangaDex Listing carries `links.mal` from the moment it is
created, so its Work should never be refused in the first place. **But the Works minted from
history do not come from the API response — they are rebuilt from `ReadingEntry` by
`resolveSignals()`, which is exactly the boundary this ADR was written about.** Every Work minted
that way before Decision 1 came out with `malId: nil`. They are refusable, and many were refused.

So the trigger is:

1. A pre-0018 history entry mints an id-less Work; the queue refuses it as `.unmatched`.
2. The user reads that title again. `HistoryStore` writes a *new* entry, now carrying `malId`.
3. `resolveSignals()` mints from it. Same `sourceId` + `mangaId` ⇒ same `ListingKey` ⇒
   `absorb` lands the id on the **existing, refused** Work.
4. `suppresses()` sees the id and releases it. Notice gone, Work back in the taste profile.

This is the *ordinary* case for any library read before 2026-08-10, not an edge case — which is a
point in Decision 3's favour that the original text did not make. It is also why Scope's "no
backfill" is cheaper than it sounds: a re-read backfills one Work for free.

**The prediction under test.** Recorded before the verification run, so the run can fail:

> On the seeded simulator (`iPhone 17`, `2A0D54DF-…`), the Work `Wind Breaker` holds
> `externalIds: {}` and one Listing, `mangadex / 9eb78304-0436-484d-9a79-a925b45e2731`, and is
> refused as `.unmatched(knownTitlesCount: 1)`. MangaDex publishes `links.mal = 133081` for that
> manga. Reading it in the app should write `malId: 133081` onto the new history entry, absorb it
> onto the existing Work, and release the refusal — while the three placeholder WeebCentral Works
> (`Qelparre Drift`, `Bramgot no Yeshu`, `Zurnak Vhelli`), for which no `mal` id exists anywhere,
> stay suppressed.

Wind Breaker is therefore the **positive** fixture, not — as the 2026-08-11 handoff had it — the
negative control. The handoff was reasoning from its 1.00/1.00 ambiguity tie, which is why it
refused; but the tie is irrelevant once an authoritative id arrives, and that is the whole content
of Decision 3. The negative control is a placeholder title instead.

Both fixtures expire when the refusals age out of the fourteen-day TTL, **on or about 2026-08-23**.

**Outcome: the prediction held.** The run reached the Work through `Add to Library` rather than a
read — MangaDex serves no chapters for this title — and the guard released it as predicted.
Written up in `docs/superpowers/specs/2026-08-11-adr-0018-in-app-verification.md`; Hazard 3 is
closed for Decision 3.

### A gap this amendment found: the resume path dropped the id

`ReadingEntry.asManga` (`HistoryView.swift:140`) hardcoded `malId: nil`. That is the `Manga` handed
to `ReaderView` and thence to `HistoryStore.record`, which reads `malId` off it — so on the route a
re-read actually takes, Scope's "the id arrives naturally as titles are read again" was false. The
same boundary loss this ADR was written to close, one layer further out. Now `malId: malId`, with
tests; `asManga` is internal rather than fileprivate so it can be tested.

`BookmarksView.asManga` keeps its `nil` and is correct: `LibraryItem` has no id to carry, per Scope.
