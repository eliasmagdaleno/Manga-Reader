# ADR-0010 — The drain loop: pass shape, failure handling, testing seams, and wiring

- **Status:** Accepted (2026-07-28); **amended by ADR-0015 (2026-08-05)** — the engine's seam with
  the queue narrows from *no coupling* to *no control*, admitting one read-only predicate
- **Amends:** ADR-0009 (its push site, its order of operations, and its silence on what a pass
  consumes)
- **Related:** ADR-0008 (queue policy), ADR-0007 (Work shape, rate limiter), ADR-0001 (Work vs
  Listing)

## Context

ADR-0009 pinned what the queue is wired to and what it does per Work. It did not say what a single
turn of the loop consumes, what happens when a Work fails in a way that is nobody's answer, or how
any of it is tested without wall-clock sleeps. Two of its decisions also turn out not to survive
contact with `WorkStore`'s actual behaviour: its order of operations assumes the AniList fetch
either succeeds or throws, and assumes the Work it started with still exists when it finishes.

**Facts verified live 2026-07-28 against the tree at `a24fb3c` (do not re-derive):**

- **`apply` does not always write a snapshot.** It writes only when `hasContent || work.snapshot ==
  nil` (`WorkStore.swift:211-212`), where content means a non-empty `genres` *or* `tags`. A Work
  holding a provisional snapshot whose AniList record has neither keeps the provisional one.
- **A provisional snapshot is unconditionally stale.** `isStale` returns `true` for
  `provider == .mangadex` before any TTL arithmetic (`Work.swift:101-104`).
- **A merge deletes the loser and aliases it** (`WorkStore.swift:269-270`), then reindexes the
  winner (`:273`). `work(_:)` follows aliases (`:59-65`) and returns the *survivor's* value, whose
  `id` is the survivor's id.
- **`EntityResolutionStore` reads UserDefaults exactly once, in `init`** (`:67-70`), into an
  in-memory dictionary that `resolution(sourceId:mangaId:)` serves (`:72-74`). It never reloads. The
  detail-page path writes through `.shared` (`:58`), which is `MoreLikeThisProvider`'s default
  (`MoreLikeThisProvider.swift:20`). `MyAnimeListDebugView.swift:138` constructs a fresh instance
  instead.
- **Only `AniListError.notFound` is terminal** (`AniListAPI.swift:23-28`). It is raised both by a
  GraphQL 404 and by a null `Media` (`:172`).
- **Two of the three sleep sources are already injectable.** `AniListRateLimiter.init(minimumInterval:)`
  (`AniListRateLimiter.swift:38`) and a cold limiter never delays its first caller (`:49`);
  `AniListAPI` takes a `Transport` (`:96-102`) and its 429 retry is unreachable behind a stub.
- **`profileAndExclusions()` has two callers** — `rebuild()` (`RecommendationEngine.swift:106`) and
  `rankedRecommendations()` (`:120`) — and gates on `taggedMangaCount` at `:141`.
  `RecommendationEngine` already injects `now: @escaping () -> Date = Date.init` (`:44`, `:64`).
- **The `scenePhase` handler currently has one branch**, `.background → works.flush()`
  (`Manga_ReaderApp.swift:55-60`).

## Decisions

### A pass re-scans before every request

Batch size one. The loop scans, takes the head, spends one request, and scans again.

Draining the whole eligible list under a single ordering was rejected on what happens during the
drain. A fresh install with a few hundred provisional Works is several minutes of continuous
foreground draining, and `mint` runs on **every page turn** (`WorkStore.swift:97`) — the user is
*reading* through that window, and the Work they just opened is the most valuable upgrade in the
store. A whole-list pass cannot see it until the pass ends. Re-scanning also makes a `setPriority`
push take effect at the next request rather than the next pass, which is the entire point of the
push design.

A bounded batch of 5 was rejected because it is a constant nobody measured — it appears in
`AniListRateLimiter.swift:12` as a note written before the pacing decision existed — and because the
scan it saves costs nothing. `allWorkIds()` is a dictionary key copy (`WorkStore.swift:97-100`) plus
a filter and a sort over a few hundred entries, main-actor and in-memory, against a 2-second request
floor. There is no efficiency argument for batching, only an accidental one.

