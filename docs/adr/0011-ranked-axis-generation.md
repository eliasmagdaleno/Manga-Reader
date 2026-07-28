# ADR-0011 — Spending the ranked axis: AniList as a candidate generator

- **Status:** Accepted (2026-07-28)
- **Amends:** ADR-0007 — its "the AniList client must not be callable from view models" rule, and
  its claim that the ranked axis can never be a search key
- **Related:** ADR-0008 (queue policy), ADR-0010 (drain loop and wiring), ADR-0001 (Work vs
  Listing), ADR-0005 (manual link, matcher precision)

## Context

ADR-0007 through ADR-0010 built a subsystem whose entire purpose is to put AniList's ranked tag
axis — 425 tags with 0–100 per-title relevance — into the Work store. It is there.
`MetadataSnapshot.tags` is declared (`Work.swift:90`) and written (`WorkStore.swift:216`), and
**nothing reads it**: grepping `RankedTag` across `Manga-Reader/` returns only that declaration and
`AniListAPI.swift`. The taste profile still builds from the searchable axis alone
(`RecommendationEngine.swift:193`). The app spends a rate-limited budget fetching a 425-tag
vocabulary and then scores recommendations on the 19 genres MangaDex gives away.

This ADR decides what the axis is *for*. It is not a coding task: ADR-0007 defines the two axes as
different kinds of thing, and "fold rank into signal strength" has no obvious meaning until you say
which side of the scoring equation rank lands on.

**Facts verified live 2026-07-28 (do not re-derive):**

- **Candidates carry no tags at all.** `Manga` is `(id, sourceId, title, description, status, year,
  coverURL, malId)` (`MangaDexAPI.swift:13-22`). Both existing providers therefore score by
  *provenance* — `weight × 1/(1 + position)` (`CandidateProvider.swift:66`, `:129`) — because
  position is the only candidate-side datum they have.
- **MangaDex's `/manga` **list** endpoint returns full grouped tags at no extra request cost.**
  `GET /manga?limit=1` yields `attributes.tags` = `[{name:{en:"Romance"}, group:"genre"}, …]`, six
  on the first title, groups `genre` / `theme` / `format`. The app discards them at the decoder:
  `MangaAttributes` declares `title, description, status, year, links` and no `tags`
  (`MangaDexAPI.swift:71-76`).
- **AniList `tag_in` is a conjunction, not a disjunction.** `tag_in:["Dungeon","Iyashikei"]` with
  `minimumTagRank:80` returns **zero** media; at `minimumTagRank:0` it returns Frieren, Delicious in
  Dungeon, Campfire Cooking in Another World — titles carrying *both*. Every result of
  `tag_in:["Dungeon","Male Protagonist"]` carried both tags.
- **`minimumTagRank` applies per tag across the whole conjunction.** `tag_in:["Dungeon"]` at 80
  excludes Berserk (Dungeon 57), Black Clover (30), Tower of God (50). `Delicious in Dungeon`
  (Dungeon 98, Male Protagonist 70) survives the pair at 60 and dies at 80.
- **`pageInfo.total` is junk** — a flat `5000` on every query regardless of filters.
- **One `Page` query returns everything needed to both generate and score.** Each `media` carries
  `id`, `idMal`, `genres`, `tags { name rank category isMediaSpoiler }`, `status`, `chapters`.
  `isAdult:false` is a working media-level filter.
- **`MediaTagCollection` returns the whole vocabulary in one 27 KB request** — 425 tags with
  `name`, `category`, `isGeneralSpoiler`, `isAdult`. Category counts match ADR-0007's 2026-07-25
  table exactly (Cast-Traits 73, Sexual Content 65, Theme-Other 59), so the vocabulary has not moved
  in three days. `Technical` 21, `Cast-Main Cast` 12, `Demographic` 5. **66** tags are `isAdult`;
  **8** are `isGeneralSpoiler` — Afterlife, Age Gap, Alternate Universe, Body Swapping,
  Reincarnation, Time Manipulation, Time Skip, Tragedy.
- **Per-title spoiler flags are per-media, not global.** `War` on Solo Leveling is
  `isMediaSpoiler: true` while unflagged in `MediaTagCollection`.
- **`x-ratelimit-limit: 30` still holds**, unchanged from ADR-0007's measurement.
- **A provisional snapshot leaves the ranked axis empty.** `applyProvisionalSnapshot` writes
  `tags: []` (`WorkStore.swift:193`) — the ranked axis exists only for Works a provider fetch has
  reached.
