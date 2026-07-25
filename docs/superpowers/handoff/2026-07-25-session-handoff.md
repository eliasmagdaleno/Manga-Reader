# Session Handoff — 2026-07-25

**Audience:** a fresh session picking up this project. Self-contained — you shouldn't need the
prior chat.

## TL;DR

This session was a **design grilling** that produced five ADRs and a glossary, plus two code
changes to the recommender. The big outcome is not code: it's that the project's next phase —
**cross-source recommendations via a local Work store, with user-installable source
extensions** — is now fully specified in `docs/adr/`, with the load-bearing assumptions verified
against live APIs rather than assumed.

`main` is at `61d852a`. **Two PRs are open and were both green-or-pending at handoff time.**
There is uncommitted duplicate work in the working tree — see "Working tree" below before you
run anything.

## Open PRs

| PR | Branch | Contents | State at handoff |
|---|---|---|---|
| [#10](https://github.com/eliasmagdaleno/Manga-Reader/pull/10) | `geometric-agreement` | Proportional agreement bonus + sub-provider tie-break | SwiftLint pass, build+tests running |
| [#11](https://github.com/eliasmagdaleno/Manga-Reader/pull/11) | `library-collections` | Multiple library collections | SwiftLint pass, build+tests running |

Both verified locally before pushing: #10 at 172 tests green, #11 at 169 tests green, neither
adding SwiftLint errors.

**PR #11 was written in an earlier session and had been sitting uncommitted.** It was branched
off `main`, built, and tested, but **not reviewed line by line by the session that opened it.**
Read it properly before merging.

## What merged this session

**PR #8 → `main`** (`c3c6a92`, `61d852a`):

- **Golden-file harness** for the For You blend: `Manga-ReaderTests/RecommendationGoldenTests.swift`
  plus `Manga-ReaderTests/__Goldens__/foryou-ranking.txt`. The blend's tuning constants were
  chosen a priori and there is no labeled relevance data for this app, so a ranking change can
  never be *proven* better — the harness makes it **reviewable as a diff** instead.
- **ADR-0001 … ADR-0005** and `docs/glossary.md`.

## The design decisions (read the ADRs, but here's the spine)

The project is inverting from **source-primary** (pick a site, browse it) to **catalog-primary**
(browse manga; the app finds a source that can serve it). That reframing is the reason for
everything below.

- **[ADR-0001](../../adr/0001-work-vs-listing-identity.md)** — a **Work** is the manga itself; a
  **Listing** is one source's copy. Today's `Manga` struct is a Listing. The recommender must
  rank Works.
- **[ADR-0002](../../adr/0002-catalog-authority-and-local-work-store.md)** — a **local Work
  store** owns identity; MAL and AniList are *metadata providers*, not the catalog. Tags live on
  the Work. Persistence is a **JSON file in Application Support**, lazily loaded, debounced
  saves (UserDefaults and SwiftData both rejected, with reasons and a revisit trigger).
- **[ADR-0003](../../adr/0003-extension-substrate.md)** — extensions are **JavaScript**:
  JavaScriptCore for logic, `WKWebView` for fetches that need to be a real browser (Cloudflare).
  One extension kind, two fetch strategies. Ship **zero built-in aggregator sources**. The
  **host API is the real work and is undesigned**.
- **[ADR-0004](../../adr/0004-fulfillment-routing.md)** — route to the Listing with the most
  complete English chapter run; MangaDex breaks ties. Optimistic render, then reconcile.
- **[ADR-0005](../../adr/0005-manual-link-override.md)** — keep the precision-biased matcher, add
  a user-facing manual link override, and **make resolution failures visible**.

### The live bug these fix

`MangaDetailView.swift:56` guards `manga.sourceId == "mangadex"` before recording tags, and
`RecommendationEngine.scheduleBackfill` filters to mangadex. `TasteProfile.build` then skips
untagged manga *before* computing engagement weight (`TasteProfile.swift:59`). Chain it:
**a manga read on WeebCentral gets no tags → no engagement weight → it can neither contribute
tag signal nor become a MAL seed. Non-MangaDex reading is structurally invisible to the
recommender.** ADR-0002's tags-on-the-Work decision is the fix.

## Verified facts (do not re-derive; do not assume otherwise)

Checked live against `https://graphql.anilist.co` on 2026-07-24:

- **`Media.idMal` exists and is populated** — `Solo Leveling` → `id: 105398, idMal: 121496`.
  AniList *bridges* to MAL rather than competing, so everything already keyed on `malId` keeps
  working.
- **AniList covers the manhwa/manhua gap** that motivated moving off MAL-only.
- **AniList tags carry a `rank` (0–100)** — `Dungeon: 95`, … `Marriage: 20`. Real per-title tag
  relevance, strictly better evidence than `TasteProfile.groupWeight`'s coarse
  genre/theme/format heuristic.
- **Ongoing series report `chapters: null`.** One Piece (`status: RELEASING`) → `null`;
  Jujutsu Kaisen (`FINISHED`) → 272. This **disproved** the assumption fulfillment routing was
  going to rest on, and is why ADR-0004 has the "sources define the frontier" fallback.

## Next steps, in order

Ordering is already decided (ADR-0003 "Sequencing") — identity first, extensions last, because
extensions without a Work model just multiply duplicate entries.

1. **AniList GraphQL client.** The best first slice: self-contained, mirrors `MyAnimeListAPI`'s
   request/retry/error shape, touches no existing store, and immediately unlocks ranked tags.
2. **`Work` type + local JSON store** (ADR-0002).
3. **Migrate `EntityResolutionStore`** off its `malId` key onto the Work key.
4. **Move tags onto the Work**, then delete the `sourceId == "mangadex"` guard and the
   mangadex-only backfill filter. *This is the change that makes non-MangaDex reading count.*
5. **Data migration** — `HistoryStore` and `LibraryStore` entries are Listing-keyed today.
   Without back-resolution, history orphans on first launch. Easy to forget, expensive to find.
6. Then ADR-0005 (manual override), ADR-0004 (fulfillment), ADR-0003 (extensions — first task
   there is *porting WeebCentral to the host API*, not designing the API in the abstract).

**Smaller, independently useful:**

- **Retune `agreementBonus`.** After #10, the geometric bonus is always ≤ the flat one it
  replaced, so agreement now carries less total weight than before. One line, readable diff.
- **A recorded-from-real-data golden** as a second fixture — the synthetic one proves mechanics,
  a real one would let you judge *quality*. Caveat: bakes reading history into a public repo.
- **Retire `MyAnimeListDebugView`** — deferred since the More Like This rail proved out.
- **Split `Manga_ReaderTests.swift`** — 2,200+ lines and already tripping SwiftLint's
  `file_length` before any of this session's work.

## Gotchas found this session

- **`xcodebuild` silently drops plain env vars** for simulator tests. Only `TEST_RUNNER_`-prefixed
  vars reach the runner (the prefix is stripped). Regenerate goldens with
  `TEST_RUNNER_REGENERATE_GOLDENS=1`, never a bare `REGENERATE_GOLDENS=1` — the bare form fails
  silently, which looks like the harness not working.
- **Goldens resolve via `#filePath`**, not a bundled resource, because `Manga-ReaderTests` is a
  plain `PBXGroup` (not synchronized) — bundled fixtures would need a resources build phase it
  doesn't have. New test *files* there still need all four manual pbxproj edits.
- **Any new git worktree needs `Secrets.xcconfig`** copied in — it's gitignored but is the app
  target's base config, so the build fails immediately without it. CI writes a placeholder
  (`MAL_CLIENT_ID = ci-placeholder`); unit tests never call MAL.
- **`gh pr merge --delete-branch` auto-closes any PR stacked on that branch**, and GitHub then
  refuses to reopen it (base branch gone) *or* retarget it (PR is closed). Recovery is
  cherry-picking onto the new `main` and opening a fresh PR. This happened to PR #9 → #10.
- **CI only triggers on PRs targeting `main`** (`.github/workflows/ci.yml`), so a stacked PR gets
  no checks at all. Don't stack.
- **macOS runners queued ~1 hour** at one point this session. Jobs showing `queued` with zero
  steps executed are capacity, not failure — don't debug the code.
- **`TagCandidateProvider` / `MALCandidateProvider` had no sort tie-break** (the composite got one
  in `5fb47f9`; the sub-providers were missed). Fixed in PR #10, along with the same defect in
  their reason-string attribution.

## Working tree — read before running anything

The main checkout is on branch **`recommender-geometric-agreement`**, which is **superseded**
(its commit was cherry-picked to `geometric-agreement` for PR #10; the old PR #9 is closed).

The working tree also still holds the **collections changes as uncommitted edits**, even though
that exact work is now committed and pushed on `library-collections` (PR #11). It is duplicated,
not at risk. Once PR #11 is merged and you're satisfied, the cleanup is:

```sh
git checkout main && git pull
git reset --hard origin/main     # ONLY after #11 is merged — discards the duplicate edits
git branch -D recommender-geometric-agreement
```

Stale remote branch `recommender-geometric-agreement` can also be deleted; its only unique
commit lives in `geometric-agreement`.

## Working style notes (carried forward)

- User is a **new-grad dev learning SWE from this project** — teach and give rationale, don't
  just do it ([[user-new-grad-learning]]).
- Prefer **prose discussion at big forks** over AskUserQuestion ([[works-discussion-at-forks]]).
- Always **iPhone 17 + `-parallel-testing-enabled NO`** ([[no-parallel-test-clones]]).
- **Ignore SourceKit "cannot find type" / "No such module XCTest"** — indexer false alarms; judge
  by `xcodebuild` only.
- `main` is branch-protected: branch → PR → both checks green → merge. No direct pushes.
