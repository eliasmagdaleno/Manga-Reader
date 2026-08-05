# ADR-0015 — Accounting for an absent "For You" rail

- **Status:** Accepted (2026-08-05)
- **Amends:** ADR-0010 — its "the engine pushes, the queue never pulls" seam, which this narrows
  from *no coupling* to *no control*: a read-only predicate is now permitted, through a closure
- **Related:** ADR-0011 (records this as a hazard and defers it), ADR-0007 / ADR-0009 (the Work
  model that decides what "tagged" means), ADR-0012 / ADR-0013 (the precedent for modelling a
  failure as state rather than a string), ADR-0005 (manual link — the richer fix, not taken here)

## Context

**Facts verified live 2026-08-05 against `main` at `16c10cf`. Do not re-derive.**

- The rail's gate is `profile.taggedMangaCount >= minTaggedManga, !profile.isEmpty`
  (`RecommendationEngine.swift:151`), with `minTaggedManga = 3` (`:52`). Below it,
  `profileAndExclusions()` returns `nil` and `rebuild()` sets `recommendations = []`.
- `taggedMangaCount` increments **only** for a Work with non-empty tags — `guard
  !signal.tags.isEmpty else { continue }` sits directly above `taggedCount += 1`
  (`TasteProfile.swift:115-116`).
- An untagged Work still contributes engagement weight (`TasteProfile.swift:110`). **It looks like
  signal and counts as none.**
- A Work reaches the count by exactly two routes: a MAL match, or a Listing carrying its own tags
  (`WorkStore.swift:157`). A source supplying neither tags nor a resolvable external id has
  **neither** — an opaque numeric id matches nothing on MAL, and there are no Listing tags to build
  a provisional snapshot from.
- `HomeView.swift:42` renders the rail only when `recommendations` is non-empty. There is no other
  branch: no message, no placeholder, nothing.
- `UpgradeAttemptMemory` already records *why* a Work is still provisional —
  `.unmatched(knownTitlesCount:)` (`:25`) and `.absentFromProvider(malId:)` (`:33`) — and
  `suppresses(_:now:)` (`:83-97`) answers "does the queue already know the answer", bounded by a
  14-day TTL (`:46`).
- `profileAndExclusions()` has two callers, the rail and the See-all grid
  (`RecommendationEngine.swift:120, 131`), and returns `nil` for two structurally different
  situations without distinguishing them.

**Observed live 2026-08-04** (recorded at `docs/adr/0011-ranked-axis-generation.md:780`): a store of
5 Works, 3 of them untaggable by both routes and all 3 recorded `unmatched`, sat permanently at
`taggedMangaCount == 2`. Reading more from such a source moves the number by zero, forever, with no
error and nothing in the UI to explain it. ADR-0011 declined to fix it there — correctly, since it is
not a property of the ranked axis — and named ADR-0007/ADR-0009 as the owner.

**This ADR relocates the problem rather than accepting that hand-off.** The Work model is not wrong:
see the first decision below.

## Decisions

### The gate is right; the silence is the defect

The tempting fix is to loosen `minTaggedManga`, or to count untagged Works. **Both fail one line
later, and the failure is instructive.** An untagged Work contributes no tags, so a profile built
from nothing but untaggable Works has an empty weight vector — it would clear a loosened
`taggedMangaCount` check and then die on `!profile.isEmpty` at the same `guard`. Force past that too,
and all three pools have nothing to work with: `TagCandidateProvider` queries by tag,
`MALCandidateProvider` needs resolvable seeds, `AniListCandidateProvider` needs seeded tag pairs.
Every one returns empty.

So a reader whose library is genuinely untaggable **cannot be recommended from**. That is an honest
absence of signal, not a threshold set too high. What the app gets wrong is rendering that absence as
*nothing at all*, which is indistinguishable from a bug and — worse — invites the one inference that
is guaranteed useless.

**The target is legibility, not reachability.** Nothing in this ADR changes who gets recommendations;
it changes who is told why they don't.

