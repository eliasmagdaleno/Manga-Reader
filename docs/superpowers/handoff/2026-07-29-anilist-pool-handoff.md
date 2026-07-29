# Session Handoff — 2026-07-29: queue verified live, ADR-0011 ready to build

**Audience:** the next session picking up the recommender.

Supersedes `2026-07-28-upgrade-queue-merged-handoff.md`. That file stays as the record of *why*
the queue looks the way it does — its "finding that should drive the next session" section, its
mutation table, and its account of the livelock are not repeated here. Read it if you need the
reasoning; read this one for where things stand.

## State

| | |
|---|---|
| `main` | `9199d0b` — "Refresh the handoff State table after #25 and #27 (#28)" |
| Working tree | branch `queue-logging-and-mal-query-fix` at `0304299`, clean, pushed |
| **PR #29** | **open, both checks green, NOT merged** — merging it is step 1 below |
| Unit tests | **274 pass, 0 failures** (iPhone 17, `-parallel-testing-enabled NO`) — was 270 |
| ADRs | 0007–0011 accepted; **next free number is 0012** |

There is no other in-flight work. Everything ADR-0009 and ADR-0010 specified is shipped and now
**verified against the live APIs**. ADR-0011 is accepted and **not built** — that is the next
body of code.

## Pick up here

### 1. Merge PR #29

`gh pr merge 29 --squash --delete-branch`. It carries the queue's `os.Logger` instrumentation
plus the two fixes for the livelock that logging exposed:

- **MAL's `q` caps at 64 characters** and answers HTTP 400 above it. Bisected live 2026-07-28:
  64 → 200, 65 → 400, and the cap counts **characters, not UTF-8 bytes** (64 multibyte characters
  also returns 200). Truncating on bytes would have cut Japanese titles to a third of the usable
  length. Fixed by `MyAnimeListAPI.searchQuery(for:)` (`MyAnimeListAPI.swift:123`).
- **Non-429 4xx is an *answer*, not an outage.** The queue used to classify every resolver error
  as transient, so three over-long titles recorded nothing, tripped the breaker, and `endPass`
  cleared the skip set — the same three replayed every 60s forever and the fourth eligible Work
  was never reached on any pass. `permanentStatus(of:)` in `MetadataUpgradeQueue.swift` now
  records those as `.unmatched`, whose reopen condition (a new synonym changes the query) is
  exactly right.

Both are covered by tests, including a starvation regression
(`testUnsearchableWorksDoNotStarveTheOnesBehindThem`). All four new tests were confirmed red
before the fix.

**Fix 2 was never exercised live** — fix 1 removed the 400s entirely — so it rests on its unit
tests alone. That is the correct outcome, but it is not the same as having watched it fire.

### 2. Seed the library before building ADR-0011

