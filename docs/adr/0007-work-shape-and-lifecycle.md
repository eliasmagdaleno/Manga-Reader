# ADR-0007 — The Work's shape and lifecycle

- **Status:** Accepted (2026-07-25)
- **Amends:** ADR-0002 (its sizing argument — see "Minting", below)
- **Related:** ADR-0001 (Work vs Listing), ADR-0004 (fulfillment routing), ADR-0005 (manual link)

## Context

ADR-0001 said the recommender must rank Works; ADR-0002 said a local store owns them and
persisted them as JSON. Neither said what a Work *is* — how its id is generated, what fields it
carries, when it comes into existence, or what happens when two of them turn out to be the same
manga. That gap blocked the next slice: the AniList client's response type is only designable
once the Work it feeds is designed.

Facts verified live on 2026-07-25 (do not re-derive):

| | vocabulary | ranked? | searchable via `mangaByTag`? |
|---|---|---|---|
| MangaDex tags | **77** (25 genre / 38 theme / 12 format / 2 content) | no | yes, by display name |
| AniList `genres` | **19** | no | 18 of 19 map onto MangaDex genre tags |
| AniList `tags` | **425** (Cast-Traits 73, Sexual Content 65, Theme-Other 59…) | **yes, 0–100** | mostly **no** |

- **Only 32 of MangaDex's 77 tag names exist in AniList's 425-tag vocabulary.** The 45
  MangaDex-only names are the load-bearing ones — `Action`, `Romance`, `Fantasy`, `Comedy`,
  `Drama`, `Horror`, `Mystery`, `Sci-Fi`, `Slice of Life`, `Supernatural` — absent because AniList
  models them as `genres`, a *separate field* from `tags`. The two systems are not rival
  vocabularies; they are **two granularities**.
- **AniList's live rate limit is `x-ratelimit-limit: 30`/min**, not the 90 its documentation
  advertises. One request per two seconds.

## Decisions

### Identity: opaque Work id + an external-id index

The Work id is a locally-minted UUID, opaque and **immutable for the life of the Work**. Dedupe
runs through an `externalId → workId` index, not through the id's spelling.

A key derived from the first external id (`"anilist:105398"`) was rejected on one argument:
**merge is unavoidable, so do not buy a key scheme whose only benefit is avoiding merge.** ADR-0002
permits Works no provider knows (minted from a WeebCentral read), and ADR-0005's manual link
override *is* a merge — the user says "this Listing is that Work" when the Listing usually already
has a local-only Work. A derived key would therefore have to mutate after being persisted.

### The edges stay Listing-keyed; the Work lives at the seam

ADR-0001 left an "or" unresolved: the existing stores either re-key onto the Work id **or carry a
mapping**. They carry a mapping. `HistoryStore`, `LibraryStore`, `TasteProfileStore` and
`EntityResolutionStore` keep recording `(sourceId, mangaId)` exactly as they do today; the Work
store owns `Listing → Work`, and the *recommender* resolves through it when building the profile.

- It **deletes the first-launch migration risk** ADR-0001 flagged ("history orphans"). There is no
  re-key, so there is nothing to orphan.
- A merge then mutates **one file**. Re-keying would require consistently updating seven
  UserDefaults keys plus a JSON file, with **no transaction spanning UserDefaults and a file**,
  against four live `@MainActor @Published` singletons.
- A reading entry is intrinsically a Listing fact — chapter numbering is per-source (ADR-0004
  accepts this), and `ReadingEntry` already carries `sourceId`.

**Accepted cost:** cross-source reading progress is left undefined. Chapter 12 read on MangaDex and
chapter 15 on WeebCentral are two entries for one Work, and "Continue" must choose. Re-keying would
have forced an answer up front; that answer would also have been a guess, and this keeps the guess
out of persisted data.

### Merge aliases; it never erases

The losing Work id gets a tombstone redirecting to the winner, and stays resolvable forever. The
redirect is **hidden inside the store's accessor** — deliberately unlike `EntityResolutionStore`
and `TasteProfileStore`, which expose `@Published private(set)` dictionaries directly. There must
be no way to reach a Work without resolving, or the indirection becomes a thing to forget.