**Accepted cost: the loop depends on the eligibility predicate genuinely flipping.** At batch 1 a
Work that is neither upgraded nor suppressed is re-picked 2 seconds later rather than once per pass,
so every "this can't happen" in the predicate becomes a spin instead of a slow leak. Two such holes
existed and are closed below; this decision is what made them worth finding.

### Transient failures are skipped for the rest of the pass, and three in a row abandon it

ADR-0008 requires that a transient failure record *nothing*, so a throwing Work stays eligible and
sorts back to the same place. The queue keeps an **in-memory skip set** of ids that failed during
the current pass, and a **consecutive-failure counter**; three failures in a row clear both and idle
the loop.

```
loop {
  let eligible = scan().filter { !failedThisPass.contains($0) }        // sorted
  guard let next = eligible.first else { endPass(); continue }         // idle + clear
  do    { try await upgrade(next); consecutiveFailures = 0 }
  catch { failedThisPass.insert(live.id); consecutiveFailures += 1 }
  if consecutiveFailures >= 3 { endPass() }
}
```

This makes forward progress structural rather than hoped-for: every iteration either upgrades a Work
— flipping `isStale` false — or adds one id to the skip set, so the eligible list strictly shrinks
and a pass terminates. That property is what batching would have supplied by accident; here it is
supplied on purpose.

Persisting the transient failure with a short TTL was rejected because `UpgradeAttemptMemory` is
reserved for *semantic* answers by ADR-0008's delete test, and a network blip is not an answer about
a Work. The skip set is also correctly scoped to the pass by being in-memory: cancel-on-background
already gives every foregrounding a clean slate, which is exactly the reopen policy a transient
failure wants.

The breaker exists because the skip set alone handles one bad Work but not a bad *network*: offline,
every Work in the store would fail once at 2-second spacing before the pass ended. Three failures
reaches the same conclusion in about six seconds, without a reachability API, and an isolated failure
never trips it because the next success resets the count.

Two classifications follow, and they are the load-bearing part:

- **`AniListError.notFound` is not a failure.** It is the terminal answer, records
  `.absentFromProvider(malId:)`, and counts as a *success* for the breaker. It is the only
  `AniListError` case that does; `.rateLimited`, `.httpStatus`, `.invalidResponse`, `.graphQL` and
  raw URLSession errors are all transient. `.graphQL` genuinely means *our bug* and would fail
  permanently, but it fails identically on every Work, so the breaker degrades it to one wasted
  request per idle interval rather than one every 2 seconds.
- **`CancellationError` is neither.** `Task.isCancelled` is checked at the top of the loop and after
  the awaited request, before the catch can read a teardown as a failure.

**Accepted cost: 3 is arbitrary.** Unlike ADR-0009's fan-out cap of 3, this one is cheap to be wrong
about in both directions — too low costs a premature idle, too high costs a few doomed requests.

### The loop has one branch; every decision lives in a sleep-free `drainOnce`

```swift
enum DrainStep: Equatable { case upgraded(WorkID), failed(WorkID), idle }

func drainOnce(now: Date) async -> DrainStep      // no sleeps of its own
func run() async {
    while !Task.isCancelled {
        if await drainOnce(now: now()) == .idle { try? await sleep(idleInterval) }
    }
}
```

The skip set and the breaker are queue state read and written *inside* `drainOnce`, so a tripped
breaker returns `.idle` exactly as an empty scan does. That is what buys the single branch: `run` has
no knowledge of why it is idling, and nothing in it is worth testing beyond "it loops, and it stops
when cancelled."

The new injection surface is therefore just `sleep` and `now` — the second matching the precedent
already in `RecommendationEngine.swift:44,64`, and needed regardless to drive `isStale(now:)` and
`suppresses(_:now:)` past their fourteen-day TTLs. The 2-second pacing and the 429 retry need no new
seams at all (see Context).

A `Clock` abstraction was rejected: conforming would drag a generic parameter through the queue's
type to serve one sleep site that never needs to compose. Testing the behaviour *through* the loop
was rejected because it reintroduces exactly the timing dependence the split exists to remove.

