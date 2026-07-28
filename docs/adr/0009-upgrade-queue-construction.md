# ADR-0009 — Building the upgrade queue: ordering source, drain mechanism, and merge semantics

- **Status:** Accepted (2026-07-26); **amended by ADR-0010 (2026-07-28)**
- **Amends:** ADR-0008 (its ordering decision — "untagged Works sort last"), ADR-0007 (its merge
  semantics — the surviving Work's snapshot)
- **Related:** ADR-0001 (Work vs Listing), ADR-0005 (manual link), ADR-0004 (fulfillment routing),
  ADR-0010 (drain loop and wiring)

## Context

ADR-0008 designed the upgrade queue's *policy* — what it resolves, in what order, what it
remembers, when it runs. It did not say what the queue is wired to, and four of its decisions turn
out to name values the code cannot currently supply or mechanisms it does not currently have.

**Facts verified live 2026-07-26 against the tree at `9208bba` (do not re-derive):**

- **There is no mint timestamp anywhere.** `Work` carries none (`Work.swift:112-134`),
  `LibraryItem` carries none (`LibraryStore.swift:12-22`), and `works` is a dictionary whose
  insertion order is not persisted (`WorkStore.swift:17`, `:360-367`). ADR-0008's "untagged Works
  sort last, **by mint recency**" is unimplementable as written.
- **`TasteProfile.build`'s inputs are assembled only by `RecommendationEngine`**
  (`RecommendationEngine.swift:128-144`), and `resolveSignals()` **mutates the store** — it mints
  and seeds from `legacyTagCache` (`:157-180`).
- **`WorkStore.merge` has no production caller.** Only tests reach it (`WorkStoreTests.swift:101`,
  `:112`, `:132`, `:339`, `:379`). The queue will be the first.
- **`WorkStore` publishes nothing.** Every field is `private var` and there are no `@Published`
  properties, so nothing can observe a mint or a staleness transition.
- **`MyAnimeListAPI` has no injection seam.** It is `static func` onto `URLSession.shared`
  (`MyAnimeListAPI.swift:111`, `:156`), and `MALEntityResolver` calls it directly (`:43`), so the
  resolver is untestable past its cache branch. `AniListAPI` took the opposite approach with an
  injectable `Transport` (`AniListAPI.swift:96-102`).
- **`searchManga` takes exactly one title** (`MyAnimeListAPI.swift:111`). A Work has a set.
- **`apply` resolves aliases before writing** (`WorkStore.swift:191`), so a snapshot applied to a
  Work id that was merged away lands on the survivor.

## Decisions

### The recommender pushes engagement weight to the queue; the queue never pulls

`RecommendationEngine.rebuild()` hands `profile.workWeights` to `queue.setPriority(_:)` on every
rail build. The queue stores the last map it was given and orders on it. It holds no reference to
history, library, or the taste store.

> **Amended by ADR-0010.** The direction stands; the *site* moves down one level, to
> `profileAndExclusions()` after its gate. That function is where the profile is actually built and
> it has two callers — the rail and the See-all grid — so pushing from it is one call site instead of
> two. The handoff is an injected closure defaulted to a no-op, not a queue reference, so no existing
> engine construction site or test changes.

Having the queue construct its own profile was rejected because `TasteProfile.build`'s inputs are
reachable only through the engine, and the assembly step mutates the Work store: `resolveSignals()`
mints and back-seeds provisional snapshots (`RecommendationEngine.swift:157-180`). A background
drain asking "what should I fetch next?" would mint as a side effect of the question. Injecting the
engine into the queue was rejected for the reason ADR-0008 already gives for the detail screen —
it inverts the dependency, with a different caller.

Extracting signal resolution into a type both could call is the cleaner end state and was rejected
only on timing: it moves the minting-and-migration path while that path is load-bearing for
existing users' first launch after slice 3, and it would ride along inside a new subsystem's PR.

**Accepted cost: the ordering is stale between rail builds, and absent on a cold start.**
`profileAndExclusions()` returns `nil` below the three-tagged-manga gate
(`RecommendationEngine.swift:141`), so `build` is never called and the queue is handed nothing —
on a first run, which is when the queue has the most to do. It then falls back to the unweighted
ordering below, which is a defined behaviour rather than an undefined one, but it is not a good
one.

### Ordering amendment: Works with **no reading history** sort last, not untagged Works

ADR-0008's tail conflates two populations. A Work that has been *read* but never had a detail page
opened carries no tags — yet it has reading history, and therefore a computable engagement weight.
A Work minted from a save or a *Not interested* has no history at all.

The first population is the highest-value set in the store: proven demand, contributing exactly
nothing to the profile. It is the case ADR-0001 exists to fix. So `TasteProfile.build` computes
`workWeights` for **every signal with entries**, tagged or not, and the residual tail — Works with
no history — orders by `WorkID`, arbitrary but stable.

Adding `mintedAt` to `Work` to implement ADR-0008 literally was rejected. It buys ordering for the
smaller and less valuable population, and it costs a `works.json` migration: `Work` uses
synthesized `Codable`, so a non-optional `Date` makes `loadIfNeeded`'s decode fail
(`WorkStore.swift:324-325`) and **silently drops every existing user's entire catalog**, since that
path is a `try?` with no error branch.

**Constraint this imposes:** `workWeights` and the `weighted` array must be accumulated
*separately*. `weighted` feeds `makeSeeds` (`TasteProfile.swift:112`), and seeds are MAL
recommendation input — letting untagged Works into it would silently change what the recommender
asks MyAnimeList for. `taggedMangaCount` likewise keeps incrementing only on tagged signals, so the
cold-start gate is untouched.

### The store exposes ids; the queue owns the predicate

`WorkStore` gains `allWorkIds() -> [WorkID]` and nothing else. Eligibility — snapshot staleness
*and* attempt memory — is computed entirely in the queue.

A purpose-built `upgradeCandidates()` accessor was rejected because the store can only ever apply
half the predicate: attempt memory lives in the queue's own file by ADR-0008's delete test, so the
queue must re-filter whatever the store returns. A half-predicate in the store drags queue policy
across the boundary and buys nothing.

This does not weaken ADR-0007's no-public-dictionary rule. That rule exists so every lookup follows
merge aliases; `work(_:)` already hands out complete `Work` values (`WorkStore.swift:59`), and
`allWorkIds()` returns keys of the live dictionary — losers are removed on merge (`:247`), so every
id it yields is already resolved. `MetadataSnapshot.isStale` is on the value type (`Work.swift:101`),
so the store never learns what an upgrade is.

**Accepted cost: a full scan per drain pass.** Main-actor, in-memory, a few hundred Works, against
a 2-second rate limiter. If the store outgrows that, the fix is an incremental dirty set inside the
store.

### The queue polls; there is no mint notification

One long-lived `Task`, started on `scenePhase == .active` and cancelled on `.background`, scanning
and draining, sleeping 60s when the scan comes back empty.

A signal-based design was rejected on where the signal would have to come from. `WorkStore`
publishes nothing, so the honest poke site is `mint` — which runs on **every page turn**
(`WorkStore.swift:97`). That means thousands of notifications per session so the queue can learn
something its next scan finds anyway. And the failure modes are asymmetric: a missed poke is a
permanently stuck queue, a missed scan self-heals in 60 seconds. Cancel-on-background also makes
every foregrounding start with a fresh scan for free.

The queue is serial by construction — one task, one loop, no `TaskGroup`. That is what "a single
serial queue owns the budget" means, and it reduces `AniListRateLimiter`'s slot reservation from
load-bearing to belt-and-braces.

It is an `ObservableObject` with **zero `@Published` properties**, the same shape `WorkStore` has
and for the same reason: it needs `@StateObject` ownership in the App struct, and nothing should
redraw when it works (ADR-0008's no-rebuild decision).

### Resolution searches once per known title, and matches once

For a Work with no external id: search MyAnimeList once per known title (capped at 3, display
title first), union the candidates by `malId`, and run **one** match over the merged pool.

This is not the shortcut ADR-0008 rejected. That was N *matches* → take the maximum, which
destroys the ambiguity guard because a maximum across independent ranked lists has no runner-up to
compare against. This is N *searches* → one pool → one match: the guard survives and is handed
*more* to compare, so two different titles pulling in two plausible candidates produces a
**rejection**, which is the correct precision-biased answer.

Single-search-on-display-title was rejected because cross-product *matching* cannot rescue a
candidate the *search* never retrieved, and a scraped source's spelling is exactly the case where
MAL's search may return nothing. The cost is near zero in the common case: an unresolved Work's
`knownTitles` is just its Listings' mint titles (`WorkStore.swift:127`, `:267`), usually one — so
this fans out only when a second source has contributed a different spelling, which is precisely
when it can help. ADR-0008's measurement (MAL absorbed ~4.3 req/s untroubled, queue runs at 0.5)
is what makes spending MAL requests to save AniList ones sound, and this is what it was for.

The Work-level entry point is a new method on `MALEntityResolver`, not a second copy of the
pipeline in the queue. It does **not** write `EntityResolutionStore` — ADR-0008 rejected that store
as the home of Work-level answers — but it does *read* it as a free fast path: a `.resolved(malId)`
recorded for any of the Work's Listings by a detail-page open is a valid answer for the Work and
costs no request. Rejecting it as a home is not rejecting it as a source.

`MALTitleMatcher` gains a `bestMatch(sourceTitles:candidates:)` overload with the existing singular
delegating to it. Every current matcher test stays untouched **on purpose** — that suite is the only
evidence the threshold ADR-0005 says never to loosen did not move.

`MALEntityResolver` takes an injected search closure defaulting to the real call, because
`MyAnimeListAPI` is static onto `URLSession.shared` and the resolver is otherwise untestable past
its cache branch. The seam goes at the resolver rather than in `MyAnimeListAPI` to keep the blast
radius inside the thing already being changed.

### A confident `malId` is written to the Work before the AniList fetch

Resolution calls `setExternalIds` the moment the matcher returns an id — not after the metadata
arrives.

ADR-0008 describes a Work that "stops being a resolution case and becomes a fetch case", but the
only code path that records an external id is `apply` (`WorkStore.swift:207`), which runs solely on
a *successful* fetch. So as specified, a transient AniList failure silently rewinds the Work to a
resolution case and re-searches MAL forever.

Deferring the write to preserve "uncorroborated matches don't reach the store" was rejected because
AniList corroborates nothing: `work(malId:)` is a bare lookup (`AniListAPI.swift:131`) and its
returned titles are never compared against ours. A wrong match writes the same wrong id either way;
deferring shrinks the window without changing the risk, and costs a redundant MAL search on every
transient failure permanently.

**This is also what makes the merge fix safe** — see below. Writing early puts any merge *before*
the fetch result exists, so there is no snapshot to lose.

> **Amended by ADR-0010.** This decision assumes the fetch either succeeds or throws. It can do
> neither: `apply` writes a snapshot only when the provider record has content
> (`WorkStore.swift:211-212`), so an AniList entry with no genres *and* no tags leaves a provisional
> snapshot in place — unconditionally stale (`Work.swift:104`) — while the external id written here
> short-circuits resolution. The Work is then re-fetched forever. ADR-0010 hoists `hasContent` onto
> `AniListWork` and records `.absentFromProvider(malId:)` when it is false.

### `reindexExternalIds` merges, and bails out of its own loop

Per ADR-0008 the incumbent index owner survives. The implementation detail that decision needs: on
collision, `merge(id, into: incumbent)` and **return immediately**.

`merge` already calls `reindexExternalIds(of: winnerId)` (`WorkStore.swift:251`). Without the
early return, the loop continues over the keys of a Work that was just set to `nil` (`:247`), and
the two functions mutually recurse. The merge's own reindex of the winner covers the remaining
keys, because the winner absorbed them (`:241`).

The queue then needs no special case for the collision: `setExternalIds` → merge → `apply(..., to:
originalId)`, and `apply`'s leading `resolve` (`:191`) follows the alias so the snapshot lands on
the survivor.

> **Amended by ADR-0010.** True for `apply`, false for everything else the queue does afterwards.
> The merge deletes and aliases the loser (`WorkStore.swift:269-270`), so an attempt-memory record
> or skip-set entry written against the original id is dead on arrival — `allWorkIds()` yields only
> live ids — leaving the survivor unsuppressed and re-picked immediately, forever. The queue must
> re-read `works.work(work.id)` after `setExternalIds` and target the survivor for every memory
> write, and re-check eligibility before spending the request.

### A merge keeps the better snapshot, not the winner's

**Amends ADR-0007.** `merge` copies titles, external ids, and listings (`WorkStore.swift:239-244`)
and drops the loser's `snapshot`. The surviving Work now takes the loser's snapshot when the
loser's outranks it, by the precedence rule already in the file: `nil` loses to anything,
`.mangadex` (provisional) loses to a provider (`:173`).

Leaving it alone — "one authority per Work, and a merge is a fine moment to pick one" — was
rejected because *which* one it picks is an accident, not an authority rule. The concrete case is
the one ADR-0008's own trace produces: Work B is the WeebCentral Work the user actually read,
carrying provisional tags; Work A is a MangaDex mint carrying nothing. Incumbent-survives hands the
store the empty one and discards the tags reading produced.

This is a live decision rather than a behaviour change, because `merge` has no production caller
today (verified above). Reusing `applyProvisionalSnapshot`'s existing floor rather than inventing a
comparator keeps one precedence order in the file.

## Hazards

- **The cold start has no ordering at all.** Below the three-tagged-manga gate the engine never
  builds a profile, so the queue's first and largest drain — the one on a fresh install — runs
  unweighted. Ordering arrives only after the rail first builds successfully.
- **A *Not interested* Work is still an upgrade candidate.** `markNotInterested` mints
  (`RecommendationEngine.swift:94`), and the queue has no view of `profileStore.notInterested` under
  the push design. It sorts into the no-history tail and is eventually fetched. Filtering it would
  mean handing the queue a second Listing-keyed set, reopening the dependency question.
- **A wrong match is effectively permanent.** Writing an uncorroborated `malId` can trigger a merge,
  and merge aliases are never pruned by design (`WorkStore.swift:25`). ADR-0005's manual link is the
  only recovery path, and it is not wired to undo a merge.
- **The fan-out cap of 3 is arbitrary.** It bounds a worst case that a heavily-merged Work could
  otherwise produce; nothing measured it.
- **`allWorkIds()` is a bulk accessor on a store that deliberately has none.** It is safe today
  because it returns only live ids, but it is the obvious thing a future caller reaches for when it
  wants to iterate Works, and it does not follow aliases on the caller's behalf.

## Revisit triggers

- If MyAnimeList ever returns a 429, the search fan-out is the first thing to shrink — before
  building a MAL limiter.
- If the no-history tail stops being small, its arbitrary `WorkID` ordering needs a real key, and
  that is when `mintedAt` earns its migration.
- If a second consumer needs engagement weight, the push stops being adequate and signal resolution
  should be extracted into a type both the engine and the queue call.
- If the unordered cold-start drain turns out to matter, the fix is a cheaper ordering source for
  the pre-gate case, not a queue that builds its own profile.
