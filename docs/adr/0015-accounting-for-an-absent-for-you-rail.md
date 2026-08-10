# ADR-0015 — Accounting for an absent "For You" rail

- **Status:** Accepted (2026-08-05), amended 2026-08-07, 2026-08-08, 2026-08-10
- **Amends:** ADR-0010 — its "the engine pushes, the queue never pulls" seam, which this narrows
  from *no coupling* to *no control*: a read-only predicate is now permitted, through a closure.
  **Also amends itself** — see "Amendments (2026-08-07)" below
- **Related:** ADR-0011 (records this as a hazard and defers it), ADR-0007 / ADR-0009 (the Work
  model that decides what "tagged" means), ADR-0012 / ADR-0013 (the precedent for modelling a
  failure as state rather than a string), ADR-0005 (manual link — the richer fix, not taken here)

## Amendments (2026-08-07)

Before any code was written, this ADR's implementation plan was grilled against the code it commits
to. **Four decisions rested on facts that had been recalled rather than checked**, and all four were
wrong. They are corrected in place below; this section records what was wrong and why, because that
is the part a future reader cannot reconstruct from the corrected text.

| # | Decided | Actually true | Corrected in |
|---|---|---|---|
| 1 | `TagBlocked = (WorkID) -> Bool` | `suppresses` takes a whole `Work`, deliberately | "The queue is asked through a read-only closure" |
| 2 | `UpgradeAttemptMemory` can be wired from the root | It is not reachable there at all today | same section |
| 3 | `noTaggableSignal` ⟺ *every* untagged Work blocked | A transient-failure Work is never blocked, so the quantifier never holds | "Only the dead end gets UI" / the definition |
| 4 | Copy: "**adding** a title from MangaDex will" | Saving a title does not move `taggedCount`; only reading does | The copy |
| 5 | `railState` also assigned on `load()`'s `loadedOnce` short-circuit | Nothing correct to assign there; writing would overwrite a decided state | "`profileAndExclusions()` returns the reason" |

Amendment 5 was found during implementation on 2026-08-08, after the first four; it is the same
error again, which is the strongest argument this section makes.

The common shape: this ADR was written with the code open but **not read at the call sites it
commits to**. The failure is worth naming because it recurred — the prior session's correction (a
fixture that stubs a dependency is a promise it does not execute that dependency) is the same error
in different clothes. A claim about current behaviour is not verified until the line asserting it has
been opened.

None of the four changed the ADR's *shape*: the gate stays, the state stays modelled on the engine,
only the dead end gets UI, and the queue is still asked through a closure. What changed is that three
of those would not have compiled or would not have fired, and the fourth would have told the reader
to do something that does not work.

## Amendment 7 (2026-08-10): `ready` carries the rail's basis

Hazard 3 below — "a mixed library can hide the problem" — was recorded as out of scope and is now
in scope. `ready` gains a payload:

```swift
case ready(tagged: Int, of: Int)
```

and `HomeView` renders one line under the rail: **"Based on 8 of 11 titles you've read."**

**Why now.** ADR-0017 (excluding novels from MAL resolution candidates) was accepted on a Python
harness run over twelve hand-picked titles skewed toward Korean webtoons — the population where its
effect is largest, which is the standing caveat on that acceptance. This payload is the same ratio
measured against the reader's real library, in the app, continuously. It is the cheapest available
answer to "did 0017 actually work here", and it needs no harness to survive.

### `of` counts read titles, not the library

The denominator is Works with history entries. **Rejected: read ∪ saved**, i.e. everything on the
Library screen. A saved-but-unread title contributes no entries, so it can never reach `tagged` —
amendment 4 above establishes this and had to correct the copy for the same reason. Counting it in
`of` would make the ratio permanently less than 1 for any reader with a backlog, reporting *having a
to-read list* as a recommender failure. Numerator and denominator must be drawn from one population
or the sentence is not about anything.

### `of` counts Works, not Listings

