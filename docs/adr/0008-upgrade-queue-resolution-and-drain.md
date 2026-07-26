# ADR-0008 — The upgrade queue: resolution, ordering, and drain

- **Status:** Accepted (2026-07-26)
- **Amends:** ADR-0007 (its "Upgrade queue" decision — trigger and ordering, below)
- **Related:** ADR-0001 (Work vs Listing), ADR-0004 (fulfillment routing), ADR-0005 (manual link)

## Context

ADR-0007 pinned the Work's shape and named a single serial upgrade queue as the owner of the
AniList budget. It did not say how a Work reaches AniList in the first place, and the gap is
load-bearing:

- `mint` builds `ExternalIDs(mal: listing.malId, anilist: nil)` (`WorkStore.swift:100`), and only
  MangaDex publishes `attributes.links.mal`. **A Work minted from a scraped source has no external
  id.**
- `AniListAPI` exposes exactly one lookup, `work(malId: Int)` (`AniListAPI.swift:131`).
- `MetadataSnapshot.isStale` returns `true` unconditionally for provisional snapshots
  (`Work.swift:104`).

Chained: every WeebCentral Work is permanently stale, permanently eligible, and permanently
un-upgradable — the queue can dequeue it and then has nothing to send. That is the same futile-loop
shape ADR-0007 warns about for `scheduleBackfill`'s MangaDex-only filter, relocated into the
component meant to replace it. Since "make non-MangaDex reading count" is the stated purpose of this
whole line of work, the queue cannot ship without an answer.

ADR-0007 left the tension visible: it calls a WeebCentral Work's missing external id an "accepted
cost", then describes the invisibility being fixed "asynchronously… once the upgrade queue reaches
it and the title matches". Nothing owned the matching. This ADR assigns it.

**Fact verified live 2026-07-26 (do not re-derive): MyAnimeList publishes no rate-limit headers and
did not throttle 90 sequential `/v2/manga?q=` requests in 21s (~4.3 req/s), all 200.** AniList's
measured 30/min is **8.6× stricter**, so AniList is the binding constraint and MAL needs no limiter
of its own. This does not prove MAL has no limit — a daily cap or a longer window would not show up
in a 21s probe — only that it is not the constraint at the queue's pace of 0.5 req/s.

## Decisions

### Resolution reuses the MyAnimeList path; AniList is never asked to search

A Work with no external id is resolved by `MALEntityResolver` — title search against MyAnimeList,
decided by `MALTitleMatcher` — and the resulting `malId` is handed to `AniListAPI.work(malId:)`.
AniList is a **lookup-by-id** provider here and never a search provider.

Adding `Media(search:)` to the AniList client was rejected on two counts. It draws resolution and
metadata from the same 30/min budget, so an unresolvable Work spends the budget it can never
benefit from; and `MALTitleMatcher`'s threshold was tuned against MAL's search ranking, so pointing
it at AniList's would be an untested precision assumption on the one threshold ADR-0005 says never
to loosen.

Doing nothing — leaving scraped Works provisional until the user manually links them — was rejected
as a *default*, not as a fallback. It is still what happens when matching declines; the difference
is that ADR-0005's manual link stays a recovery path instead of becoming the only path.

**Accepted cost: two providers now sit between a Work and its metadata.** Measured (above), MAL is
not a second rate-limited resource in practice — it absorbed ~4.3 req/s untroubled, against a queue
that runs at 0.5. So `AniListRateLimiter` stays AniList's alone and **no MAL limiter is built**. What
the second provider does cost is a second failure mode, which the attempt memory below has to model.

### Resolution is Work-level, and `knownTitles` goes *into* the matcher

`MALEntityResolver.malId(for:)` matches on a single Listing title today
(`MALEntityResolver.swift:49`). ADR-0007 built `Work.knownTitles` explicitly as "a richer left-hand
side for `MALTitleMatcher`, raising recall without touching the precision threshold", and nothing
ever read it. The queue resolves per **Work**, and passes the whole `knownTitles` set to the matcher
as the source side.

The tempting shortcut — run the existing single-title matcher once per known title and take the best
result — was rejected because it **routes around the ambiguity guard**. That guard compares the
winner to the runner-up *within one ranked list* (`MALTitleMatcher.swift:95`); a maximum taken across
N independent passes has no runner-up to compare against, so it raises recall and the false-match
rate together. Precision-biased matching is not preserved by running a precision-biased matcher
repeatedly.