**Accepted cost: `drainOnce` is `internal`, not `private`, purely so tests can call it.** The app
calls only `start()`, `stop()` and `flush()`.

### The engine pushes through a closure, from `profileAndExclusions()`

**Amends ADR-0009**, which named `rebuild()` as the push site.

`RecommendationEngine` gains `typealias PriorityPush = ([WorkID: Double]) -> Void` and an init
parameter defaulted to `{ _ in }`. `Manga_ReaderApp.init()` constructs the store, then the queue,
then `RecommendationEngine(..., pushPriority: queue.setPriority)`.

A concrete `MetadataUpgradeQueue` reference on the engine was rejected on test cost: the engine lives
in `Models/` and the queue in `Services/`, and the queue transitively owns `AniListAPI`,
`MALEntityResolver`, `EntityResolutionStore` and an `UpgradeAttemptMemory` that writes to Application
Support — a large standing cost for a one-way handoff of a dictionary. A one-element protocol reads
marginally better at the call site and was rejected only on consistency: the injected-closure seam is
what this subsystem chose one step earlier for the same problem (`MALEntityResolver.Search`,
`MALEntityResolver.swift:21,31-34`). Defaulting to a no-op means no existing construction site or
test changes.

The site moves down to `profileAndExclusions()` because that is where the profile is actually built,
and it has two callers — the rail and the See-all grid (`RecommendationEngine.swift:106,120`). One
call site instead of two, and the grid comes along free. Placement is **after** the gate at `:141`:
below the three-tagged-manga threshold the function returns `nil`, and pushing there would overwrite
a previous session's good ordering with a cold-start blank, which is strictly worse than pushing
nothing.

**Amended 2026-08-05 by ADR-0015.** The rule above is restated as **no control**, not no coupling.
The engine now also asks the queue one read-only question — `TagBlocked = (WorkID) -> Bool`, "is
there an unexpired failure on record for this Work" — through a second injected closure, so it can
tell a reader whose library cannot be tagged from one who has simply not read enough. It still
cannot start, stop, pace, or alter the queue, and the queue remains unaware it is being asked. The
closure form is what keeps this from decaying into a type dependency; see ADR-0015 for why the
`WorkStore` cannot answer the question instead.

`setPriority` **replaces** rather than merges. The map is complete for every Work with reading
history, so a Work dropping out means its history is gone, and it should fall to the tail rather than
keep a stale weight.

**Accepted cost: `profileAndExclusions()` stops being a pure accessor.** That is already conceded —
it calls `resolveSignals()`, which mints Works and back-seeds snapshots (`:157-180`). Adding a third
side effect to a path documented as having two is honest; hiding it in `rebuild()` to preserve a
purity the function does not have would be theatre.

### The queue owns its memory, is owned but not published, and stops only on `.background`

```swift
.onChange(of: scenePhase) { _, phase in
    switch phase {
    case .active:     queue.start()
    case .background: queue.stop(); works.flush(); queue.flush()
    default:          break
    }
}
```

`UpgradeAttemptMemory` is constructed by the queue behind a default init parameter, and `flush()` is a
one-line delegate. Hoisting it to the App struct alongside `works` was rejected because it would
advertise as app-wide state the very thing ADR-0008's delete test isolated, and invite a second
reader.

**`.inactive` is not a stop signal.** ADR-0009 says "cancelled on `.background`" and that is kept
literally. A Control Center pull, a notification banner and the app switcher all produce `.inactive`;
stopping there would tear down and re-scan several times a minute during ordinary use and — worse —
discard the pass's skip set each time, so an offline device would restart its doomed pass on every
banner. `.background` is the only phase where the OS is about to stop giving us time.

**`start()` is idempotent**, guarding on a non-nil task, because `.active` recurs without an
intervening `.background`. Without the guard every dismissed banner leaks another loop and "serial by
construction" — ADR-0009's stated reason the limiter's slot reservation is only belt-and-braces —
quietly becomes false. `ContentView` also carries `.task { queue.start() }`, because `onChange` does
not fire for the initial value; relying on iOS delivering `.inactive → .active` at launch works today
but is not something the queue's existence should rest on.