Per ADR-0001, one series read on two sources is one Work and two Listings, and it contributes one
taste signal. The count follows the signal. **This reads as an off-by-one to anyone who remembers
reading it on both sources**, and is recorded here so a future reader recognises it as a decision
rather than filing it. The alternative — counting Listings — would inflate the denominator with
duplicates the recommender never treated as separate, understating the basis it actually used.

### Hidden at parity

`tagged == of` renders nothing. **Rejected: always showing it**, including the healthy "11 of 11".
A line that renders unconditionally becomes wallpaper within a day and stops being read, which
destroys the diagnostic value it exists for. The accepted consequence is stated plainly because it
cuts against the motivation above: **if ADR-0017 worked as measured, this line may never appear on
the author's library.** Its absence is then the result, not a failure to observe one.

### The payload rides on the state

`profileAndExclusions()` returns `.ready(TasteProfile, Set<String>, RailState)` — the state fully
formed, not just the numbers. Same argument the "returns the reason instead of `nil`" decision makes
below: the basis is computed from the same `signals` array the gate is applied to, and recomputing it
in `rebuild()` would need that array published or rebuilt, putting the definition of the population
in a second place that drifts. **Rejected: a second `@Published` property** beside `railState`, which
is that second place with extra steps.

### One claim in the implementation is untestable, by construction

The denominator is written `signals.filter { !$0.entries.isEmpty }.count`, mirroring the filter
`TasteProfile.build` counts under. **Mutation-checked: replacing it with `signals.count` fails no
test, and cannot** — `resolveSignals()` derives every signal from a history entry, so the predicate
is always true. It is kept as the written form of an alignment that would otherwise be an
undocumented coincidence, and recorded here as vacuous rather than presented as verified. The
load-bearing half of the decision *is* covered: adding `savedIds.count` to the denominator turns the
suite red.

## Amendment 8 (2026-08-10): the ceiling test needs a reading precondition

**The defect is real; the story originally written here about how it was found was not. Both are
recorded, because the false one is the ninth instance of this ADR's recurring failure and it was
committed to a file before being checked.**

What was claimed: that the simulator had been observed rendering the dead-end notice on a device
with no reading history at all. What is true: the simulator has **three** read titles, all
WeebCentral placeholders (`Zurnak Vhelli`, `Bramgot no Yeshu`, `Qelparre Drift`), all unmatchable —
so `noTaggableSignal` was **the correct render**, and the screenshot showed the feature working.

The bad inference: the app's `Library/Preferences/…plist` was dumped and had no `history.entries`
key, and **an absent key was read as an absent fact**. It was absent because `cfprefs` had not
flushed it to disk, and because the container inspected was the pre-reinstall one. The live value —
obtained later by printing `history.entries.count` from `rebuild()` — is 3. This is the same error
the 2026-08-07 amendments name: *a claim about current behaviour is not verified until the line
asserting it has been opened.* A `plutil` dump is not that line.

The defect itself was found by reasoning about the predicate and is **proved by test, not by
observation**: `testEmptyHistoryIsColdStartNotADeadEnd` fails on the pre-amendment engine with
exactly `noTaggableSignal` where `needMoreReading(tagged: 0, needed: 3)` belongs. It is a real
first-launch defect that no reader has yet reported, and it is worth fixing on that basis alone —
but it is not what was on the screen.

Amendment 3 replaced

> enough read Works to clear the threshold *if they were tagged*, **and** every untagged one is
> blocked

with the ceiling test alone, on the claim that it "subsumes the original *enough read Works if
tagged* clause." **It does not subsume that clause; it deletes it.** With zero read Works,
`taggedMangaCount + stillInPlay = 0 < 3` and the ceiling test fires — trivially, because tagging
nothing cannot open any gate. The definition is therefore both halves:

```
noTaggableSignal  ⟺  readWorks ≥ minTaggedManga
                  ∧  taggedMangaCount + (untagged, not blocked).count < minTaggedManga
```

