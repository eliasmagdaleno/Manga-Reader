# Session Handoff — 2026-08-04 (evening): the device check passed; the branch is PR-ready

**Audience:** the next session. Supersedes `2026-08-04-device-check-blocked-handoff.md` **entirely**
— that file's central claim (the check failed, cause unknown) is now known to be a **false
negative**, and its "pick up here" list is done. Its agy-hook section is still accurate and still
worth reading. The slice-4 handoff's gotchas and parked items also still stand.

## The blocking item is cleared

Slice 4's device check **passed both runs**. The branch has no known blockers.

## What the previous session's negative actually was

Not a wiring failure. **The engine's cold-start gate was closed**, upstream of everything the check
was looking at.

- `profileAndExclusions()` returns `nil` when `taggedMangaCount < 3`
  (`RecommendationEngine.swift:151`), and `rebuild()` returns on that `nil` **without ever calling
  `makeProvider`**. So below the threshold the AniList provider is never constructed, never queried,
  and its own contributing-Works gate is never reached.
- That single fact produces **both** observables the previous session saw — no For You rail *and* no
  `anilist-pool.json` — which is why they looked like one symptom with a downstream cause.
- The old container held **2** tagged Works, not 3. Three of its five Works came from a source that
  supplies no Listing tags and whose opaque numeric ids resolve to nothing on MAL — all 3 recorded
  `unmatched` in `upgrade-attempts.json`, with no tags to fall back on. Structurally untaggable by
  both routes — see the new ADR-0011 hazard.

**Both of the previous handoff's hypotheses were wrong, and H1 was independently false:**
`.task { engine.load() }` sits on the ScrollView at `HomeView.swift:112`, **outside** the rail's
`if !engine.recommendations.isEmpty` guard at `:42`. `load()` ran fine on every launch. H2 never got
a chance — no network call was ever attempted.

**No instrumented build was needed.** The whole diagnosis came from reading the simulator container
off-disk. The previous handoff's recommendation to build one was written while H1-vs-H2 was live;
that question is now answered and the instrumented build has no reason to exist. Do not build one.

## The check that passed

Simulator: **iPhone 17 Pro `A74B66F8-4CA3-4E9D-A47B-0F0AB69F3ED4`**, container
`F2EA12E4-5F92-4D01-A7D6-DCE052987EB0`, binary built 15:53 from `4c0d45a`. Note this is **not** the
device the previous two handoffs name — the UDID has now changed twice. Always re-discover it.

**Pre-flight** (throwaway script, scratchpad, deliberately not committed): read `works.json` and the
prefs plist, count distinct Works reachable from `history.entries` whose snapshot carries non-empty
genres, assert `>= 3`. Result: 5 of 5 tagged. **This step is the point of the whole session** — an
absent pool cache has a cause upstream of the wiring, so below the threshold a run is *invalid*, not
negative. Reconstruct it from the rule; don't go looking for the file.

- **Run 1 passed unattended.** A container empty at 15:57 held a full pool by 16:21, produced by
  ordinary reading with no scripted run: 5 seed pairs (`Adoption×Aliens`, `Adoption×Found Family`,
  `Aliens×Found Family`, `Conspiracy×Gangs`, `Cultivation×Super Power`), 12 of 12 head candidates
  reverse-resolved, three of them multi-pair contributors.
- **Run 2 passed.** After `simctl terminate` + `launch`, `anilist-pool.json` held at 16:21:12 /
  14077 bytes across a 60s poll **while the For You rail rendered**. That conjunction is the proof:
  the rail rendering means `rebuild()` → `makeProvider` → `AniListCandidateProvider.candidates` →
  `refreshIfNeeded` all ran, and the file not moving means it found a record. A per-rail-build
  `AniListPoolStore` would have held nothing and refetched. **Actor identity across rebuilds is the
  one claim the composition root makes and the one thing unit tests can't reach.**

**Honest limit:** individual rail cards cannot be attributed to the AniList pool from a screenshot —
the visible reasons are consistent with any of the three pools. That is exactly why the gate is the
cache file and the rail is corroboration only. Do not "strengthen" the check by reading rank order
off a screenshot.

## Landed this session

ADR-0011 amendment (`docs/adr/0011-ranked-axis-generation.md`) + one glossary term:

- **`## Context`** — a new *verified live 2026-08-04, do not re-derive* block: the engine gate
  preceding provider construction; `taggedMangaCount` counting **history-reachable** Works only (a
  saved-but-never-read tagged Work does not count); the two independent tag routes and that a Work
  can miss both; the discharged wiring proof; the unattended cold path.
- **`## Hazards`** — new entry: a reader whose history is dominated by an untaggable source can
  never open the engine's gate, no matter how much they read. Explicitly distinguished from the
  WeebCentral hazard, which is about *this ADR's* provider-level gate; this one is upstream and
  darkens all three pools.
- **Wiring hazard** — marked discharged, but left standing as written for future
  `Manga_ReaderApp.init` changes, now carrying the precondition requirement.
- **`docs/glossary.md`** — new term **Tagged Work**.

## Parked, by decision — do not reopen on this branch

- **The untaggable-source gate problem.** Real, recorded as a hazard, belongs to the Work model
  (ADR-0007/ADR-0009), not the ranked axis. Fixing it here would be fixing it in the wrong place.
- **`MALReverseResolver` extraction** — after the merge, as previously decided.
- **The pre-flight script** — stayed in the scratchpad. A tracked version would hard-code a device
  UDID and container path that go stale (this branch has already lost two UDIDs), and a stale
  tracked script is worse than none because the next session trusts it. The *rule* lives in the ADR
  and here. If it proves useful more than once, promote it to `scripts/` with real device discovery,
  as its own change on `main`.

## Minor, unchased

- `source.activeID` was `"b"` in the old container — matches no registered source, so
  `SourceRegistry.swift:38` falls back to `sources[0]`. Harmless. Origin unknown.

## Pick up here

1. Confirm the full unit suite is green (was running in the background at handoff time).
2. **One PR** of the whole branch to `main`. **Do not stack** — the child closes unrecoverably and
   gets no CI.
3. After the merge: the `MALReverseResolver` extraction.

## Gotchas

All of the slice-4 handoff's still apply, plus:

- **The simulator UDID changes between sessions and the containers are not interchangeable.** Two
  handoffs in a row have named a device that no longer exists. Re-discover with
  `xcrun simctl list devices booted`, then `get_app_container <udid> Elias-Magdaleno.Manga-Reader
  data`. The bundle id is **`Elias-Magdaleno.Manga-Reader`** (hyphen, capital E-M) — guessing
  `com.eliasmagdaleno.*` fails.
- **`get_app_container` fails against a shut-down simulator** with a `code=405 … current state:
  Shutdown` error, even though the files are readable at their path. Boot it, or read the path
  directly.
- **Do not "clear state" by uninstalling** — it takes the Works with it, and with no library there
  is nothing to seed from, so the check produces a confident-looking negative that proves nothing.
  Delete `Library/Caches/anilist-pool.json` only.
- **`works.json` saves are debounced.** A read that isn't followed by backgrounding the app may not
  have hit disk when you go looking.