The queue is **not** placed in the environment. It has zero `@Published` properties by ADR-0009, so a
view that reached it could only misuse it; `@StateObject` ownership here is for lifetime, not reach.

**Accepted cost: `stop()` cancels without awaiting.** A suspended upgrade can resume after
`queue.flush()` has written, re-dirty the memory, and lose that one record to suspension — one
redundant resolution pass on the next launch, which is precisely the loss that let attempt memory
live outside `works.json`. Awaiting would block a `scenePhase` handler on an in-flight network
request.

### An AniList record with no genres and no tags is `.absentFromProvider`

**Amends ADR-0009's order of operations**, which reads as though step 4 always succeeds.

`AniListWork` gains `var hasContent: Bool { !genres.isEmpty || !tags.isEmpty }`. `WorkStore.apply`
uses it in place of its local binding (`WorkStore.swift:211`), and the queue reads the same property
off the value it already holds — so `WorkStore`'s signature is unchanged and the queue never has to
ask the store what it did. When it is false the queue still calls `apply`, because the AniList id and
canonical titles are worth keeping when the metadata is not, and then records
`.absentFromProvider(malId:)` instead of calling `forget`.

Without this, a Work holding a provisional snapshot whose AniList record is empty keeps that
provisional snapshot (`:211-212`), stays unconditionally stale (`Work.swift:104`), and — since its
external id now short-circuits resolution — is re-fetched every 2 seconds for as long as the app is
foregrounded. Obscure entries reachable from scraped sources are exactly the population this queue
exists to serve, so this is not a corner.

Hoisting `hasContent` onto the model rather than writing the expression twice is the point: two
hand-maintained copies in two files is how this defect returns.

A third `UpgradeOutcome` case, `.providerEmpty(malId:)`, was rejected on the enum's own design rule.
Its cases exist to distinguish *what evidence reopens them* — `.unmatched` is fingerprinted on title
count because a new synonym reopens it; `.absentFromProvider` is TTL-only because re-matching yields
the same id forever. An empty record reopens on exactly the same evidence as a missing one. So the
case is reused and its documentation widened to "AniList has nothing usable for that id: no entry, or
an entry carrying neither genres nor tags." Adding the case would have been free — the enum is
unreleased and no `upgrade-attempts.json` exists anywhere — which is why it is worth saying that the
reason is the rule, not the cost.

### Resolve before you remember

**Amends ADR-0009's order of operations.**

```
2.  works.setExternalIds(ExternalIDs(mal: id, anilist: nil), on: work.id)
2a. guard let live = works.work(work.id) else { return .idle }
2b. guard live.snapshot == nil || live.snapshot!.isStale(now: now) else {
        memory.forget(live.id); return .upgraded(live.id)
    }
3.  rateLimiter.run { try await anilist.work(malId: id) }
4.  works.apply(result, to: live.id)
5.  memory.forget(live.id)  /  memory.record(outcome, for: live.id)
```

Every memory write, and every skip-set insertion, targets `live.id`.

ADR-0009 writes the external id before the fetch specifically so a collision merges while there is no
snapshot to lose. The consequence it did not follow through: after step 2 the Work the queue is
holding may no longer exist. The loser is deleted and aliased (`WorkStore.swift:269-270`), so a
record written against the original id is dead on arrival — `allWorkIds()` yields only live ids, and
nothing will ever ask `suppresses` about it again. The survivor is left unsuppressed and still
eligible, and is re-picked on the next iteration: the same 404, every 2 seconds, forever.
Structurally the same defect as the decision above, reached by a different route.

`works.work(_:)` is the store's alias-following accessor (`:59-65`) and the `Work` it returns carries
the survivor's id, so `live` is correct whether or not a merge happened. It is also the right value to
hand `suppresses(_:now:)`: the survivor absorbed the loser's titles during the merge, so
`knownTitles.count` changed, and re-reading is what makes that parameter's whole reason for being a
`Work` rather than an id-and-count hold across a merge.

Step 2b is not tidiness. A merge is precisely the moment the queue may have made its own remaining
work redundant: if the survivor already carries a fresh provider snapshot, the candidate's only
reason for being in the queue was its own provisional snapshot, and it is gone. Fetching would spend
a paced request to overwrite good data with the same data.