- **`MetadataSnapshot.isStale` returns `false` forever for `.finished`** (`Work.swift:106`), so an
  already-upgraded finished Work is never re-fetched by the queue.
- **`CompositeCandidateProvider` already degrades per pool** — `async let`, then
  `(try? await pool) ?? []` (`CandidateProvider.swift:193-197`) — and its weights are non-private and
  injectable (`:182-188`). Its reason assignment lets MAL overwrite the tag reason (`:208`, `:213`).
- **`AniListRateLimiter` is an actor built for concurrent callers**, using slot *reservation* rather
  than "wait since the last one finished" (`AniListRateLimiter.swift:20-25`, `:45-57`).
- **`RecommendationEngine` gates the rail at `minTaggedManga = 3`** (`:52`, `:151`), and pushes
  weights out through a one-way closure so it cannot start, stop, or inspect the queue (`:34-36`).

## Decisions

### The ranked axis pays off as *generation on AniList*, not as scoring on MangaDex candidates

**Amends ADR-0007**, which states the ranked axis is "used for scoring and re-ranking candidates
already retrieved" and "never a search key."

That sentence is true of `MangaSource.mangaByTag`, which takes a MangaDex display name
(`MangaSource.swift:33-35`) against a 77-tag vocabulary sharing only 32 names with AniList's 425.
It is **not** true of AniList itself, which searches its own ranked vocabulary natively and filters
on rank while doing it. The rule was about one API's capability and got written down as a property
of the data.

Scoring-only was rejected on arithmetic. To score candidates on the ranked axis you need the
*candidates'* ranked tags. They have none, and getting them from AniList costs one paced request per
candidate against a 40-title pool. The affordable substitute — decoding MangaDex's list-endpoint
tags, which are free — gives you 77 unranked names, whose intersection with the user's ranked axis
is at most 32 names, and those 32 exclude every load-bearing genre (`Action`, `Romance`, `Fantasy`),
because AniList models those as `genres` and they already live on the searchable axis. The best
available scoring-only design therefore spends the ranked axis on its least informative sliver.

Generation inverts the economics: the user's ranked tags are the *query*, so the 425-tag vocabulary
is used at full resolution, and each result arrives carrying its own ranked tags in the same
response — the only place in this system where both sides of a comparison have real per-title
relevance data.

**Accepted cost: decoding MangaDex's free candidate tags is now unclaimed work.** It is a genuine
improvement to the existing tag pool (real overlap instead of pure provenance) and it is *not* part
of this decision. Doing both at once would make the golden diff unattributable.

### The generator lives beside the queue, sharing the limiter — not inside it

**Amends ADR-0007's** "the AniList client must not be callable from view models — only through the
queue," which is restated as: **one owner of the rate *limiter*.**

`AniListTagCandidateProvider` is a third `CandidateProvider` inside `CompositeCandidateProvider`,
calling `AniListAPI` through the shared `AniListRateLimiter`.

The original rule was written when every AniList call was per-Work, so an unbounded caller could
starve the queue. Generation is O(pairs) per *cache miss*, not per Work. What the rule protected —
the global 30/min budget — is protected by the limiter, and the limiter was built for exactly this:
slot reservation exists so N concurrent callers stagger deterministically
(`AniListRateLimiter.swift:20-25`).

Putting generation inside the queue was rejected on dependency direction. The seed pairs derive from
the taste profile, and only `RecommendationEngine` builds one — so the queue would have to take a
dependency on `TasteProfile`, which is precisely the direction ADR-0010 refused when it chose a
one-way `PriorityPush` closure so the recommender "must not be able to start, stop, or inspect the
queue" (`RecommendationEngine.swift:34-36`). Inverting a deliberate architectural decision to solve
a latency problem that has a cheaper answer (below) is a bad trade. It would also make the queue
emit two unrelated output types, and make the rail read a cache filled on a background loop's
schedule.

The composite is the right seam because failure handling is already there: a third `async let` pool
costs no wall-clock beyond its own latency, and "AniList is down" degrades to today's exact rail
through an existing code path (`CandidateProvider.swift:193-197`).

**Accepted cost: a rail build can now wait one limiter slot (~2s) behind the drain.** The drain is
serial, so the wait is bounded at one slot, and the next decision removes it from the common case.

### The query unit is a **pair** of tags at `minimumTagRank: 60`

One query per pair, `sort: POPULARITY_DESC`, `isAdult: false`.

