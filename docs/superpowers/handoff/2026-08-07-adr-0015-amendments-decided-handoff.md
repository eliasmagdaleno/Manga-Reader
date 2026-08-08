# Session Handoff — 2026-08-07: ADR-0015 grilled, four amendments decided, still no code

**Audience:** the next session. Supersedes `2026-08-05-adr-0015-decided-handoff.md` for **state**;
its *gotchas* and *open items* sections still apply verbatim and are not repeated here.

**Work in flight:** branch `foryou-rail-state`, one commit (the ADR), **still ADR only — no code,
and the ADR does not yet carry the amendments below.**

## State

| | |
|---|---|
| `main` | **`16c10cf`** — unchanged since 2026-08-05 |
| Checked out | `foryou-rail-state` at `f61c1cd`, two commits ahead of `main`, clean |
| Tests | 426 pass / 1 skipped on `main` — not re-run this session, nothing was built |
| ADR-0015 | `docs/adr/0015-accounting-for-an-absent-for-you-rail.md`, Accepted, **four decisions now known wrong** |

## What this session did

Nothing was implemented. The ADR-0015 implementation plan was grilled against the code it
describes, and **four of its decisions rest on facts that were never verified.** All four are
decided and approved; none are written down yet. That is the whole delta.

The pattern is worth naming because it is the second session in a row to hit it: ADR-0015 was
written with the code open but not *read at the call sites it commits to*. The previous session's
correction (a fixture that stubs a dependency is a promise it does not execute that dependency)
and these four are the same error in different clothes — a claim about current behaviour that was
recalled rather than checked.

## The four amendments — approved, unwritten

**1. `TagBlocked` takes a `Work`, not a `WorkID`.**

ADR-0015 specifies `typealias TagBlocked = (WorkID) -> Bool`. `UpgradeAttemptMemory.suppresses` takes
a whole `Work` (`UpgradeAttemptMemory.swift:85`), and its doc comment says why: *"so a caller cannot
pair the wrong count with the wrong id."* The `.unmatched(knownTitlesCount:)` branch compares
`work.knownTitles.count` against the recorded count — that comparison is what unblocks a Work when a
new title synonym arrives, and a `WorkID`-keyed closure cannot carry it. Wiring the ADR as written
would put a `workStore.work(id)` lookup at the composition root, re-creating exactly the mispairing
that signature prevents.

The engine already requires `workStore` (`RecommendationEngine.swift:44-46`), so "keep the engine
ignorant of `Work`" was never a property worth protecting.

**2. `UpgradeAttemptMemory` hoists to the composition root.**

It is not reachable today, at all. `Manga_ReaderApp.swift:54` constructs
`MetadataUpgradeQueue(works:anilist:rateLimiter:)` with no `memory:` argument, so the queue builds its
own via `memory ?? UpgradeAttemptMemory()` (`MetadataUpgradeQueue.swift:69`) and holds it `private let`
(`:47`).

Fix: `let mem = UpgradeAttemptMemory()` at the root, passed as `memory: mem` and captured by the
closure. **The argument for this is already written twelve lines above the call site** —
`Manga_ReaderApp.swift:47-53` hoists `AniListRateLimiter` because "one owner … is only true by
construction if every caller is handed the same instance." Same claim shape: two consumers must see
the same attempt records or the notice contradicts the drain.

*Rejected: exposing the memory through the queue.* Even read-only, that routes the question through
the object ADR-0010 says the engine must not inspect — the coupling the closure form exists to avoid.

**3. The ceiling test replaces the universal quantifier.**

ADR-0015 defines `noTaggableSignal` as "enough read Works to clear the threshold if tagged, and
**every** untagged one currently blocked." Transient failures record nothing, deliberately and
documented (`UpgradeAttemptMemory.swift:100-102`). So a Work that fails transiently on every drain
pass is untagged and never blocked, **permanently** — and under a universal quantifier that single
Work suppresses the notice forever, by the one route no test catches, because nothing is wrong.

Replace with:

```
noTaggableSignal  ⟺  taggedMangaCount + (untagged, not blocked).count < minTaggedManga
```

"Even if every Work still in play got tagged, the gate cannot open." It subsumes the ADR's separate
"enough read Works if tagged" clause, and it is monotone: a Work getting tagged, or a TTL expiring,
can only move the state back toward silence, never falsely toward the notice.

It does **not** fix the one-transient-Work case when two tagged Works already exist (2 + 1 ≥ 3, so
the gate could still open and silence is correct). What it fixes is every case where the arithmetic
already says no and the quantifier cannot see it — e.g. 1 tagged, 5 blocked, 1 pending.

**4. The approved copy's last clause is false. "Reading", not "adding".**

> …but ~~adding~~ **reading** a title from MangaDex will.

`taggedCount` increments only inside `for signal in signals where !signal.entries.isEmpty`
(`TasteProfile.swift:93, 115-116`); `libraryItems` reaches `makeSeeds` alone (`:129`) and never
touches the count. **Saving a MangaDex title does not open the gate.** The reader does the one thing
the notice tells them to and observes no change — worse than the silence, because the app has now
made a promise and broken it.

*Rejected: making saving count.* A saved title has no entries and no engagement weight, so it would
clear `taggedMangaCount` and then die on `!profile.isEmpty` — the exact failure ADR-0015's first
decision rejects.

## Verified sound, do not re-derive

Checked live 2026-08-07 against `foryou-rail-state` (identical to `main` outside `docs/`). The rest
of the 2026-08-05 checklist stands:

- `RailState`'s four cases, and the argument for carrying two that render nothing.
- Assignment points: before `rebuild()`'s `Task.isCancelled` check (`RecommendationEngine.swift:122`)
  and on `load()`'s `loadedOnce` short-circuit (`:87-92`). Both confirmed present as described.
- `profileAndExclusions()` has exactly two callers, `:120` and `:131`; the grid ignores the state.
- `HomeView.swift:42` renders the rail only on `!engine.recommendations.isEmpty`, with no other
  branch. Confirmed.
- `PriorityPush` (`RecommendationEngine.swift:36`) is the shape to copy for the defaulted closure —
  `{ _ in false }`, so no existing construction site changes.
- `resolveSignals()` returns `WorkSignal(workId:entries:tags:)` (`:188-191`), so "untagged" is
  `signal.tags.isEmpty` and the `Work` is one `workStore.work(id)` away. **It is called inline inside
  `TasteProfile.build(signals:…)` and needs binding to a local** before the ceiling test can reuse it.
- `makeEngine` at `Manga_ReaderTests.swift:1662` — use it, don't build a second harness.

## Next

1. **Amend ADR-0015 in place** with all four, `Amends:` header updated to note it amends itself,
   dated 2026-08-07. Say plainly that each was decided against an unverified fact — the ADR's value
   is the record of what beat what, and "this was decided without checking the signature" is part of
   that record.
2. **Then the three commits from the 2026-08-05 handoff, unchanged in shape:** engine (tests first),
   view, composition root. One PR, no stacking.

## Gotchas

All of the 2026-08-05 list still applies — the `.agy_review_running` lock, `xcp`'s vanishing
reformat, phantom SourceKit errors on newly added files, `@MainActor` fixtures crossing into
`@Sendable` child tasks, and `gh pr checks` hanging past the tool timeout.

Nothing was built or committed this session, so none of them were exercised.