**Accepted cost: 2b returns `.upgraded` for a Work the queue never fetched.** The breaker only cares
whether forward progress happened, and it did; a fourth `DrainStep` case would buy nothing.

Pruning the survivor's now-meaningless attempt record was rejected: it is dead weight rather than a
bug — the survivor has a fresh snapshot so it is not eligible, and its title count no longer matches
so `suppresses` returns false regardless — and it ages out at the TTL. Doing better would mean giving
`UpgradeAttemptMemory` a view of merges, which is a dependency it exists not to have.

### The queue's resolver reads `EntityResolutionStore.shared`, and writes nothing

The queue's `MALEntityResolver` is an injectable init parameter defaulting to
`.init(store: .shared)`.

ADR-0009 sells the resolver's cache read as a free fast path: a `.resolved(malId)` recorded for any
of the Work's Listings by a detail-page open is a valid answer for the Work. That claim is **false
unless the instance is `.shared`**. The store loads UserDefaults into memory once in `init`
(`EntityResolutionStore.swift:67-70`) and never reloads, so a queue holding its own instance is
frozen at launch and cannot see anything the session records. The fast path becomes a dead branch and
the queue pays a MAL search fan-out for answers the app already had — silently, because the wrong
wiring compiles and passes every test that injects its own store. `MyAnimeListDebugView.swift:138`
already makes exactly this mistake, which is the evidence that it is worth writing down.

Injecting the whole resolver rather than only the store is what lets tests combine both seams the
resolver already has: `MALEntityResolver(store: EntityResolutionStore(defaults: isolated), search:
stub)`, following the isolation idiom already established at `Manga_ReaderTests.swift:2067`.

The read is one-way. ADR-0008 rejected `EntityResolutionStore` as the *home* of Work-level answers
and `malId(for work:)` correctly writes nothing to it, so there is no contention with the detail
path. Rejecting a store as a home is not rejecting it as a source — but "we read a store we refuse to
write" looks like an oversight unless it is stated.

## Hazards

- **A `.graphQL` error is permanent and looks transient.** It means our query is wrong, so it will
  fail on every Work forever, and the breaker only reduces it to one wasted request per idle
  interval. Nothing surfaces it — the queue publishes nothing by design — so a broken query degrades
  to a silently non-functional subsystem.
- **The skip set makes offline behaviour phase-dependent.** Three failures idle the loop, but each
  foregrounding clears the set and pays another three. A user toggling between apps on a plane
  re-pays that cost on every return.
- **Batch 1 spends the ordering aggressively at the head.** Weight is pushed only on a successful
  rail build, so between builds the same top-weighted Works are drained in the same order — correct,
  but it means an ordering computed from a stale profile is followed exactly rather than averaged out
  across a batch.
- **`.task { queue.start() }` on `ContentView` couples queue lifetime to that view's identity.** If
  the root view is ever replaced or conditionally rebuilt, the task re-runs; idempotency covers it,
  but the coupling is invisible from the App struct where the ownership lives.
- **Nothing prunes attempt-memory records for merged-away Works.** They are inert and age out at 14
  days, but a store with heavy merge activity accumulates them.
- **`hasContent` now has two readers with one definition** — the point of the decision — which means
  a future change to what "content" means silently changes the queue's suppression behaviour as well
  as `apply`'s replacement behaviour. That coupling is intended and is the smaller risk, but it is a
  coupling.

## Revisit triggers

- If the scan ever stops being negligible — a store in the thousands, or a predicate that grows a
  network or disk term — batch 1 is the first thing to give up, and the fix is an incremental dirty
  set in the store rather than a bigger batch.
- If a second consumer needs to observe the drain (a debug view, a settings row showing progress),
  the zero-`@Published` decision is what to reopen, not the environment decision.
- If `.graphQL` failures ever happen in the field, the queue needs a way to say so — which is the
  first real argument for it publishing anything.
- If the cold-start ordering gap from ADR-0009 gets closed, the push site moves again, and
  `profileAndExclusions()` stops being the only place a profile is built.
- If merged-away attempt records ever become measurable, the answer is a prune during
  `loadIfNeeded` keyed on ids the store no longer yields — not a merge notification.