Single-tag queries were rejected as a popularity list wearing a tag's name. "Dungeon ≥ 60, most
popular" returns approximately the same eight titles for every user who has read one dungeon manga,
and it is the same *shape* of query the tag pool already issues against MangaDex — AniList budget
spent to duplicate an existing rail, with rank contributing only a floor.

The conjunction is the thing no other part of the system can express. `Dungeon ∧ Time Manipulation,
both ≥ 60` is a statement about one reader, and it is the two-axis model working as designed:
the searchable axis generates broad, the ranked axis generates narrow.

Triples were rejected on measured thinning: `Dungeon ∧ Iyashikei` is already empty at
`minimumTagRank: 80`. A three-way conjunction at any useful floor returns nothing most of the time,
and an empty pool is indistinguishable from a broken one.

60 rather than 80 because 80 collapses the pool — `Delicious in Dungeon` is exactly the title you
want and it does not clear 80 on both legs. The floor's job is to exclude noise, not to rank;
ranking happens downstream with each candidate's actual rank values in hand.

### Seeds are the top 5 **co-occurring** pairs, excluding `Technical` and `Cast-Main Cast`

```
pairWeight(a,b) = Σ over Works w carrying both a and b at rank ≥ 60:
                     engagement(w) × min(rank_a, rank_b) / 100
```

Pairs must co-occur *within a single Work*, because rank is a per-Work number and a conjunction
assembled across Works is a claim nobody made. `Dungeon` from Solo Leveling ∧ `Cosmic Horror` from
Berserk is a query with no evidence behind it, and under AND semantics it frequently returns
nothing. Co-occurrence also guarantees a satisfiable query — the seed Work itself matches, which is
both the proof the pool is non-empty and the reminder that the exclusion set must catch it.

Anchoring every pair on the single top tag (`(t1,t2), (t1,t3), …`) was rejected because five
requests then buy one tag's worth of diversity. Ranking pairs by the product of global tag weights
was rejected for the same reason adjacency was: it manufactures conjunctions nobody read.

Summing across Works prefers pairs that **recur** — a pair in four Works is taste, a pair in one is
an accident — and degrades gracefully to single-Work pairs when history is thin. `min(rank_a,
rank_b)` rather than product or mean because it mirrors `minimumTagRank`: a conjunction is only as
strong as its weaker leg.

Two categories are excluded from **seeding only**, and remain available for scoring:

- **`Technical`** (Full Color, Long Strip) is a rendering fact. Seeding on it means "recommend me
  webtoons," and it will dominate — nearly every Korean title scores it 85+.
- **`Cast-Main Cast`** (Male Protagonist, Primarily Adult Cast) is near-universal; it appeared on
  every result of every verification query above.

The 66 `isAdult` tags are excluded from seeding on `main`. `isAdult:false` filters the *results*, but
a seed drawn from `Sexual Content` still shapes the pool and reads badly in a reason string.

### `category` lives in a cached tag vocabulary, never on the Work

`RankedTag` stays `(name, rank)`. Categories are looked up at read time from a `MediaTagCollection`
snapshot cached in `Caches/`, 30-day TTL.

Widening `RankedTag` was rejected because category is a property of a *tag name*, globally — not a
fact about any Work — so persisting it inside every `MetadataSnapshot` duplicates 425 strings across
the store *and* creates a migration trap with no exit: old snapshots would carry `nil`, and
`isStale` returns `false` forever for `.finished` Works (`Work.swift:106`), so every already-upgraded
finished Work would silently drop out of pair seeding permanently. A schema-version stamp forcing a
re-fetch would work and costs the whole store's worth of budget to fix a problem that does not need
to exist.

`Caches/` follows ADR-0007's own placement test — *can you delete this file and lose nothing but
time?* One 27 KB request rebuilds it.

**When the vocabulary is unavailable, AniList generation is skipped entirely** rather than run with
categories unknown. Unfiltered seeding is specifically the "recommend me webtoons and Male
Protagonist" failure; an empty pool degrades to today's rail. A missing filter should cost the
feature, not corrupt it.

### The pool is read-through and never blocks

The provider returns whatever the cache holds — empty on a cold miss — and kicks a background
refresh. The AniList pool appears on the *next* rail build.

Fetching inline was rejected on where the stall lands: five pairs × 2s spacing is ~10s, and the
composite awaits all pools together, so every cold build would stall Home behind a rail that
otherwise returns in one or two seconds — including on pull-to-refresh, where the user is watching.