Instead each candidate scores as the maximum similarity over the **title cross-product**, producing
one ranked list and one ambiguity guard. This is symmetric with what `bestMatch` already does on the
candidate side (`MALTitleMatcher.swift:86-89`) — it maxes over each candidate's titles; now the
source side is a list too.

**Consequence:** recall improves monotonically as Listings link and providers contribute synonyms,
with no rate limit spent re-fetching titles — the payoff ADR-0007 claimed for `knownTitles` and
could not yet collect.

### Attempt memory lives in the queue's own state file, keyed by Work

The queue records `WorkID → (checkedAt, outcome)` in a file it owns, separate from `works.json`.
(The outcome's shape is the next decision.)

Not in `works.json`, by ADR-0007's own test: *can you delete this file and lose nothing but time?*
Attempt bookkeeping, yes — worst case is one redundant resolution pass. Work identity, no. Data with
different answers must not share a file.

Not in `EntityResolutionStore` either, despite it already having a miss TTL for exactly this shape
(`EntityResolutionStore.swift:61`). Its cache is keyed `sourceId:mangaId`, and a Work-level answer
has no single Listing to key on. Writing the same result back to every Listing key was considered
and rejected: it cannot see the Work-level input change the next decision depends on.

### Attempt memory records an outcome, because the two stages fail differently

Two providers now sit between a Work and its metadata, and a timestamp alone cannot tell them apart.
The memory stores one of:

- **`.unmatched(knownTitlesCount)`** — MAL returned candidates, none cleared the threshold.
  Reopened by the title count, with the TTL as backstop.
- **`.absentFromProvider(malId)`** — resolution succeeded, AniList has no entry for that id.
  Reopened by the TTL only.
- **transient** — recorded as nothing at all.

**`knownTitlesCount` invalidates an `.unmatched`, and the TTL is the backstop.** A miss means "no
confident match *given these titles*" — so when a Listing links or a provider adds synonyms, the miss
is stale immediately rather than after 14 days. The count is a sound fingerprint because
`knownTitles` is **monotonic**: `Work.noteTitle` only appends (`Work.swift:129-133`) and `merge` only
unions (`WorkStore.swift:239-241`), so a changed count always means the set grew.

**`.absentFromProvider` exists because the fetch stage would otherwise have no memory whatsoever.**
Once resolution records `mal:123` on a Work, that Work stops being a resolution case and becomes a
fetch case — and a memory keyed only on title count is about resolution. Without this outcome, a Work
whose `malId` AniList 404s is re-requested on **every drain, forever**: exactly the futile loop
ADR-0007 warns about, rebuilt one stage later. More titles cannot help it, because re-matching
produces the same id every time.

**It gets a long TTL (14 days) rather than being terminal.** AniList adds entries over time, and the
costs are asymmetric: a TTL spends one request per Work per interval, while terminal strands a Work
that gets catalogued next month as provisional until the user manually links something that is not
actually broken. The argument for terminal is real — `.absentFromProvider` is a fact about the
catalog rather than about our matching, and ADR-0007 treats catalog facts like `FINISHED` as
never-expiring — but it loses on that asymmetry.

Transient failures are recorded as nothing, mirroring the discipline `MALEntityResolver` already
documents: an outage must not poison the memory for the TTL.

### Ordering: one definition of engagement weight, exposed

`TasteProfile.build` returns `workWeights: [WorkID: Double]` alongside what it already returns, and
the queue orders on that, descending.

ADR-0007 specified this ordering without noticing it was unimplementable: the weight is computed
inside `build`, the `weighted` array is private, and `guard !signal.tags.isEmpty`
(`TasteProfile.swift:82`) means it is never computed at all for an untagged Work. Letting the queue
compute its own recency×chapters score was rejected — two formulas for "engagement" will silently
diverge the first time either is tuned, and this one is already load-bearing for seeds.

**Untagged Works sort after every weighted Work, by mint recency.** These are Works minted from a
save where no detail page was ever opened, so they carry no tags and no weight by construction. The
opposing argument is real — an untagged Work contributes literally nothing, so upgrading it has the
highest marginal value — but it loses on evidence: a heavily-read Work is *proven* demand, an
untagged save is a guess at it. Provisional tags already cover everything actually read, so this set
is small.

### The queue is its own service, and it drains continuously while foregrounded

`Services/MetadataUpgradeQueue.swift` owns `AniListAPI`, `AniListRateLimiter`, `MALEntityResolver`,
`WorkStore`, and the attempt-memory file.

Not on `RecommendationEngine`, where `scheduleBackfill` lives today. ADR-0007 already anticipates
"a user-initiated detail-page fetch to jump the queue", and a detail screen reaching through the
recommender to get metadata inverts the dependency — the recommender is one consumer of Work
metadata, not its owner. ADR-0004's fulfillment routing will be another.

**Trigger: drain while the app is foregrounded, paced by the limiter, idle when nothing is stale.**
This amends ADR-0007's "batch of 5 on rail build", which does not work: `load()` is
`guard !loadedOnce` (`RecommendationEngine.swift:74`), so the rail builds once per session and a
long reading session triggers the queue zero times.

Continuous drain is cheaper than it sounds, because the queue is nearly always empty. Works are
bounded by what the user reads and saves; `FINISHED` snapshots never expire and `RELEASING` re-checks
on 14 days (`Work.swift:101-108`). So it is one drain of a few hundred items followed by near
permanent idle. Batching existed to bound a cost the rate limiter already bounds.

### A completed drain does not rebuild the rail

The queue's output is invisible until the next rail build — pull-to-refresh, or the next launch.
`WorkStore` is an `ObservableObject` with **no `@Published` properties at all** (every field is
`private var`, which follows from ADR-0007's no-public-dictionary rule), so `objectWillChange` never
fires; and `load()` is `guard !loadedOnce`. A user can therefore read for an hour, have hundreds of
Works upgraded from provisional to AniList, and see the same rail throughout.

That is accepted rather than worked around. **A rail that rearranges itself while being looked at is
worse than a rail that is one session stale**, and the recommender already accepts session-staleness
by design. The cost is bounded because provisional tags cover everything the user has actually read
(ADR-0007's provisional tier), so the cold-start gate never depends on the queue — only tag
*quality* improves when it runs.

**Accepted cost:** a new user who reads five titles on a scraped source sees the queue resolve them
all and the rail not move until relaunch.

### Learning an external id can merge, so the index must never silently overwrite

`reindexExternalIds` checks whether an index key already points at a different live Work and calls
`merge` rather than reassigning. **The incumbent index owner survives; the newly-resolved Work is
the loser.**

Today it assigns unconditionally (`WorkStore.swift:289-294`), reached from both `apply` and
`setExternalIds`. The reachable trace:

1. Solo Leveling read on WeebCentral → Work B minted, no external id.
2. Read on MangaDex → a different Listing key, and B has no id to match on, so **Work A** is minted
   with `mal:123`. Two Works for one manga — expected; this is what merge exists for.
3. The queue resolves B by title, gets `malId 123`, fetches AniList, calls `apply(to: B)`.
4. B absorbs `mal:123` and `externalIdIndex["mal:123"]` flips from A to B — **no merge, no alias.**

A survives with its own Listings and history, unreachable by external id, and the profile counts two
Works where there is one manga. Engagement splits across both, which is the exact failure Work
identity exists to prevent.

**This bug is created by the decisions above.** Before Work-level resolution, nothing ever learned an
external id after mint, so the collision was unreachable — which is why slice 2 shipped without it.

Incumbent-survives was chosen for stability rather than correctness: aliasing keeps the loser
resolvable either way (ADR-0007), so the only user-visible consequence is which `displayTitle`
persists, and the id that arrived first is the one already on screen.

## Hazards

- **Both failure outcomes still read as "still provisional" in the UI.** The attempt memory now
  distinguishes them, so ADR-0005's manual-link screen has something specific to say — but nothing
  surfaces it yet, and "why isn't this in For You" stays unanswerable to the user until it does.
- **MAL's limit was probed over 21 seconds.** A daily cap or a longer window would not have shown up.
  If 429s ever appear from MAL, the fix is a limiter, not a retry.
- **The priority lane ADR-0007 mentions ("a user-initiated detail-page fetch to jump the queue") is
  not designed here.** Nothing in the UI needs AniList data synchronously today — the detail screen
  renders the Listing's own tags — so it is deferred rather than decided.

## Revisit triggers

- If the untagged tail grows large enough to matter, revisit its ordering — the argument for sorting
  it last rests on the set being small.
- If a third rate-limited provider appears, the per-provider limiter pattern should become one
  shared budget abstraction rather than a third copy.
- If the first-run "rail doesn't move" gap turns out to matter more than rearrangement does, the
  no-rebuild decision is the one to reopen.