Chosen on failure mode, not elegance: under rewrite, a stale Work id — from a screen already open
when a background reconcile merged underneath it (ADR-0004 makes that routine) — resolves to
**nothing**, and a `nil` Work degrades exactly like the bug this whole line of work fixes: no tags,
no engagement weight, invisible to the recommender. Under aliasing it resolves to the right Work.
Cost is two UUIDs per merge, and merges are rare.

### Two tag axes, not one merged set

- **`genres: [QueryableTag]`** — the coarse, **searchable** axis. AniList `genres` and the
  searchable MangaDex tags both land here, matched on normalized name. **This is what drives
  candidate generation.**

  > **Amended 2026-07-25, during slice 2.** This originally read `genres: [String]`. Bare strings
  > discard MangaDex's tag **group** (genre / theme / format / content), which
  > `TasteProfile.groupWeight` still uses to weight genre above theme above format
  > (`TasteProfile.swift:33`) — so shipping strings would have silently flattened the existing
  > recommender for every MangaDex-sourced Work. The element is therefore
  > `QueryableTag { name: String, group: String? }`, with `group == nil` for AniList genres, which
  > are all genre-level anyway. The axis distinction the decision rests on is unchanged.
- **`tags: [(name, rank: Int?)]`** — the fine, **ranked, unsearchable** axis. AniList's 425 with
  their 0–100 rank; MangaDex tags land here too with `rank == nil`. Used for **scoring and
  re-ranking candidates already retrieved.**

Adopting AniList's ranked vocabulary as *the* tag set would have been a **silent regression**.
`TagCandidateProvider` turns top tags into `mangaByTag(tag: name)` calls
(`CandidateProvider.swift:37-49`), `MangaSource.mangaByTag` takes a *display name*
(`MangaSource.swift:33-35`), and a failing feed is swallowed by `try?`. Weighting `Dungeon` and
`Male Protagonist` highest would have produced empty feeds and a thinner rail — from strictly
better evidence. `Dungeon: 95` is excellent for judging two retrieved candidates and useless as a
search key.

This also gives `TasteProfile.groupWeight`'s genre/theme/format heuristic (`TasteProfile.swift:33`)
a principled successor **on the ranked axis only**, leaving generation untouched — so the change is
one the golden file can adjudicate as a diff.

**Accepted fuzziness:** MangaDex's `theme` group (38 of 77) is genuinely both searchable and
fine-grained. All searchable MangaDex tags go on the `genres` axis; "genre" is then a slight
misnomer, preferred over pushing the distinction into two booleans on every element.

### One metadata snapshot from one authority, with a provisional tier