The delay is invisible because the rail is *already* non-deterministic between builds by design:
`compose` reshuffles with a per-session seed (`RecommendationEngine.swift:199-209`). A pool arriving
one build later is indistinguishable from exploration. `load()` fires on every Home appearance, so
"next build" is seconds away.

- **Cache the reverse-resolved pool** (MangaDex `Manga` values), not raw `AniListWork`s. The query is
  5 requests; resolving AniList ids to openable listings is the larger fan-out, and caching only the
  cheap half would be pointless. Resolution reuses the existing path — every result carries `idMal`,
  so `EntityResolutionStore.reverseResolution(malId:)` serves hits and MangaDex title search covers
  misses, exactly as `MoreLikeThisProvider.swift:49-57` already does.
- **Key on the seed-pair set**, so a taste shift invalidates the entry for free.
- **14-day TTL**, matching `MetadataSnapshot.releasingTTL` and `EntityResolutionStore.missTTL` —
  one number in this codebase for "a stale answer is worth re-asking eventually," not a third.
- **Persist in `Caches/`.** In-memory means no AniList pool on the first Home appearance of every
  cold launch, which is the most common Home appearance there is.
- **Apply exclusions at scoring time, not cache time.** `read ∪ saved ∪ notInterested` changes every
  time a chapter is opened; the pool changes every two weeks. Baking exclusions in would resurrect
  titles the user just read.

### Candidates are scored on their own rank; agreement generalizes to a geometric mean over n pools

```
withinPool(c) = Σ over pairs p=(a,b) that surfaced c:
                   pairWeight(p) × min(rank_a(c), rank_b(c)) / 100
composite     = wTag·tag + wMal·mal + wAniList·ani
                + agreementBonus · (∏ contributing normalized scores)^(1/n)
wAniList = 0.6
```

This is the first candidate-side scoring in the system that uses the candidate's own metadata rather
than its position in a list. The rank values arrive in the same response that generated the
candidate, at no additional cost, so a title that is Dungeon 98 ∧ Necromancy 87 outranks one that
scraped in at 61/60. Summing across pairs preserves the multi-signal-overlap property both existing
pools have.

`wAniList = 0.6`, below `wMal`'s 0.85 — not because the signal is weaker in principle (it is the
best-evidenced of the three) but because it is the only one that has never faced a real device. The
golden file is the instrument for raising it, and the composite's constants are already injectable
for exactly this (`CandidateProvider.swift:182-188`).

**Three pairwise agreement terms were rejected.** `√(tag·mal) + √(tag·ani) + √(mal·ani)` lets a
title in all three collect up to `3 × agreementBonus` — reintroducing precisely the failure the
geometric mean was adopted to fix, where agreement outranks strength. Holding the current balance
would mean cutting `agreementBonus` to ~0.08, quietly weakening two-pool agreement as a side effect
of adding a third pool.

The generalized geometric mean stays bounded by the **weakest** contributing signal, which is the
property the current formula was chosen for, and reduces to today's exact behaviour when only two
pools contribute — so the change is one the golden file can adjudicate as a diff. `agreementBonus`
stays at 0.25 until it does.

Leaving agreement at two pools was rejected because tag-space and collaborative filtering
independently converging on a title is the strongest evidence this system can produce, and that is
exactly the case a two-pool term cannot see.

### Pool metadata is discarded; nothing is minted

Each pool result is a complete `AniListWork` — the exact payload `WorkStore.apply` consumes. It is
thrown away.

**Minting Works for candidates is refused outright.** ADR-0007 struck "or recommended" from ADR-0002
because `poolLimit = 40` per refresh means minting per candidate grows the store with *browsing*
rather than usage — the "tens of thousands" case the JSON-file decision was sized against. A third
provider producing another pool per refresh makes that worse, and re-litigating it on convenience
grounds is exactly what that decision anticipated.

**Side-caching the `AniListWork` by `malId`**, so a later mint finds its metadata free, was rejected
as premature. It introduces a second path into `MetadataSnapshot` with its own staleness question —
`fetchedAt` would be the pool's fetch time, up to 14 days stale — to optimize a resource that is not
scarce.

**Accepted cost:** a title discovered through this rail and then read costs one redundant AniList
fetch when the queue reaches it. Against 30/min and a handful of new reads a week, that is a
rounding error.

### The pool runs only above 3 AniList-resolved Works