This restores what the state's own name asserts — *enough reading*, nothing identifiable — and what
the decision "only the dead end gets UI" depends on. Without it, **cold start and a permanent dead
end render identically, in the dead end's favour**, which is verbatim the defect this ADR was
written to fix. The ADR spent four paragraphs arguing a first-launch reader should see silence and
then shipped them the notice.

**Why amendment 3 missed it.** It was reasoned from the shape of the predicate — is the quantifier
sound? — and the unsound case it was checked against (one perpetually transient Work) was the
interesting one, not the trivial one. **The empty library was never substituted in.** Checking a
definition against its hard case and not its degenerate case is how a guard clause goes missing.

*Rejected: special-casing `signals.isEmpty`.* It fixes the observed screen and leaves the same
defect at one and two read titles, where the ceiling test is equally trivial and equally wrong. The
precondition is the general form and the tests cover both points.

**Consequence for amendment 7's basis line:** none. The line still could not be verified on the
simulator, for the reason the diagnosis above actually establishes: all three read titles are
WeebCentral placeholders that nothing can tag, so the rail never opens and there is nothing for the
line to annotate. Verifying it needs a library with at least three *taggable* read titles — which is
the standing obstacle ADR-0016's Hazard 3 called unsatisfiable, not a property of this amendment.

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
> sources won't change that — but reading a title from MangaDex will.

The last clause is the reason this ADR exists. "Keep reading" is what an empty rail implies and it
is a **lie in exactly this case**; naming an action that actually works is the whole user-visible
payoff. Naming MangaDex in product copy was considered and kept: a source name the reader can act on
beats a generic phrase they cannot.