**Rejected: a third tagging route** (resolve untaggable Works by title against MangaDex, or surface
ADR-0005's manual link here). Genuinely useful, and probably a later ADR — but it is a feature, it
cannot help a title that is not in any catalogue we query, and it would leave the silence in place
for everyone it fails. A fix that only works when it works is not a fix for a legibility problem.

**Rejected: counting Works the queue could *still* tag**, so the gate opens once the drain completes.
This is arguably the more honest count, but it opens the gate on a promise, and the reader whose
queue can never succeed lands back in the same silence by a longer route.

### Absence is modelled state on the engine, not an empty array

`RecommendationEngine` gains a published `RailState`:

```swift
enum RailState {
    case building                                    // load() in flight, nothing decided
    case needMoreReading(tagged: Int, needed: Int)
    case noTaggableSignal                            // enough reading, nothing identifiable
    case ready
}
```

The engine is the only place that can compute this honestly — it owns the threshold and the `nil`
return. Making the view derive it from history and Work counts would duplicate `minTaggedManga` and
the definition of "tagged" in a second place, and they would drift the first time the gate is tuned.
It is also precisely how the 2026-08-04 device check went wrong: reading a downstream absence and
inferring an upstream cause.

**Rejected: an `errorMessage` string**, which is this codebase's stated convention for view models
(`CLAUDE.md`: "errors surface as `errorMessage` strings, never thrown past the view model"). Broken
with deliberately, on ADR-0012/ADR-0013's precedent: the reader's failure states became types because
they differ in *what the user can do about them*, and a string cannot be branched on. The same holds
here — `needMoreReading` resolves itself with time and `noTaggableSignal` never will. Also, none of
these are errors: the app is working correctly and has nothing to recommend.

### Only the dead end gets UI; cold start stays silent

| State | Renders |
|---|---|
| `building` | nothing |
| `needMoreReading` | nothing — unchanged from today |
| `noTaggableSignal` | an explanatory notice in the rail's slot |
| `ready` | the rail, unchanged |

`HomeView.swift:41` already describes the rail as "hidden until there's enough reading signal", and
that is right. A first-launch reader who has read one chapter does not need "2 of 3 tagged manga":
it leaks the recommender's internals and reads as a progress bar for a feature they never asked for.
The defect is not that cold start is silent — it is that a **permanent dead end is indistinguishable
from cold start**. Only the dead end needs words.

The copy:

> **For You needs titles we can identify.** The manga in your history come from sources we can't
> match to a catalog, so there's nothing to base recommendations on yet. Reading more from these
> sources won't change that — but adding a title from MangaDex will.

The last clause is the reason this ADR exists. "Keep reading" is what an empty rail implies and it
is a **lie in exactly this case**; naming an action that actually works is the whole user-visible
payoff. Naming MangaDex in product copy was considered and kept: a source name the reader can act on
beats a generic phrase they cannot.

**Accepted cost:** two of the four states render nothing today. They are carried for diagnosis, not
speculation — the 2026-08-04 device check burned a full cycle on an empty rail and reached two wrong
hypotheses before finding this gate closed upstream. A published state naming which gate is shut, and
with what numbers, turns that investigation into a glance. A three-case enum collapsing `building`
and `needMoreReading` would render identically and was rejected only on that evidence.

### The queue is asked through a read-only closure

`RecommendationEngine` gains `typealias TagBlocked = (WorkID) -> Bool` — "the queue holds an
unexpired failure for this Work" — defaulted to `{ _ in false }`, wired at the composition root to
`UpgradeAttemptMemory.suppresses`. `noTaggableSignal` means: enough read Works to clear the threshold
*if they were tagged*, and every untagged one is currently blocked.

**This narrows ADR-0010, and the tension is real rather than resolved.** That ADR's seam is that the
dependency runs one way — the engine pushes a dictionary and "must not be able to start, stop, or
inspect the queue" (`RecommendationEngine.swift:34-36`). A closure prevents the *type* coupling but
not the *semantic* one: this is still the recommender asking the queue a question. What survives is
the property that carried the weight — the recommender cannot **act** on the queue, cannot change its
pace or contents, and the queue remains unaware anyone is asking. The rule is therefore restated as
**no control**, not **no coupling**.

The closure form (rather than a direct `UpgradeAttemptMemory` reference) is what keeps that honest,
and it is the seam this subsystem already chose twice: `PriorityPush` (ADR-0010) and
`MALEntityResolver.Search`. A direct reference would put `Services/` types and an Application
Support writer into the engine's test surface for the sake of one `Bool`.

**Rejected: deciding from the `WorkStore` alone.** No new dependency, and arguably the right home
given ADR-0011 assigns the hazard to the Work model. But "resolvable" is a *matcher outcome*, not a
stored fact: the store cannot tell a MangaDex title nobody has looked up yet from an opaque numeric
id that will never match. Only the attempt memory knows, because only it has tried.

**Rejected: collapsing the distinction** — one "keep reading to unlock For You" message for every
closed gate. Cheapest, no ADR tension, and it discards the entire point by telling the untaggable
reader to do the one thing that provably cannot work.

### `profileAndExclusions()` returns the reason instead of `nil`

The reason is computed where it is already known. `profileAndExclusions()` returns a `RailState` on
refusal rather than `nil`; `rebuild()` publishes it; `rankedRecommendations()` ignores it and still
returns `[]`, since the grid is only reachable from a rail that is already rendering.

**Rejected: computing `railState` separately in `rebuild()`** beside the existing `nil` check. The
gate would then exist twice and the two copies could disagree after a tuning change — the same drift
argued against for the view, and no more acceptable inside the engine. One function already knows why
it is refusing; the bug is that it throws that knowledge away, which is the original defect
reproduced one layer down.

`railState` is assigned **before** `rebuild()`'s `Task.isCancelled` check (`:122`) and on `load()`'s
`loadedOnce` short-circuit (`:87-92`), or a cancelled rebuild strands the UI on a stale explanation.

## Hazards

- **`noTaggableSignal` is a claim about *now*, not forever.** `UpgradeAttemptMemory` is TTL-bounded
  at 14 days (`:46`), and `.unmatched` is fingerprinted on title count, so a Listing link or a
  provider adding synonyms reopens it immediately. The copy must never promise permanence — "we
  can't identify these titles", not "we never will". If the wording is ever tightened, this is the
  constraint it must respect.
- **The state is only as honest as the queue's memory.** A Work the drain has not reached yet is
  untagged and *not* blocked, so a reader mid-drain shows `needMoreReading` and sees nothing. That is
  correct but time-dependent: the same reader may see the notice appear minutes later. Nothing
  refreshes the rail on drain completion, so the transition is observed on the next rail build.
- **A mixed library can hide the problem.** Three taggable Works alongside twenty untaggable ones
  clears the gate and renders a rail built from an eighth of the reader's actual taste. This ADR does
  not address that: the rail is present, so the failure is no longer silent, merely thin. Recorded
  because "the gate opened" is not the same claim as "the recommendations are good".
- **The notice names MangaDex.** If the source lineup ever changes — a source removed, or MangaDex
  demoted from the default browse source — this copy becomes wrong in a place no test will catch.

## Revisit triggers

- **If a third tagging route lands** (title-based MangaDex resolution, or ADR-0005's manual link
  surfaced from this notice), the copy's final clause is the thing to rewrite, and `noTaggableSignal`
  stops being a dead end and becomes an actionable state. That is the point to reconsider whether it
  deserves a button rather than a sentence.
- **If `needMoreReading` is ever rendered**, revisit the decision above rather than adding UI to it
  silently — the argument for silence is about a first-launch reader, and it stops applying if For
  You ever becomes something the app advertises before it can deliver it.
- **If a second consumer needs to ask the queue a read-only question**, the `TagBlocked` closure
  stops being an exception and becomes a pattern — at which point ADR-0010's seam should be
  rewritten around a named read-only capability rather than amended a second time.
- **If the mixed-library hazard is ever reported as bad recommendations** rather than absent ones,
  the gate itself is what to reopen: `taggedMangaCount >= 3` measures whether a profile can be built,
  never whether it is representative.
