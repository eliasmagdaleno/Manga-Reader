# ADR-0011 — Spending the ranked axis: AniList as a candidate generator

- **Status:** Accepted (2026-07-28); amended 2026-08-03 (slice 2), 2026-08-04 (slices 3 and 4),
  2026-08-04 (slice 4 device check), 2026-08-04 (`MALReverseResolver` extraction discharged)
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

**Measured 2026-08-03 against the real device store — 22 Works, 58 history entries, 425-tag
vocabulary. Do not re-derive; re-run `TagPairSeedingDiagnostic` instead.**

- **13 Works carry a tag at rank ≥ 60**; 20 have engagement. The other 9 are provisional or
  unresolved, and a provisional snapshot has an empty ranked axis.
- **A single Work does not dominate the cut, and the reason is not the one that was predicted.**
  Every one of the top 20 pairs recurs in **≥ 2 Works**; no single-Work pair appears at all; the
  top 5 draws on 6 distinct titles. The prediction that Berserk would own the cut rested on
  misreading its `ranked=66` as engagement — it is a **tag count**. Berserk's engagement is
  mid-pack (2.179 against Iruma-kun's 5.005), so its 1035 candidate pairs each land near
  `2.179 × [0.6…1.0]`, far below the recurring pairs at 5–8.8. **Recurrence beats volume**, which
  is what the formula claims and had not previously been checked.
- **Therefore no per-Work cap or diversity rule was added.** The two candidates considered — one
  pair per Work, and recurrence-only weighting — were both rejected as unnecessary rather than
  wrong.
- **The top 5 does contain a triangle**: `Demons∧Magic`, `Demons∧Found Family`,
  `Found Family∧Magic` are the three edges of one triple over largely the same three Works, so
  three of five queries ask nearly the same question and will overlap under AND. **Left in
  deliberately** — a "no tag in more than N of the cut" rule is a guess, and slice 4's golden diff
  is the instrument that shows whether the overlap actually costs pool breadth. This is the open
  item this measurement leaves behind. **Resolved 2026-08-04 — see the next block; the overlap was
  measured and is small.**
- **Engagement is not persisted.** It is derived from history, which lives in **UserDefaults**, not
  Application Support — so reading the real store off-device needs `Library/Preferences/…plist`
  alongside `works.json`, and `devicectl … --source .` is rejected (use `--source Library`). The
  diagnostic decays recency against `Date()`, so its weights are not reproducible to the digit.

**Measured 2026-08-04 against live AniList — the triangle's three edges, `minimumTagRank: 60`,
`isAdult: false`, `sort: POPULARITY_DESC`, top 12 each. Do not re-derive; re-run the three queries.**

The 2026-08-03 block left the triangle open on the assumption that three pairs over the same three
tags ask "nearly the same question." **They do not.** Across 36 slots the three edges return **29
distinct titles**:

| Appears in | Count | Titles |
|---|---|---|
| all 3 pools | **2** | Berserk, The Greatest Estate Developer |
| exactly 2 | **3** | Tsugumomo, Welcome to Demon School! Iruma-kun, Ichi the Witch |
| exactly 1 | **24** | — |

The tags overlap; the catalogue regions largely do not. `Demons∧Magic` returns shounen battle (Solo
Leveling, Jujutsu Kaisen, Black Clover), `Demons∧Found Family` returns darker ensembles (Chainsaw
Man, The Promised Neverland, The Girl From the Other Side), `Found Family∧Magic` returns soft and
slice-of-life (Witch Hat Atelier, Miss Kobayashi's Dragon Maid, WITCH WATCH). A shared tag pair is
not a shared neighbourhood, which is the thing this measurement establishes and the earlier
prediction got wrong.

Two consequences, both **no change**:

- **Breadth costs ~7 duplicate slots in 36.** Real, small, and not worth a "no tag in more than N of
  the cut" seeding rule. The 2026-08-03 decision to leave the triangle in now rests on evidence
  rather than on declining to guess.
- **`withinPool` sums over every pair that surfaced a candidate** (see the scoring decision below),
  so a title in all three edges collects three terms. That is the same "agreement outranks strength"
  shape rejected for the cross-pool agreement term — one level down, inside the AniList pool, where
  that argument had not been applied. **It stands**, because the measurement says it applies to 2
  titles, one of which (Berserk) is a seed Work and so is a library title the candidate path drops
  anyway. Capping or `max`-ing the per-pair contribution is a two-line change and stays available;
  it is not worth paying for roughly one title per refresh against `wAniList = 0.6`.
  **Accepted cost:** the sum is knowingly unbounded in the number of contributing pairs, and a
  future store whose top pairs *are* redundant would amplify one cluster with nothing to stop it.
  The revisit trigger below is what catches that.

Also re-confirmed at the floor this ADR actually uses: all 12 `Demons∧Magic` results carry **both**
tags at rank ≥ 60 (weakest legs: Slime 61/74, Solo Leveling 64/87). The Context block's AND-semantics
finding was verified at ranks 0 and 80 on 2026-07-28; this extends it to 60.

**Facts verified live 2026-08-04, running slice 4's device check (do not re-derive):**

- **`RecommendationEngine`'s cold-start gate runs *before* any provider is constructed, and
  darkens all three pools at once.** `profileAndExclusions()` returns `nil` when
  `profile.taggedMangaCount < 3` (`RecommendationEngine.swift:151`), and `rebuild()` returns on
  that `nil` **without calling `makeProvider`** — so below the threshold the AniList provider is
  never built, never queried, and its own contributing-Works gate is never asked. The observable is
  an empty rail *and* an absent pool cache, from one cause. A device check that reads only the
  absence of `Caches/anilist-pool.json` cannot distinguish this from broken wiring, and on
  2026-08-04 one did not: it recorded a negative against a store holding **2** tagged Works.
- **`taggedMangaCount` counts Works reachable from `history.entries`, not Works in the store.**
  Signals are built by grouping history entries by Work (`RecommendationEngine.swift:172+`), and
  `taggedCount` increments only for a signal whose tags are non-empty (`TasteProfile.swift:115-116`).
  A tagged Work that was saved but never read contributes nothing to the gate.
- **Tags reach a Work by two independent routes, and a Work can miss both.** Either a provider fetch
  (MAL match → AniList), or the provisional tier built from a Listing's own tags
  (`WorkStore.swift:157`, `:171-180`) — which for MangaDex arrive free with the detail fetch. On the
  check's store, one Work carried 9 MangaDex tags while its `upgrade-attempts.json` entry read
  `unmatched`: provisional-only, and still counted by the gate.
- **The composition root hands the provider single store instances.** Relaunching against a warm
  pool left `anilist-pool.json` byte- and mtime-identical across a 60s poll while the For You rail
  rendered — so `rebuild()` ran, `makeProvider` ran, and `refreshIfNeeded` found a record and
  no-oped. A per-build `AniListPoolStore` would have held no record and refetched. This discharges
  the wiring hazard below.
- **The cold path completes unattended.** A container empty at 15:57 held a full pool by 16:21 — 5
  seed pairs, 12 of 12 head candidates reverse-resolved, three of them multi-pair contributors —
  produced by ordinary reading, with no scripted run.

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

### Seeds are the top 5 **co-occurring** pairs, excluding `Technical`, `Cast-Main Cast` and `Demographic`

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

**Amended 2026-08-03, after slice 2 ran against the real store** (see the measurements below):

- **`Demographic`** (Shounen, Seinen) joins the exclusion set. The real store seeded four
  demographic pairs into its top 20. Same argument as `Cast-Main Cast` — a demographic covers an
  enormous slice of the catalogue, so as a leg of an AND it barely narrows anything. This is
  knowingly the *weakest* of the three: `Seinen ∧ Tragedy` is at least a coherent question where
  `Full Color ∧ Tragedy` is not. It was excluded because none of the four reached the cut, so the
  change costs nothing observable today while stopping a near-tautology from displacing a real
  pair as the store grows. **Accepted cost:** a real signal is being discarded on a prediction
  about future data, and the top 5 is identical with and without it — so there is currently no
  evidence this decision is *right*, only that it is free.
- The adult exclusion is an **injected parameter** (`excludeAdultTags`, defaulting to `true`), not
  a constant. It is a fact about *which branch this is*, not about the domain: hardcoding it puts a
  permanent body diff on the private branch that every merge from `main` must re-resolve, which is
  the shape that eventually resolves the wrong way. A parameter keeps the private branch to a
  call-site change and makes both behaviours testable from `main`.
- Ties are broken **lexicographically** after weight. Not decoration: every pair inside one Work
  shares that Work's engagement and the multiplier band is only `[0.60, 1.00]`, so exact-tie blocks
  are the common case and the top-5 cut runs through one. Swift's sort is not guaranteed stable, so
  without a total order the golden file in slice 4 would diff on re-sorts rather than on rankings.
  **Accepted cost:** alphabetical order is meaningless — where a tie block spans the cut, which
  pairs survive carries no signal and must not be read as any.

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

**Amended 2026-08-04, designing slice 3.** The policy above survives unchanged; what follows fills
the holes it left. Every one of these is a decision the original text did not make.

- **The refresh state lives in an `actor AniListPoolStore`** (`Services/`), owning the `Caches/`
  file, the in-memory copy, and an **in-flight `Task` keyed by the seed-pair set**. The provider
  stays a `struct` holding a reference to it. `load()` fires on every Home appearance, so without
  in-flight dedupe two appearances two seconds apart kick two independent 5-query refreshes for the
  same seeds — 10 requests against a 30/min budget. Returning the *same* `Task` to the second caller
  is the fix and it needs actor isolation to be race-free. `TagVocabularyStore`'s plain-class shape
  was rejected as the model: that store *awaits* its fetch (`TagVocabularyStore.swift:105`), which is
  right for one caller on a cold path and is exactly what this design exists not to do. A
  `@MainActor` class matching the app's other stores was rejected for putting a 40-title JSON
  encode/decode on the main actor and making the provider main-actor-bound, which
  `CandidateProvider` is not. The refresh is an **unstructured `Task` created inside the actor**, so
  it does not inherit the rail build's cancellation — read-through means nothing if the refresh dies
  with the caller that triggered it.
- **Empty pools are cached, at a 24-hour TTL** — the one place the 14-day number does not apply.
  "Fetched and empty" is distinguished from "never fetched" in the record. Not caching empties at
  all means the user whose top pair is genuinely rare re-issues 5 AniList requests on every Home
  appearance, forever — the hazard below, made expensive. Caching them for 14 days is also wrong,
  because a transient AniList hiccup that returns HTTP 200 with an empty page is indistinguishable
  from a real empty, and eating a fortnight of dark rail for that is worse than re-asking.
  **Accepted cost:** a third TTL in a codebase whose stated preference is one number, and at most
  one wasted 5-request refresh per day for a sparse-taste user.
- **All five pair queries must complete without throwing, or nothing is written.** The record's
  identity *is* the seed-pair set, so an entry keyed on five pairs but built from three is lying
  about its own key, and slice 4's golden would show a thin pool with no way to attribute it.
  Caching the partial with its contributing subset was rejected: it decouples key from contents, so
  every consumer must handle subset provenance, and staleness gains a second dimension. Aborting is
  nearly free — the previous entry stands and the next Home appearance retries seconds later.
  **A query returning zero results is not a failure**: under AND semantics that is a normal outcome,
  and treating it as an error would abort refreshes for precisely the sparse-taste user and prevent
  the empty record above from ever being written.
- **`perPairLimit = 12`, deduped, capped at 40 unique titles — and candidates are scored *before*
  any resolution, with only the top 12 resolved.** The AniList side costs 5 requests regardless; the
  real fan-out is that every `idMal` without a fresh `EntityResolutionStore` hit costs one live
  MangaDex title search (`MoreLikeThisProvider.swift:107`), so 20 per pair is up to 100 searches on
  a cold cache. `withinPool` is computable from the AniList response alone, so the whole pool can be
  ranked for free and budget spent only on the head; a title ranked 47th will never reach a rail
  that shows a handful of cards. 40 matches the existing `poolLimit` so this pool is not
  structurally larger than the ones beside it. Resolving everything was rejected — better second-
  refresh economics, but it front-loads up to 60 searches for a user who may never scroll, against
  a MangaDex rate limiter the AniList limiter knows nothing about. **The ordering is the decision;
  the constants are tunable, doing it the other way round is not fixable without restructuring.**
- **Resolution failures never abort and never backfill.** A title failing to resolve is the *normal*
  case — AniList's catalogue and MangaDex's are different sets — and there is no honest way to
  separate "MangaDex doesn't have it" from "the search 500'd" without the subset provenance rejected
  above. Backfilling to top the head back up to 12 would turn a bounded fan-out into a loop whose
  length depends on network luck, spending the most budget exactly when MangaDex is least healthy.
  A minimum-resolved floor was rejected as a guess at a threshold, the same shape of guess this ADR
  declined to make for pool diversity. **Accepted cost:** total MangaDex failure self-heals within a
  day via the 24-hour empty TTL, but a *partial* — 4 of 12 resolving — is written with the full 14.
  Slice 4's golden is the instrument that would show it.
- **The cached record stores raw material, not scores.** Per title: the resolved `Manga` plus, per
  contributing pair, its `min(rank_a, rank_b)`. `withinPool` is recomputed at read time against
  today's `pairWeight`s. The `min(rank)` half is a frozen property of the title; `pairWeight` is
  not — engagement is recency-decayed against `Date()`, so a stored score is a 14-day-old snapshot
  of a drifting quantity. Recomputation is arithmetic over ~12 titles on an already-`async` path,
  and it gives the right split: **membership is expensive to refresh, ordering is free.** It also
  covers the case the cache key cannot — a taste shift that reweights the same five pairs without
  reordering them does not invalidate the entry, by design, and that is exactly where frozen scores
  go quietly wrong. Freezing was defensible on the grounds that `compose`'s per-session reshuffle
  already exceeds this precision, but that reshuffle is exploration noise layered on a *correct*
  ranking; using it to excuse a stale one is how the two stop being distinguishable.
- **The provider never calls `TagVocabularyStore.vocabulary()`.** That method awaits a network fetch
  whenever the cache is absent *or* older than 30 days (`TagVocabularyStore.swift:105-113`), so
  calling it on the rail path stalls Home behind a 27 KB request and a limiter slot — on cold launch
  after a `Caches/` purge, which is the case that placement deliberately accepts. A non-fetching
  `cachedVocabulary()` plus a fire-and-forget `refreshIfNeeded()` are added; the existing
  `vocabulary()` is untouched for its current caller. **Staleness is fine for this consumer and
  absence is not**: categories move on the order of years, and an unknown tag already stays seedable
  by the deny-list rule, so a 40-day-old vocabulary is a non-event — while a missing one triggers
  the skip-rather-than-degrade rule above, returning `[]` and refreshing in the background, which is
  indistinguishable to the user from a cold pool miss.
- **A corrupt or undecodable cache file is treated as a miss**, matching
  `TagVocabularyStore.loadIfNeeded`'s `try?`.

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

**Amended 2026-08-04, designing slice 3 — the gate is counted on *contributing* Works, inside the
provider.** Seed first, then require the resulting pairs drew on **≥ 3 distinct Works**.

Counting Works with a non-empty `snapshot.tags` is the obvious reading and is subtly wrong: a Work
can carry ranked tags where none clears `minimumSeedTagRank`, or where every tag clearing it sits in
an excluded category. Those Works contribute nothing, so counting them lets the gate open on a store
that then produces zero pairs — and a zero-pair store yields an empty pool, cached for 24 hours by
the rule above. The gate would be doing the opposite of its job. Counting contributing Works states
the property this ADR already argues for — "a recurring pair is taste, a one-off is an accident" —
directly rather than through a proxy.

**This reopens slice 2:** `SeededTagPair` gains `contributingWorks: Set<WorkID>`, the Works that
carried both legs at rank ≥ 60 and therefore contributed a term to the pair's weight. The gate is
then `Set(pairs.flatMap(\.contributingWorks)).count >= 3`. Per-pair rather than a summary union for
the same reason the weight travels with the pair: slice 4's golden is more readable with the datum
next to what it describes — and here it makes the **triangle** measured on 2026-08-03 directly
visible, since overlapping edges can be seen drawing on the same Work ids rather than inferred. A
separate `contributingWorks(...)` function was rejected outright: it re-walks the admission logic in
a second place, and the two can then disagree about what a contributing Work is, which is the exact
failure this gate definition exists to prevent. **Accepted cost:** churn on 15 green slice-2 tests,
most of which must now state provenance they do not care about.

The gate lives **in the provider**, not in `RecommendationEngine`. Putting it in the engine would
make the engine know what a ranked axis is and how to count one, to serve one of its three pools —
the knowledge accumulation ADR-0010's one-way closure was chosen to prevent
(`RecommendationEngine.swift:34-36`). A provider returning `[]` is already fully supported
(`CandidateProvider.swift:193-197`).

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

**Amended 2026-08-04, designing slice 3 — when several pairs surfaced the same title, the reason
names the pair contributing the largest term to its `withinPool` score**, with a lexicographic
tiebreak on the canonical pair.

The original text fixed the format and the spoiler rule but never said which pair wins, and the
2026-08-03 measurement makes multi-pair overlap the *dominant* case rather than an edge one: the
triangle means three of five seeds ask nearly the same question over the same Works. Naming the
largest contribution keeps the reason string explaining the title's actual placement instead of
telling a second, unrelated story about it. The tiebreak is load-bearing for the same reason slice
2's was — within a Work every pair shares that engagement and the multiplier band is `[0.60, 1.00]`,
so exact ties are ordinary and Swift's sort is not stable; without a total order the reason flips
between builds on identical data.

Naming the highest-weighted *seed* pair instead was rejected: it decouples the reason from the
ranking, so a title that scraped in at 61 on the top pair and dominated on the fourth is explained
by the pair it barely matched.

**Spoiler suppression degrades the text, it never re-picks the pair.** If the winning pair is
`Reincarnation ∧ Magic`, the string is `"More Magic"` — not the next pair down with two clean legs.
Falling through would make the printed reason describe a weaker contribution than the one that
actually placed the title, breaking the trace back to the score.

### The provider splits into a pure core and an I/O shell, and lands unreferenced

**Amended 2026-08-04 — a new decision, recorded here because it only makes sense beside the policies
above.**

`MoreLikeThisProvider` calls `MangaDexAPI.searchManga` and `fetchMangaByIdsWithCovers` as statics
inside a private method (`MoreLikeThisProvider.swift:107`, `:71`), so it has no injection point. If
the AniList provider does the same, every policy decided above is testable only against live
network. Instead: a **pure, synchronous core** takes the per-pair `[AniListWork]` plus the seed pairs
and returns candidates ranked by `pairWeight × min(rank_a, rank_b)/100` — that is the "score first"
step, total and network-free — and a thin shell does seed → 5 transport-faked queries → core → **an
injected `Resolve = ([Int]) async -> [Int: Manga]` closure** → cache write. The closure is the
`MetadataUpgradeQueue.Sleep` pattern (`MetadataUpgradeQueue.swift:13`), this codebase's established
answer to a dependency worth faking without a protocol. Each policy then has a deterministic test: a
`Resolve` returning short exercises the no-floor rule, one returning nothing exercises the 24-hour
empty, a transport throwing on query 3 exercises the abort.

**`reverseResolveViaSearch` is deliberately not extracted into a shared helper this slice.** It is
40 private lines, and the two callers want different things — MoreLikeThis resolves in
recommendation order and drops self; this one resolves a scored head. Extracting means changing a
shipped, working path in the same slice that adds a new one, and slice 4's golden needs exactly one
cause — the argument that already deferred MangaDex tag decoding. If both paths still look alike
after slice 4, extract then, with the golden in place to prove nothing moved. Wrapping MangaDex
behind a protocol was rejected as larger than this slice. **Accepted cost: two resolution paths on
`main` until at least slice 4.**

**Amended 2026-08-04, after slice 4 merged — the extraction is discharged, and the reason given for
deferring it turns out to have been wrong.**

`MALReverseResolver` (`Services/MALReverseResolver.swift`) now owns `ReverseTarget`, the
cache-hit/miss partition, the bounded-concurrency search, and the batch fetch, exposing
`resolve(_ targets:) -> [Int: Manga]` plus an `resolve(works:limit:)` adapter for the pool.
`MoreLikeThisProvider.resolve(works:limit:)` is deleted, not shimmed — a forwarding stub would have
kept the naming debt the extraction existed to retire. The callers lost 162 lines and gained 22.

**The cut is wide on purpose.** The narrow alternative — extract only the search helper, leave the
partition and batch-fetch assembly in both callers — is what the code already effectively had, since
`reverseResolveViaSearch` was one private method both called. It moves a file boundary without
removing the ~25 duplicated assembly lines that made the extraction worth doing at all. What stays
with the callers is **ordering**, and only ordering: `recommendations(for:)` reassembles in
MAL-recommendation order and drops self; the pool takes the map as-is because `buildRecord` already
holds its ranking. That is the same argument the paragraph above makes for why they differ — it just
turns out to be an argument about ordering, not about the resolution beneath it.

**The correction, which matters more than the extraction.** The sentence above — *"extract then,
with the golden in place to prove nothing moved"* — is false, and it was repeated into three
handoffs and acted on as a reason to defer. The golden pins the **blend**, never the **resolution**:
every AniList test stubs `Resolve` outright (`AniListPoolTests.swift:315`, `:349`, `:390`) and the
MAL path stubs `SimilarTitlesProviding`. Both existing safety nets inject *past* the code being
extracted, which had **zero** coverage — it was private, and it called `MangaDexAPI` statics.

So the extraction carries its own net rather than borrowing one. `search` and `fetchByIds` are
injected `@Sendable` closures defaulting to the real endpoints — the same `Sleep`/`Resolve` pattern
argued for above, applied to the thing that most needed it. `MALReverseResolverTests` pins the
cache-write discipline (`.resolved` / `.unresolved` / **nothing on a thrown search**), the partition,
the stale-miss re-attempt, and the adapter's limit and `malId` filtering. That discipline was
previously prose in a doc comment, trusted to be noticed; a second implementation writing
`.unresolved` on a transient throw would poison `EntityResolutionStore` against a title for the full
14-day TTL, invisibly. **Verified by mutation:** flipping `else if didSearch` to `else` fails exactly
the two tests that name the case, and nothing else.

**Accepted cost:** four injection points on the resolver and one more parameter on
`MoreLikeThisProvider.init`, all defaulted, so no call site was forced to change. And the generalized
lesson, which is not local to this file: **an untested path cannot be refactored under a golden that
stubs it.** Before citing a golden as licence to move code, check the tests actually reach the code.

**Still parked:** widening `MoreLikeThis.pickMatch` to take `AniListWork.knownTitles` rather than a
single title. `ReverseTarget` keeps `title: String`. Tempting while holding the type, and now
provable — but the widening *changes matching behaviour*, and this extraction's whole claim is that
nothing moved. Two causes again. See the residual recorded under the `Resolve` decision below.

**Amended 2026-08-04, implementing slice 3 — two decisions the design above did not make,
recorded because both were forced by the compiler rather than chosen freely.**

- **Works reach the provider through a `LoadWorks = @Sendable () async -> [Work]` closure.**
  Seeding needs Works, `WorkStore` is `@MainActor`, and this provider deliberately is not —
  so it cannot hold the store. A closure is the same one-way shape as
  `RecommendationEngine.PriorityPush`: the provider can read Works and can do nothing else
  to the store. Passing a `[Work]` snapshot at construction was rejected because the
  provider outlives any one rail build and the store changes under it.
- **`Manga` gains `Codable, Equatable` on the type**, not via an extension: Swift only
  synthesizes those in the declaring file, and a cross-file `extension Manga: Codable {}`
  does not compile. A lossy mirror in `LibraryItem`'s shape was rejected — a pool entry
  that dropped `malId` or `sourceId` could not produce an openable candidate.
  **Accepted cost:** `Manga` is now persistable everywhere, and a field added to it silently
  changes the pool cache's format. The corrupt-file-is-a-miss rule is what contains that.

Two things the design predicted turned out cheaper than stated. The slice-2 churn was **one
new test, not 15** — the existing tests assert on `.pair` and `.weight`, never on whole
`SeededTagPair` values, so the added field did not touch them. And `rankPoolCandidates`
could not be written as one `map`/`sorted`/`prefix`/`map` chain; the type checker times out
on it. It is explicit loops, which the ordering comments now have to carry alone.

**Slice 3 lands unreferenced.** `RecommendationEngine` still constructs the composite with `tag:` and
`mal:` only (`RecommendationEngine.swift:66`). The moment the provider is reachable, the AniList pool
contributes to `foryou-ranking.txt` and slice 4's diff can no longer answer the one question it
exists for. Wiring it at `wAniList = 0` was rejected as looking inert without being it: a zero weight
still admits the pool to the composite's `manga` and `reason` dictionaries, so it can supply titles
the other pools missed and overwrite reasons on titles they did not — the golden moves anyway, which
is worse than obviously-dead code. **Accepted cost: the cache never warms before slice 4**, so the
first golden run after wiring sees a cold miss on the pool and possibly the vocabulary, and reads as
a broken feature if unexpected. Run it, wait, run it again.

### `Resolve` takes whole `AniListWork`s, not `malId`s — reversing a slice-3 decision

**Amended 2026-08-04, implementing slice 4.** Slice 3 declared
`Resolve = ([Int]) async -> [Int: Manga]`, on the reasoning that `idMal` is the bridge and the
id is therefore all the closure needs. Implementing the closure showed that is wrong.

Reverse-resolution **is title matching**. `MoreLikeThis.pickMatch` takes a `malTitle`
(`MoreLikeThis.swift:19-28`), and the only route to candidates at all is
`MangaDexAPI.searchManga(title:)`. `buildRecord` held the complete `AniListWork` and discarded
everything but the id one line before calling `resolve`, so the closure would have had to buy the
titles back: one `MyAnimeListAPI.mangaDetail` per unresolved id, up to `poolResolveLimit` per
refresh, against a MAL budget this ADR never costed. The alternative that beat the original is
simply passing what we already have.

`buildRecord` now filters the head to works carrying a `malId` before handing them over — without
one there is no bridge by any route, so such a work must not consume a slot in the resolve batch.

**Accepted cost:** this edits a shipped, reviewed, committed public typealias and the tests pinned
to it, so slice 4 is **not** purely additive as planned. It is done in the commit that first makes
the type reachable, before any golden is regenerated, so the golden diff's attributability is
unaffected.

**Residual, and it is a real one:** `AniListWork.knownTitles` carries romaji, english, native and
synonyms — a richer left-hand side than MAL's single title — but `pickMatch` accepts one title, so
only the primary reaches the matcher. Widening the matcher would change the shipped MAL path in the
slice whose golden must have exactly one cause. The strong arm, an exact `malId` hit among the
search candidates, does not use the title at all.

### The composite stays fixed-arity; the two caches are owned by the app

**Amended 2026-08-04, implementing slice 4.**

`CompositeCandidateProvider` gains a named `ani:` property and `wAniList`, rather than becoming a
`[WeightedPool]`. The *formula* generalizes to n; the *type* is not thereby obliged to. Against the
array: the golden's `tagNorm` / `aniNorm` / `malNorm` columns and its weights header are read off
named properties, and the `tag < AniList < MAL` precedence is three ordered assignments over named
pools rather than a priority field per element. No fourth pool is on any roadmap.
**Accepted cost:** a fourth pool would be a real refactor of a shipped, goldened path.

`ani` defaults to a new `EmptyCandidateProvider`. This is not a convenience default: the paths that
take it — SwiftUI previews, and every test about the blend rather than the pool — genuinely must not
do AniList network. It is distinct from the `wAniList = 0` wiring rejected above, which would have
admitted the pool to the `manga` and `reason` dictionaries while claiming to be inert.

`AniListRateLimiter`, `TagVocabularyStore` and `AniListPoolStore` are constructed **once in
`Manga_ReaderApp.init`** and captured by the `makeProvider` closure; `makeProvider`'s signature is
unchanged. Both stores are actors whose state must outlive a rail build — `AniListPoolStore` holds
the in-flight refresh and the superseded-seeds guard — and `makeProvider` runs on *every* rebuild,
so a store built inside it would mean no refresh is ever in flight and the pool never warms. The
provider struct itself is rebuilt per call, which is correct: only the actors need identity.

Widening `makeProvider` to take a dependency struct was rejected because all four existing
`RecommendationEngine(...)` sites rely on the defaulted closure and want no AniList machinery.
**Statics/`.shared` were rejected on precedent:** `EntityResolutionStore.shared` is already this
codebase's cautionary tale (`MetadataUpgradeQueue.swift:66`), and both stores take a `directory:`
for testability that a shared instance would fight.

The limiter is now passed **explicitly** into `MetadataUpgradeQueue` rather than left to its default
argument (`MetadataUpgradeQueue.swift:54`). The "one owner of the rate limiter" claim this ADR
amends ADR-0007 with was previously true only by accident of that default.

### The vocabulary refresh is kicked at launch

**Amended 2026-08-04, implementing slice 4.** Traced on the shipped code, the cold path costs
**three** rail builds, not two: build 1 finds no vocabulary and returns `[]` *before seeding at all*
(`AniListCandidateProvider.swift:68-71`), build 2 seeds but misses the pool, build 3 has one. And
`RecommendationEngine.load()` is `guard !loadedOnce` (`:87`), so "build" means app launch or a
deliberate pull-to-refresh — not a tab switch.

`Manga_ReaderApp`'s launch `.task` now calls `vocabularyStore.refreshIfNeeded()` beside
`queue.start()`, collapsing three to two. The provider's own kick **stays**: it is the correctness
path for a `Caches/` eviction mid-session, `refreshIfNeeded` is idempotent, and both firing is a
no-op.

Making build 1 *await* the vocabulary was rejected outright — it converts skip-rather-than-degrade
into block-the-rail. Accepting three was the real alternative, and `TagVocabularyStore.swift:128`
argues against launch-time fetching; the answer is that its concern is *blocking* Home, which a
fire-and-forget kick does not.

### The golden gets a stub pool, and the seam gets its own test

**Amended 2026-08-04, implementing slice 4.** The AniList pool enters `foryou-ranking.txt` as a
hand-scored `StubPool`, not as a real `AniListCandidateProvider`.

A real provider would put `withinPool` arithmetic, both TTLs, and a read-through that returns empty
on first call inside the golden's blast radius — against a fixture whose stated principle is that
every number in the file is derivable with a calculator, and a hand-maintained no-ties invariant
that emergent scores would leave to luck. Everything a real provider would add is already pinned
deterministically by slice 3's 25 tests.

The fixture carries **four** cases, each making one decision readable: a title in all three pools
(the only row where `n = 3`, and where the rejected pairwise sum would have paid `3 x
agreementBonus` instead of one); a tag+MAL title **absent** from the AniList pool, whose row must
stay byte-identical as the control for the n=2 reduction; an AniList-only title showing `wAniList`
in isolation; and a tag+AniList title whose reason must flip to the conjunction while the
three-pool title keeps its MAL reason — pinning both directions of precedence.

**The slot and its data landed in two separate commits**, so the reduction-to-n=2 claim is an
artifact rather than an inference from unchanged rows inside a busy diff. It held: with the pool
empty, every `agree` and `final` value was byte-identical and no row moved.

**Accepted cost:** the golden never exercises the wire between the real provider and the composite.
That is covered by `AniListPoolTests.testTheAniListPoolReachesTheComposite` — real provider, real
composite, cold call degrading to the tag ranking, then after the refresh settles the AniList reason
overriding the tag one. Deliberately **not** goldened: it needs a settle, and a golden whose content
depends on a sleep is the flake the no-ties invariant exists to avoid.

## Hazards

- **A reader whose history is dominated by an untaggable source can never open the *engine's* gate,
  no matter how much they read.** This is upstream of, and distinct from, the WeebCentral hazard
  below: that one is about this ADR's contributing-Works gate inside the provider, whereas this one
  closes `RecommendationEngine`'s `taggedMangaCount >= 3` check and darkens **all three** pools.
  A Work reaches the count only via a MAL match or a Listing carrying its own tags
  (`WorkStore.swift:157`); a Listing from a source that supplies neither tags nor a resolvable
  external id has **neither** route available — an opaque numeric id matches nothing on MAL, and
  there are no Listing tags to build a provisional snapshot from. Such a Work still contributes
  *weight* to the profile (`TasteProfile.swift:110-115`), so it looks like signal and counts as
  none. Observed live 2026-08-04: a store of 5 Works, 3 of them untaggable by both routes and all
  3 recorded `unmatched`, sat permanently at `taggedMangaCount == 2`. Reading more from such a
  source moves the number by zero, forever, with no error and nothing in the UI to explain it.
  **Not addressed
  here** — it is a property of the Work model (ADR-0007/ADR-0009), not of the ranked axis, and
  fixing it inside this ADR's subsystem would be fixing it in the wrong place.
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
- **There are now three staleness numbers in this subsystem** — 14 days for a populated pool, 24
  hours for an empty one, 30 days for the vocabulary — against a codebase that deliberately holds
  one. Each is argued, but "which TTL applies here" is now a question that can be got wrong.
- **A 4-of-12 pool is written with the full 14-day TTL** and nothing distinguishes it from a healthy
  one. Only total resolution failure self-heals quickly, via the empty-pool TTL.
- **Nothing automated proves the app hands the provider *single* store instances.** The Q6 seam test
  covers provider-to-composite; the composition root in `Manga_ReaderApp.init` is not testable
  without either constructing the App type or duplicating the wiring, which would assert the copy.
  The sole detector is a human running the app twice and noticing the pool warms on the **second**
  launch — and the slice-3 handoff primes the reader to *expect* an empty first run, which is
  exactly the expectation that could absorb a real bug. **With the launch kick in place the
  expected number is two launches; a third empty run means the capture is wrong.**
  **Discharged 2026-08-04** by the relaunch check in the Context block above — the pool cache went
  unmodified across a relaunch that rendered the rail, which a per-build store cannot do. The hazard
  stands as *written* for any future change to `Manga_ReaderApp.init`: it is still the case that
  nothing automated proves this, and the detector is still a human. What the check also proved is
  that **the detector needs a precondition**: the sole observable, an absent pool cache, has a cause
  upstream of the wiring, and the 2026-08-04 run mistook one for the other. Verify
  `taggedMangaCount >= 3` from the container **before** treating an absent pool as a wiring result;
  below the threshold the run is invalid, not negative.
- - **Rank is AniList's crowd, not the user's.** `Dungeon: 95` means AniList voters agree the tag
  characterizes the title. It is evidence about the title, and this ADR treats it as evidence about
  the reader by way of what they read.

- **A golden that stubs a dependency proves nothing about that dependency.** This ADR told a future
  session it could extract `reverseResolveViaSearch` "with the golden in place to prove nothing
  moved." It could not: `foryou-ranking.txt` reaches the pool through a stubbed `Resolve` and the MAL
  path through a stubbed `SimilarTitlesProviding`, so the resolution code the sentence licensed
  moving was the one thing no test executed. The claim survived into three handoffs unchallenged
  because it was written down. Generalized: before citing a fixture as licence to move code, confirm
  the fixture's execution actually reaches it — a stub is exactly a promise that it does not.

## Revisit triggers

- Decoding MangaDex's free list-endpoint tags was gated on the AniList pool going through a golden
  diff. **Amended 2026-08-04: that gate is now satisfied and is not sufficient on its own.** Slice 4
  shipped and the golden exists, so the sentence above reads as a green light; it is not one. The
  binding condition is the second one, and it is untouched: decoding those tags moves the tag pool
  off provenance-only, and the two pools stop being independent observers — they would partly share
  a source. The agreement term rewards independent convergence, so over correlated pools it inflates
  confidence instead of measuring it. **The golden cannot adjudicate this**, which is the trap: it
  pins outputs, every output would move, and every move would have a plausible story while the
  invariant that broke is a statistical one no fixture asserts. Re-examine the agreement term
  *first*, as its own decision — the decoding is the easy half. This holds for a provenance-only
  decoding too, unless it is genuinely never read by scoring.
- **`AniListPool.swift`'s pure-core style has a compile-time cost, and it has now bitten twice.**
  The core is written as chained `map`/`sorted`/`reduce` over inferred tuples, which is what makes
  it readable and testable without a transport — but each chain is one expression for the type
  checker, and two of them have hit *"unable to type-check in reasonable time"*: once during slice 3
  and once in `poolReason` on 2026-08-04, the latter **passing locally and failing on CI**. That
  asymmetry is the real hazard: the timeout is marginal rather than deterministic, so a green local
  build does not predict a green CI one, and the failure surfaces after review rather than during
  it. Fixed both times by naming an intermediate type and annotating the binding. **If a third
  occurs, stop treating them as individual bugs** — the answer is a house rule for this file (named
  types over inferred tuples in any chain that mixes a dictionary lookup with arithmetic), not a
  third local fix.
- If the queue ever runs at its budget ceiling for sustained stretches, the `malId` side-cache is the
  first thing to add, and it is purely additive.
- **If a future seeding diagnostic shows the top-5 pairs sharing more than ~40% of their results**,
  the unbounded sum in `withinPool` becomes a real amplifier and is the thing to reopen — not the
  seeding formula, which is honestly reporting a redundant taste. The 2026-08-04 measurement puts
  today's figure at 7 duplicate slots in 36 (~19%) for the worst case in the cut, so there is roughly
  a factor of two of headroom before this matters.
- If triples ever become viable — a much larger library, or a lower floor — the pair decision is what
  to reopen, not the seeding formula.
- If per-title spoiler suppression is ever wanted in the UI, that is the argument for widening
  `RankedTag` after all, and it should be taken together with a snapshot schema version, not alone.
- If a second consumer needs the tag vocabulary (a browse-by-tag screen, a taste debug view), the
  `Caches/` placement is what to reopen — a user-facing vocabulary is no longer "lose nothing but
  time."