**Amendment 4 (2026-08-07): "reading", not "adding".** The approved copy originally ended "…but
**adding** a title from MangaDex will," which is false. `taggedCount` increments only inside `for
signal in signals where !signal.entries.isEmpty` (`TasteProfile.swift:93, 115-116`); `libraryItems`
reaches `makeSeeds` alone (`:129`) and never touches the count. **Saving a MangaDex title does not
open the gate.** Shipped as written, the reader does the one thing the notice tells them to and
observes no change — strictly worse than the silence this ADR set out to fix, because the app has now
made a promise and broken it. One word, and it inverted the ADR's entire user-visible payoff.

*Rejected: making saving count.* A saved title has no entries and no engagement weight, so it would
clear `taggedMangaCount` and then die on `!profile.isEmpty` — the exact failure the first decision
above rejects.

**Amendment 6 (2026-08-08, found on the device check):** the notice must not wear the seal wash.
This ADR argued the state is not an error and rejected `errorMessage` on exactly that ground, but the
argument was made about *words* and the first implementation kept `InkNotice`'s `Ink.sealSoft` fill
while dropping only its exclamation icon. Rendered on a device, it still read as an error banner —
inviting the one inference this ADR calls guaranteed useless. The fill carries most of that signal,
so the notice uses `Ink.surfaceAlt` with a hairline border: recessed, neutral, informational. Colour
is part of the claim "this is not an error", not decoration applied after it.

**Accepted cost:** two of the four states render nothing today. They are carried for diagnosis, not
speculation — the 2026-08-04 device check burned a full cycle on an empty rail and reached two wrong
hypotheses before finding this gate closed upstream. A published state naming which gate is shut, and
with what numbers, turns that investigation into a glance. A three-case enum collapsing `building`
and `needMoreReading` would render identically and was rejected only on that evidence.

### The queue is asked through a read-only closure

`RecommendationEngine` gains `typealias TagBlocked = (Work) -> Bool` — "the queue holds an
unexpired failure for this Work" — defaulted to `{ _ in false }`, wired at the composition root to
`UpgradeAttemptMemory.suppresses`.

**Amendment 1 (2026-08-07): the closure takes a `Work`, not a `WorkID`.** As first written this ADR
specified `(WorkID) -> Bool`, on the unchecked assumption that keeping `Work` out of the engine's
vocabulary was worth protecting. It is not, and the narrower type does not work:
`UpgradeAttemptMemory.suppresses` takes a whole `Work` (`UpgradeAttemptMemory.swift:85`) and its doc
comment says why — *"so a caller cannot pair the wrong count with the wrong id."* The
`.unmatched(knownTitlesCount:)` branch compares `work.knownTitles.count` against the recorded count,
and that comparison is exactly what unblocks a Work when a new title synonym arrives. An id-keyed
closure cannot carry it, so wiring it as written would put a `workStore.work(id)` lookup at the
composition root — **re-creating the mispairing that signature exists to prevent**. The engine
already requires `workStore` (`RecommendationEngine.swift:44-46`), so the property being protected
was never held in the first place.

**Amendment 2 (2026-08-07): `UpgradeAttemptMemory` must first be hoisted to the composition root.**
This ADR assumed the memory was available to wire. It is not reachable there at all today:
`Manga_ReaderApp.swift:54` constructs `MetadataUpgradeQueue(works:anilist:rateLimiter:)` with no
`memory:` argument, so the queue builds its own via `memory ?? UpgradeAttemptMemory()`
(`MetadataUpgradeQueue.swift:69`) and holds it `private let` (`:47`). The fix is `let mem =
UpgradeAttemptMemory()` at the root, passed as `memory: mem` and captured by the closure — and **the
argument for it is already written twelve lines above that call site**: `Manga_ReaderApp.swift:47-53`
hoists `AniListRateLimiter` because "one owner … is only true by construction if every caller is
handed the same instance." Identical claim here: two consumers must see the same attempt records, or
the notice contradicts the drain.

*Rejected: exposing the memory through the queue.* Even read-only, that routes the question through
the object ADR-0010 says the engine must not inspect — the coupling the closure form exists to avoid.

### `noTaggableSignal` is a ceiling test, not a universal quantifier

**Amendment 3 (2026-08-07).** As first written, `noTaggableSignal` meant "enough read Works to clear
the threshold *if they were tagged*, and **every** untagged one is currently blocked." The universal
quantifier is unsound: transient failures record nothing, deliberately and documented
(`UpgradeAttemptMemory.swift:100-102`), so a Work that fails transiently on every drain pass is
untagged and **never** blocked, permanently. Under the original definition that single Work suppresses
the notice forever — by the one route no test catches, because nothing is wrong.

The definition is therefore:

```
noTaggableSignal  ⟺  taggedMangaCount + (untagged, not blocked).count < minTaggedManga
```

**Superseded by amendment 8 above — this is the half-definition that shipped the notice to a reader
with an empty history.** Read as: *even if every Work still in play got tagged, the gate cannot
open.* It subsumes the original
"enough read Works if tagged" clause, and it is monotone in the right direction — a Work getting
tagged, or a TTL expiring, can only move the state back toward silence, never falsely toward the
notice.

It does **not** rescue the one-transient-Work case when two tagged Works already exist (2 + 1 ≥ 3, so
the gate could still open and silence is the correct render). What it fixes is every case where the
arithmetic already says no and the quantifier could not see it — 1 tagged, 5 blocked, 1 pending.

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

`railState` is assigned on both paths **before** `rebuild()`'s `Task.isCancelled` check (`:122`) —
including `.ready`, which is published as soon as the gate opens rather than after the pool returns,
or a cancelled rebuild strands the UI on a stale explanation.

**Amendment 5 (2026-08-08, found in implementation):** this ADR also required an assignment on
`load()`'s `loadedOnce` short-circuit (`:87-92`). **There is nothing correct to assign there.** The
short-circuit returns precisely *because* a previous `rebuild()` already decided the state, so
writing to it could only overwrite a decided state with `.building` — reintroducing the stale-UI
failure the rule exists to prevent, in the one place the rule named. `load()` is therefore left
untouched, and `.building` is the initial value only. Recorded rather than quietly dropped because
the original line reads as a checked claim and is not one: like the four before it, it was written
without opening the call site.

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
  **Partly addressed by amendment 7 (2026-08-10)**: the thinness is now reported as "N of M titles
  you've read". The hazard is not closed — the rail is still built from an eighth of the taste, and
  the reader is merely told so.
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