The ranked axis exists only for Works a provider fetch has reached (`WorkStore.swift:193`), so
`taggedMangaCount` — which counts Works with *searchable* tags — cannot gate this. The AniList
provider needs its own threshold and reuses the same number, 3, rather than introducing a second
one.

One upgraded Work was rejected: every pair would come from that single book, the co-occurrence sum
would have nothing to sum over, and "recurring pair = taste, one-off = accident" — the property the
seeding rule rests on — becomes unmeasurable. The rail would be "more like this one title" presented
as taste modeling.

A higher bar was rejected on asymmetry: the pool is additive and degrades to nothing, so being too
permissive costs a mediocre third pool for a few titles, while being too strict leaves a shipped
feature dark for weeks.

### Reason strings name the pair; MAL still wins

`"More Dungeon + Necromancy"`, in the existing `"More \(name)"` idiom (`CandidateProvider.swift:87`).

Precedence is **tag < AniList < MAL**. MAL keeps winning where it contributes — `"Because you read
Solo Leveling"` names a book the user chose, which beats any tag phrasing — but a two-tag
conjunction is strictly more informative than the single broad tag that surfaced the same title, so
it overrides `"More Action"`.

The **8 `isGeneralSpoiler` tags are suppressed from reason strings only, never from seeding.**
Excluding `Reincarnation` and `Time Manipulation` from seeding would remove two of the strongest
signals in the isekai/regression cluster, which is a large share of what this rail is for. Printing
`"More Time Skip"`, on the other hand, tells a reader something the book was withholding. When one
leg of a pair is flagged, name the other; when both are, fall back to `"Recommended"`, which the
composite already handles.

**Accepted cost: per-title spoilers are out of reach.** `War` on Solo Leveling is
`isMediaSpoiler: true` but unflagged globally, and catching that would require persisting per-media
tag flags — which the vocabulary-cache decision above deliberately avoids. Eight global flags cover
the structural cases; the residual is a tag that is accurate, on-topic, and mildly revealing.

## Hazards

- **A WeebCentral-only reader may never clear the gate, silently.** Those Works have no `malId`,
  resolution depends on `MALTitleMatcher` clearing a threshold ADR-0005 says never to loosen, and a
  decline means the Work never gains a ranked axis. The rail is then permanently absent with no
  error and nothing in the UI to explain it — ADR-0007's accepted "why isn't this in For You yet"
  timing cost, except here the answer can be *never* rather than *later*.
- **Seeding is a feedback loop.** Pairs come from Works the user read; titles read from this rail
  feed back into the pairs. Without the exploration reshuffle already in `compose`, the rail would
  narrow on itself. Nothing measures how fast.
- **`minimumTagRank: 60` and `wAniList = 0.6` are unmeasured constants**, like every constant in
  this subsystem. The golden file makes them reviewable but cannot say they are right — there is
  still no labeled relevance data.
- **AND semantics make an empty pool a normal outcome, not an error.** A user whose top pair is
  genuinely rare gets nothing back and no signal distinguishes that from a broken query — the same
  shape as ADR-0010's `.graphQL` hazard, in a subsystem that also publishes nothing.
- **The pool cache and the vocabulary cache are both evictable, with different consequences.**
  Losing the pool costs a rebuild; losing the vocabulary disables the feature until refetched, by
  the skip-rather-than-degrade rule above.
- **Rank is AniList's crowd, not the user's.** `Dungeon: 95` means AniList voters agree the tag
  characterizes the title. It is evidence about the title, and this ADR treats it as evidence about
  the reader by way of what they read.

## Revisit triggers

- If the AniList pool measurably beats the tag pool in the golden diff, decoding MangaDex's free
  list-endpoint tags becomes the next obvious work — and at that point the tag pool stops being
  provenance-only and the two pools stop being independent, which is when the agreement term needs
  re-examining.
- If the queue ever runs at its budget ceiling for sustained stretches, the `malId` side-cache is the
  first thing to add, and it is purely additive.
- If triples ever become viable — a much larger library, or a lower floor — the pair decision is what
  to reopen, not the seeding formula.
- If per-title spoiler suppression is ever wanted in the UI, that is the argument for widening
  `RankedTag` after all, and it should be taken together with a snapshot schema version, not alone.
- If a second consumer needs the tag vocabulary (a browse-by-tag screen, a taste debug view), the
  `Caches/` placement is what to reopen — a user-facing vocabulary is no longer "lose nothing but
  time."