A Work's genres, ranked tags, `status` and `chapters` come from **one** provider, stamped with
which one and when — never merged field-by-field. External ids are the exception: they
**accumulate and are never replaced** (that is the point of AniList's `idMal`).

1. A Work minted from a MangaDex read gets a **provisional snapshot** immediately: MangaDex's tags
   on the `genres` axis, ranked axis empty. Free — those tags arrive with the detail fetch the UI
   already makes (`MangaDetailView.swift:56`) — so the recommender works from launch.
2. An AniList fetch **replaces the snapshot wholesale**, only when its `genres` axis is non-empty.

Per-field merging was rejected on debuggability: with no labeled relevance data, the golden diff is
the only evidence a ranking change did what was intended, so the number of things that can vary
must stay small. "Which provider is this Work on, and when was it fetched?" is two printable
values; "which provider contributed the tag that caused this?" is a per-field investigation.

**Revisit trigger:** if the non-empty-genres guard grows into a third such rule, per-field
provenance was right after all.

### Upgrade queue: one owner of the AniList budget

A **single serial queue** turns provisional snapshots into provider ones. It reuses
`scheduleBackfill`'s shape (`RecommendationEngine.swift:149-166`) — batch on rail build, per-item
failures swallowed, never blocks — with three changes: ordered by **engagement weight descending**
rather than dictionary order, batch of **5**, and ~2s spacing (5 × 2s = 10s of a 60s window,
leaving headroom for a user-initiated detail-page fetch to jump the queue).

**Snapshot TTL is derived from publication status, not a guessed constant.** `FINISHED` snapshots
are terminal and never expire — the chapter total will not change again. `RELEASING` snapshots are
*known-incomplete* (`chapters` is `null` by definition — the fact ADR-0004 rests on) and re-check
on ~14 days, mirroring `EntityResolutionStore`'s miss TTL (`EntityResolutionStore.swift:61`).

**Consequence, and it is a real constraint:** this is the app's first rate-limited resource and the
budget is global. **The AniList client must not be callable from view models — only through the
queue.** That is the opposite of how `MangaDexAPI`'s statics are used everywhere today.

### Minting: user commitment only, synchronous and network-free — amends ADR-0002

**Mints a Work:** read, save to library, *Not interested*, *More like this*, manual link override.
**Does not mint:** browsing, searching, appearing in a candidate pool, appearing on Home.

This **strikes "or recommended" from ADR-0002's** "Works are created only on resolution — something
read, saved, or recommended". That clause breaks the sizing argument the JSON-file decision rests
on: pools are `poolLimit = 40` per rail refresh (`RecommendationEngine.swift:38`), so minting per
candidate grows the store with *browsing*, not usage — the "tens of thousands" case ADR-0002
rejected SwiftData as unnecessary for. The recommender never needs it: its exclusion set is
read ∪ saved ∪ not-interested, which is exactly the mint list.

Including the two feedback taps is a bug fix, not scope creep — under Listing-keyed edges,
*Not interested* on a MangaDex Listing would not suppress the same manga surfaced from WeebCentral;
minting on that tap is what makes suppression cross-source.

Minting is **synchronous, local, network-free** — built from the Listing alone. It sits on the path
where the user just opened a chapter: it cannot block the reader and must work offline. A Listing
already carrying `malId` (MangaDex's `attributes.links.mal`) dedupes through the index with no
request.

**Accepted cost:** a WeebCentral-minted Work has no external id and no tags at mint time. Cross-source
invisibility is fixed **asynchronously** — that read counts once the upgrade queue reaches it and
the title matches, which may be minutes later or (if `MALTitleMatcher` declines) never, until the
user manually links it. Strictly better than today's structural *never*, but "why isn't this in For
You yet" has a timing-dependent answer.

### Identity and counts are separate stores

The Work store holds identity — Work id, external ids, snapshot, titles, aliases, and Listings as
bare `(sourceId, mangaId)` references. A **separate, evictable count cache** holds
`(sourceId, mangaId) → (englishChapterCount, fetchedAt)` for ADR-0004's routing.

Storing counts inline would have reproduced the exact I/O pattern ADR-0002 rejected UserDefaults
for — *"every mutation re-encodes and rewrites the whole dataset"* — because count refreshes are
the hottest write in the system (N sources per Work, 24h TTL, across library and history) and Work
identity is among the coldest.

The general test, worth reusing for routing history and reliability priors later: **can you delete
this file and lose nothing but time?** Counts, yes — worst case is one MangaDex-first default route
until refresh, which is ADR-0004's documented cold path. Works, no — you would lose manual links
and orphan the recommender. Data with different answers must not share a file. It follows that the
count cache belongs in `Caches/` (OS-evictable, correctly) and the Work store in Application
Support (never evicted).

**Hazard:** a missing count entry means **unknown**, never zero. Defaulting it to `0` anywhere
silently ranks that source last.

### Titles: sticky display title, accumulating known titles

- **`displayTitle`** — the Listing title the Work was minted from. Set once, **never overwritten by
  a provider**.
- **`knownTitles: [String]`** — every title the Work has been known by: each linked Listing's
  mint-time title plus the provider's romaji / english / native / synonyms. Accumulates like
  external ids.

AniList's canonical title is often romaji, so a snapshot-derived display title would rename *Attack
on Titan* to *Shingeki no Kyojin* as a **delayed side effect of a background fetch** — with no user
action, unexplainable, and indistinguishable from a bug. Stickiness beats correctness here because
the user's entry point is the name they know it by.

`knownTitles` pays off three ways: matching improves monotonically as Listings link, with no rate
limit spent re-fetching titles; `MALTitleMatcher` gets a richer left-hand side than today's single
`Manga.title`, raising recall **without touching the precision threshold ADR-0005 says never to
loosen**; and the manual-link UI can show "known as X, Y, Z — none matched", which tells the user
what to search for.

On merge the surviving Work keeps its `displayTitle`; the loser's joins `knownTitles`. Arbitrary,
but stable — and stability is the property that matters.

**Accepted cost:** a junk scraped title (`Solo Leveling (Official)`) is frozen in. Mitigated by
ADR-0005's unlink path, and preferred over a title that changes on its own: visible junk is a bug
report with an obvious fix.