**This is the actual blocker, and it is not a coding task.** ADR-0011 gates the AniList pool at
**3 AniList-resolved Works** (`0011-ranked-axis-generation.md`, "The pool runs only above 3
AniList-resolved Works"). The live store currently sits at **1 of 3**:

```
Berserk    UPGRADED  anilist=30002  genres=6  ranked=66
…4 unmatched
5 works, 1 resolved to AniList
AniList pool gate (needs 3): FAIL - 2 short
suppressed by attempt memory: 4 (4 unmatched)
```

The other four are doujin titles that genuinely do not exist on MAL — no fix changes that, and
the queue is right to have stopped asking. Build the pool today and it is **silently inert**: the
For You rail renders normally, just without it, so a green test run would prove nothing.

Add two or three mainstream series to the library and relaunch the app before writing pool code.

### 3. Implement ADR-0011

Slice order, smallest verifiable step first:

1. **Tag vocabulary cache** — `category` lives there, never on the `Work` (ADR-0011, "`category`
   lives in a cached tag vocabulary").
2. **Pair seeding** — top 5 co-occurring pairs by `Σ engagement × min(rank_a, rank_b)/100`,
   `minimumTagRank: 60`, excluding `Technical` and `Cast-Main Cast`.
3. **The provider + its read-through cache** — never blocks the rail.
4. **Fold into `CompositeCandidateProvider`** and diff `Manga-ReaderTests/__Goldens__/foryou-ranking.txt`.

Keep step 4 last and alone. ADR-0011 is explicit that recovering MangaDex's free list-endpoint
tags is **separate, unclaimed work** deliberately not bundled, so the golden diff stays
attributable to one cause (`0011-ranked-axis-generation.md:95`).

Two facts found while grilling that should not be re-derived: **`tag_in` is AND, not OR** (a pair
at rank ≥ 80 is frequently empty), and **candidates carry no tags at all**
(`MangaDexAPI.swift:13-22`).

## How to see what the queue is doing

It was invisible until #29; both observables below arrive with that PR.

- **Live**: Console.app, filter
  `subsystem:Elias-Magdaleno.Manga-Reader category:UpgradeQueue`. The line worth watching is
  `upgraded "…" — anilist N, G genres, R ranked tags`. **A non-zero ranked count is the only
  proof the ranked axis arrived** — MangaDex has no rank concept, and provisional snapshots write
  `tags: []`.
- **Durable**: `scripts/queue-status.sh` (moved into the repo this session; it previously lived in
  a session scratchpad and would have been lost). It reads `works.json` and
  `upgrade-attempts.json` from the app's Application Support directory and prints the block quoted
  above.

**Read those two files together.** A queue that has answered everything and a queue that is stuck
both report `0 eligible`. The attempt-memory count is what distinguishes them — and after the
fix, the four `.unmatched` entries are what prove the queue idles because it *has answers*, not
because it is jammed.

The script reports **every** simulator store rather than guessing the newest. It used to guess,
and it misled me: `simctl install` mints a fresh container UUID, so "newest `works.json`" was a
stale store from a different simulator, reported as though it were live.

## Behaviour change live on `main`

The app **starts a background network loop on launch and on every `.active`**, stopping only on
`.background`. Paced by `AniListRateLimiter`, idles immediately when nothing is stale, so a fresh
install does nothing. A device with reading history starts making AniList requests the first time
it is opened. Intended — but it is the first user-visible network behaviour that runs without
anyone tapping anything.

## Gotchas (carried forward, all still true)

- **Do not stack PRs here.** Merging the base with `--delete-branch` **closes** the child, and it
  can then be neither reopened (`Could not open the pull request`) nor retargeted (`Cannot change
  the base branch of a closed pull request`). Cost this session: #26 was lost and had to be
  rebased onto `main` and reopened as #27. Branch from `main` every time.
- **The `agy` post-commit hook runs its own `xcodebuild`** (on *iPhone 17 Pro*, not the iPhone 17
  this repo otherwise standardizes on) and holds the DerivedData lock for 2+ minutes. Any
  concurrent build dies with `accessing build database … database is locked`. The commit returns
  in seconds, so it looks finished long before it is. It also fires **during `git rebase`**, which
  is how a rebase times out and leaves `.git/rebase-merge` behind. Gate follow-up work on
  `until ! pgrep -f "agy --model" >/dev/null; do sleep 15; done`.
- **The UI tests hit live MangaDex and are not in CI.** Treat a single red UI test as no signal:
  re-run it, then check `main` before blaming a branch. The unit suite is the trustworthy gate.
- **SourceKit is unreliable in this repo** — "No such module 'XCTest'", "Cannot find 'Ink' in
  scope" on files that compile fine. Judge only by `xcodebuild`.

## Still-open threads (older, none blocking)

- Decode MangaDex's free list-endpoint tags (`MangaDexAPI.swift:13-22`) — see ADR-0011's revisit
  trigger; do it *after* the AniList pool lands, not with it.
- Extend More Like This reverse-resolution beyond MangaDex-only.
- Add `malId` to `LibraryItem` so saved seeds skip the title search.
- `MyAnimeListMangaDetail` does not decode `alternative_titles` — widen only if a need appears.
