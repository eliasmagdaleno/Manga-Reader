# Plan — Phase 3: JavaScriptCore runtime + WeebCentral port

Written 2026-09-03, against `main` after the MangaCarta rename (#133).

Phase 3 builds the extension runtime against a contract that is **already written**:
`docs/superpowers/specs/2026-09-02-host-api-design.md` plus **ADR-0003 Amendment 2**. The split is
load-bearing and every worker must be told it: **the ADR owns decisions and their reasoning; the
spec owns wire shapes, validation rules, and operation semantics.**

**Spec Section 15's twelve acceptance criteria are this phase's definition of done.** The slices
below are cut so every criterion is owned by exactly one slice, and each must be demonstrated *by a
test* rather than asserted in a PR body.

## Slices and dependency order

| # | Slice | Owns criteria | Depends on | Wave | Agent |
|---|---|---|---|---|---|
| S1 | Manifest & declaration validation | 2, 9 | — | 1 | Sonnet or Codex |
| S2 | Domain wire schemas + adapters | 3, 4 | — | 1 | Sonnet or Codex |
| S3 | WebKit isolation spike (gate 2) | 6 (cookies), 8 | — | 1 | **Opus high** (research risk) |
| S4 | JSC runtime core + invocation bridge | 7 | S2 | 2 | **Opus high** (deep bridge design) |
| S5 | Host capabilities: http, storage, log | 5, 6 (storage), 11 | S4 (thin) | 2 | Sonnet or Codex |
| S6 | WeebCentral port + engine/config proof | 1, 12 | S1, S2, S4, S5 | 3 | strongest + review |
| S7 | Identity lifecycle | 10 | S1 | 3 | Sonnet or Codex |

Three of the seven — S1, S2 and S3 — are **independent of each other and of the runtime core**,
which is what makes Wave 1 genuinely parallel. S1 and S2 are pure functions over JSON with no
JavaScriptCore dependency at all.

**S3 runs in Wave 1 deliberately**, not when S5 needs it. It is the one genuine risk in the phase,
and if its answer is bad it changes what Wave 2 builds. Discovering that late is the expensive
outcome.

Waves 2 and 3 run at most two wide, because their slices touch overlapping core types.

## Choosing a model and a provider for each slice

Two rules, both learned from Wave 1 rather than reasoned about in advance.

**Default to a cheaper model; make Opus high earn its place.** `claude-sonnet-5` or
`gpt-5.6-sol` is the default for a dispatched worker. Spend Opus high on a slice with genuine
research risk or deep cross-cutting design — S3 and S4 qualify; a pure JSON validator does not —
and state in one line why. The table above marks the two that earned it. **Fable is not an option:
this account has no access**, and a worker dispatched on it silently parks at an unconfirmed launch
prompt rather than failing.

**Never put a whole wave on one provider.** Wave 1 put S1 and S3 on Claude and S2 on Codex.
Claude's session limit hit mid-implementation and *both* Claude workers stopped with uncommitted
work while still reporting `liveness: live`; the Codex worker was untouched and finished. A wave on
one provider shares one failure domain and the failure is silent, so split any parallel wave across
`--agent claude` and `--agent codex`. Wave 2 is two slices: run one of each.

## Sequencing note

Slices land on `main` in wave order. **Do not stack PRs** — a child closes unrecoverably when its
base is deleted, and gets no CI in the meantime.

---

## Worker briefs

The briefs below are written to be pasted whole. Each one is prefixed by the shared preamble.

---

# Shared preamble — include verbatim at the top of every Phase 3 worker brief

You are implementing one slice of **Phase 3** of MangaCarta (repo:
`/Users/eliasmagdaleno/Manga-Reader`, GitHub `eliasmagdaleno/MangaCarta`, branch off `main`).
Phase 3 builds a JavaScriptCore extension runtime against a contract that is **already written**.

## Read these before writing code, in this order

1. `docs/superpowers/specs/2026-09-02-host-api-design.md` — the Host API design (666 lines).
2. `docs/adr/0003-extension-substrate.md`, including **Amendment 2**.
3. `CLAUDE.md` — build commands, architecture, and conventions.

**The split between those first two is load-bearing: the ADR owns decisions and their reasoning;
the spec owns wire shapes, validation rules, and operation semantics.** If you are asking "why is
it this way", the ADR answers. If you are asking "what exactly must the bytes look like", the spec
answers. Do not invent an answer that one of them already gives — and do not change either
document from an implementation slice.

**Section 15 of the spec lists twelve acceptance criteria.** Your brief names which of them you
own. Those are your definition of done, and each must be demonstrated *by a test*, not asserted in
a PR description.

**Section 16 lists four deliberately open evidence gates.** If your work runs into one, do not
quietly pick a value and move on — say so, and say what evidence would settle it.

## Non-negotiable working rules

Each of these has already cost this repository real time.

1. **Test-driven, and a passing test is not evidence until you have seen it fail.** Write the test
   first, watch it go red, then make it green. Before you believe any green assertion, stash the
   implementation and re-run to confirm it goes red. A previous "fix" here passed its new test
   *and passed again with the fix removed*, because the framework already supplied the behavior.
2. **Cite documents by term or section heading, never by `file:line`.** Line citations rot inside a
   single session; that has happened here.
3. **CI is a major version behind this machine** — CI is `macos-15` / Xcode 16.4 / Swift 6.0, local
   is Xcode 26.x / Swift 6.2. Green locally proves nothing about CI for new syntax. Treat isolated
   conformances (`extension X: @MainActor P`), `nonisolated(nonsending)`, `@concurrent` and
   `Task.immediate` as **unavailable**. This has already caused one red CI run.
4. **CI's SwiftLint is not this machine's either.** A five-member tuple failed CI on `large_tuple`
   while local SwiftLint passed the same file with exit 0.
5. **Every `xcodebuild` targets the iPhone 17 Pro simulator:**
   `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`. It holds a seeded fixture.
   A wedged simulator looks exactly like a failing suite — `** TEST FAILED **` naming no failing
   test means `xcrun simctl boot "iPhone 17 Pro"` and re-run. **Never erase the device**; erasing
   has already destroyed the fixture once.
6. **Test totals come from the result bundle, not the log tail.** Run with
   `-resultBundlePath <path>`, then
   `xcrun xcresulttool get test-results summary --path <path>`.
7. **Adding files:** `MangaCarta/Models/`, `MangaCarta/Services/` and
   `MangaCarta/Views/Components/` are Xcode synchronized groups — files dropped in them compile
   automatically. **`MangaCarta/Views/` and `MangaCartaTests/` are NOT** — a new file in either
   needs `xcp add-file "$PWD/MangaCarta.xcodeproj" --file "$PWD/<path>" --targets MangaCartaTests`.
8. **`project.pbxproj` churns under you** whenever Xcode has the project open. Check
   `git diff --stat` immediately before `git add`, not right after `xcp`.
9. **Do not stack PRs.** A child PR closes unrecoverably when its base is deleted. Branch from
   `main`.
10. **Do not push to `main`.** Branch protection does not block this account, so a direct push
    would land and waive both required checks. Open a PR.
11. **Known-broken, not yours to fix:** both UI test suites currently fail on `main` (issue #134).
    Do not treat that as your regression, and do not try to fix it. The unit bundle
    `MangaCartaTests` is green and is the suite you must keep green.

## Definition of done for your slice

- Your tests pass, and you have seen each of them fail first.
- The full unit bundle still passes:
  `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:MangaCartaTests test`
- SwiftLint is clean: `swiftlint lint --quiet`.
- A PR whose description states, per acceptance criterion you own, **which test demonstrates it**.
- If you discovered something the next slice needs to know, say it in the PR body — not only in a
  commit message.

---

# S1 — Manifest and Source-declaration validation

*(Prepend `_shared-preamble.md` verbatim.)*

**Acceptance criteria you own: 2 and 9.**
**Suggested agent: Claude or Codex. Depends on: nothing. Runs in Wave 1.**

## What you are building

Pure Swift. No JavaScriptCore. You validate an installed bundle's *Source declarations* — the
records that say "this Source uses that engine with this configuration" — before any extension
code is allowed to exist.

Spec sections that own your rules: **§1.2 (Source declaration)**, **§7 (Versions and feature
negotiation)**, **§12 (Adult classification)**, **§13 (Source-authored presentation)**, and
**§3 (Entry points)** for the registration invariants.

## The shape (from §1.2 — read it, do not trust this summary)

```json
{
  "localId": "example-madara-site",
  "name": "Example Manga",
  "engine": "madara",
  "configuration": { },
  "adult": "none",
  "capabilities": { "search": true, "popular": true, "newTitles": false,
                    "latestUpdates": true, "detail": true, "chapters": true,
                    "pages": true, "tagBrowse": false, "webURL": true },
  "languages": { "mode": "fixed", "values": ["en"] },
  "network": { "httpOrigins": ["https://example.test"],
               "browserOrigins": ["https://example.test"],
               "assetOrigins": ["https://cdn.example.test"] },
  "presentation": { "feeds": { "popular": { "title": "Popular" },
                               "latestUpdates": { "title": "Recently Updated", "badge": "new" } },
                    "imagePrefetchConcurrency": 4 },
  "hostAPI": { "minimum": "1.0", "maximumExclusive": "2.0" }
}
```

## Rules worth calling out because they are easy to get backwards

- **Unknown keys are ignored *only* inside `configuration`. Anywhere else they fail installation.**
  This asymmetry is deliberate — configuration is an engine's private vocabulary, the rest is the
  host's contract. Test both directions.
- `localId`: lowercase ASCII letters, digits, `-`, `.`; 1–64 chars; **immutable across updates**.
- `name`: nonempty after trimming, ≤80 Unicode scalars. It is display text, **not identity** —
  nothing may key off it.
- `adult` ∈ `none|mixed|adultOnly`, **required, fail-closed**. Absent or unrecognized is a
  rejection, never a default to `none`. Per §12, review may only ever *strengthen* a
  classification, never weaken it.
- `languages.mode` ∈ `fixed|selectable|mixed`; values are BCP 47 (§8). **No silent substitution** —
  an unsupported language is an error, not a fallback.
- `presentation.feeds[].badge` ∈ `none|new`. Strings trimmed and length-bounded. The host owns
  layout, localization and accessibility; a declaration supplies semantics only.
- `imagePrefetchConcurrency` is a **hint**, clamped by the host — not an instruction.
- **Registration invariants (§3):** `search`, `detail`, `chapters`, `pages` are all required for a
  browsable/readable Source, **and** at least one of `popular`/`newTitles`/`latestUpdates` is
  required for Home discovery. A declaration failing either is **not registered**.
- **Host API range (§7):** intersect the declared `{minimum, maximumExclusive}` with the host's
  supported range. No match means refusing registration with an **actionable** error — that is
  criterion 9, and "actionable" means the error names the versions involved.

## The Source id — the trap in this slice

The **installer** owns repository identity and mints an **opaque, repository-qualified Source id**
by combining it with the immutable `localId`. Extension code *receives* that id and may never
construct or parse it, and neither may the UI. The same `localId` in a different repository must
not collide.

The installer itself is Phase 4. **Do not build it.** Model the boundary — take the qualified id
as an input to your validator — so Phase 4 can supply it without reshaping your types.

## How to demonstrate criterion 2

Criterion 2 is *"manifest validation and Source registration execute no Extension code."* The
strongest available evidence is **structural, not behavioral**: build the validator so it does not
link JavaScriptCore at all, and say so in the PR. Do not settle for a test that merely observes no
callback firing — that proves the absence of one path, not the absence of the capability.

## Scope boundary

You validate declarations. You do **not** load, parse, or execute extension JavaScript; you do not
implement the installer, the repository format, package signing, or storage. If you find yourself
needing any of those, you have left the slice — say so in the PR rather than expanding it.

---

# S2 — Domain wire schemas and Swift adapters

*(Prepend `_shared-preamble.md` verbatim.)*

**Acceptance criteria you own: 3 and 4.**
**Suggested agent: Claude or Codex. Depends on: nothing. Runs in Wave 1.**

## What you are building

Pure Swift. No JavaScriptCore. You validate the five domain types an extension returns over the
wire, and adapt them onto the app's existing model types (`Manga`, `Chapter`).

Spec sections that own your rules: **§2 (Domain wire schemas)** for the five types, **§1.3
(Envelope and value rules)**, **§3.1 (Pagination)**, and **§6 (Errors and partial success)** for
how warnings are shaped.

The five types: `Listing`, `Update`, `Detail`, `Chapter`, `Page`.

## The heart of this slice: drop-versus-reject

Every type has a different answer, and the tempting mistake is to apply one policy uniformly. Read
§2 for the authoritative rules; these are the ones that catch people:

- **Listing** — an item missing `id` or `title` is **dropped with a warning**, but a structurally
  wrong *top-level* type **rejects the whole operation**. If every item is dropped, that is a
  *success* with an empty list plus warnings — not a failure.
- **Chapter** — an invalid `publishedAt` (must be an RFC 3339 instant) **drops the field and keeps
  the chapter**, with a warning. The host **never reorders or merges** chapters.
- **Page** — **any** invalid page item **rejects the entire result**. Pages are the one type with
  no partial success, because a reader silently missing page 7 is worse than an error. An empty
  page list is allowed, and must surface as empty-content rather than as a completed chapter.
- **Detail** — a non-object result rejects; invalid tags are dropped with warnings; a tag needs a
  nonempty `name`.
- **Update** — `{chapterId, listing}` both required; invalid items dropped one by one.

## Semantic traps

- **Missing `contentRating` means *unknown*, not `safe`.** Defaulting to safe would let an
  unclassified Source past adult gating.
- **A missing chapter count means *unknown*, never zero** (ADR-0004). Zero is a claim; absent is
  not.
- Missing `status` → `unknown`. Missing `description` → `""` at the Swift adapter boundary.
  **Nothing else is fabricated** — do not invent placeholder titles, covers, or ids.
- `year`: integer, 1000…currentYear+1.
- Unknown `externalIds` namespaces are **preserved on the wire** and ignored by a host that does
  not understand them. Do not strip what you do not recognize.
- Empty alternate titles dropped; exact-match duplicates removed.
- **JSON-only values (§1.3):** `undefined`, functions, symbols, cycles, non-finite numbers, dates,
  typed arrays and host objects are all invalid. Reject them; never coerce.

## Criterion 4 — Source-id stamping

*"Source-id stamping cannot be overridden by Extension output."* **The host stamps every Listing
with the id of the Source it invoked**, and an extension that returns its own `sourceId` must not
be able to change that. Test the adversarial case explicitly: an extension returning a *different*
Source's id must still produce Listings stamped with the invoked one.

This mirrors an invariant the codebase already holds — `MangaAttributes.toManga` stamps
`Manga.sourceId` on every conversion path. Read that first and stay consistent with it; ADR-0001
explains why identity works this way (the Work is the identity, a Listing is one source's copy).

## Pagination (§3.1)

`Page<T>` is `{ items, nextCursor, exhausted, warnings }`. **Exactly one** of a non-null
`nextCursor` or `exhausted: true` must be present — validate that, since it is the kind of thing an
engine gets wrong silently. Cursors are opaque strings ≤2 KiB; the host never interprets them.
**Short pages mean nothing** — do not infer exhaustion from a page smaller than `limit`.

## Scope boundary

You validate and adapt values. You do **not** execute JavaScript, implement host capabilities, or
touch the manifest (that is S1). Coordinate with S1 only on the shared warning/error taxonomy from
§6 — and if you two disagree about a shape, the spec decides, not whoever wrote code first.

---

# S3 — The WebKit isolation spike (closes evidence gate 2)

*(Prepend `_shared-preamble.md` verbatim.)*

**Acceptance criteria you own: 6 (cookie half) and 8.**
**Suggested agent: Fable, high effort. Depends on: nothing. Runs in Wave 1.**

## Why this exists and why it is first

This is **the one genuine risk in Phase 3**, and it is a *research* task with a decision as its
deliverable — not a feature.

Spec **§16, evidence gate 2** is open on purpose: the design cannot yet name the iOS 17.5 WebKit
mechanism that provides **both** persistent Cloudflare clearance **and** strong per-Source
isolation. Those two pull directly against each other, and the existing code sits on one side of
the tension: `Services/WebViewService.swift` deliberately uses **one shared persistent data store**
precisely so Cloudflare's `cf_clearance` cookie survives relaunch, plus a pinned User-Agent. That
is a considered choice, not an oversight — read it and understand why before proposing to undo it.

It runs in Wave 1 rather than when the browser capability needs it, because if the answer is bad it
changes what Wave 2 builds. Discovering that late is the expensive outcome.

## What you must produce

**A prototype and a decision.** Concretely, per **§9 (Browser identity and interaction)**:

> an iOS 17.5 prototype proving cookie isolation and persistence across process relaunch for two
> Sources on one origin.

Two Sources, the *same* origin, and you must demonstrate:

1. **Isolation** — Source A cannot read Source B's cookies or website data. This is criterion 6's
   cookie half. Test it adversarially, not by inspection.
2. **Persistence across process relaunch** — clearance obtained in one launch is still there in the
   next. A test that only proves isolation within one process has not answered the question.
3. **Criterion 8** — a background challenge returns the `interaction_required` error **without
   presenting UI**. Per §9, challenge-sheet copy is host-authored, and background invocations must
   never silently surface a sheet.

## Both outcomes are acceptable; silence is not

The spec already names the fallback, so you are not required to find a mechanism that may not
exist:

> if the target cannot provide durable isolated stores: separate nonpersistent stores plus explicit
> loss of cross-launch clearance — **never a shared global store**.

So: find a mechanism that gives both, **or** demonstrate that iOS 17.5 does not and ratify the
fallback. What is *not* acceptable is leaving the gate open, or quietly picking the shared store
because it is what exists today. If you land on the fallback, state plainly what the reader loses —
they will re-solve Cloudflare challenges more often — since that is a real product cost someone
must weigh.

## The deliverable is an ADR amendment, not a note

Write the decision as an **amendment to ADR-0003**, following the amendment style already in that
file. Per `CLAUDE.md`'s document-ownership rule, **a decision that lives only in a handoff is not
recorded** — handoffs get archived and archived handoffs are never worked from. Amend; never
rewrite the original text.

Include the *evidence*, not just the conclusion: what you tried, what the API actually did, and on
which OS version. The next person needs to know whether a future iOS makes this reconsiderable.

## Where to look

- `Services/WebViewService.swift` — today's shared persistent store, the pinned UA, the interactive
  challenge sheet, the sticky 30s decline, and cancellation handling.
- `Services/SourceContext.swift` — how sources receive the capability; `WebViewExtracting` is the
  protocol tests mock.
- Spec **§4.2** (`host.browser.extract`, single-flight globally in v1, structured-cloned return
  value) and **§9** (identity, partitioning by Source + origin, host-owned UA).

Relevant API surface to evaluate includes `WKWebsiteDataStore` (default, nonpersistent, and — check
availability and behavior on the 17.5 deployment target rather than trusting documentation
summaries) and how data stores relate to process pools and cookie stores. **Verify empirically.**
The whole reason this gate is open is that the documentation did not settle it.

## Scope boundary

Prototype and decide. You are **not** building the production `host.browser.extract` — that is S5,
and it will consume your decision. Keep the prototype small enough to throw away; the ADR amendment
is the artifact that lasts. If the prototype is worth keeping as a test, say so.

---

# S4 — JavaScriptCore runtime core and the invocation bridge

*(Prepend the shared preamble verbatim.)*

**Acceptance criterion you own: 7.**
**Model: Opus high — this is one of the two slices that earns it. Depends on: S2 (merged).
Runs in Wave 2, alongside S5, on a different provider from S5.**

## What you are building

The thing that actually runs an Extension. A `JSContext` per invocation, the message contract from
spec **§1.1**, and the cancellation semantics of **§5**. Wave 1 built the pure-Swift validation
that sits on both sides of you; you are the part that touches JavaScriptCore at last.

Spec sections that own your rules: **§1.1 (configuration-first Sources)**, **§1.3 (envelope and
value rules)**, **§5 (scheduling, budgets, cancellation)**, and **§7 (versions and feature
negotiation)** for what `context.host` contains.

## What Wave 1 already built — use it, do not rebuild it

All of this is on `main`. Read it before you design anything.

- **`SourceDeclarationValidator`** (S1) — validates a declaration and tells you which capabilities
  a Source declared. `HostAPIVersion` / `HostAPIVersionRange` / `HostAPISupport` do version
  negotiation. `JSONValue` is the JSON model both slices already share.
- **`ExtensionDomainValidator`** and the `Extension*` wire types (S2) — validate what comes *back*.
  You do not re-validate domain shapes; you hand raw values to that validator.
- **`ExtensionHostErrorCode`**, `ExtensionSchemaError`, `ExtensionValidationWarning` (S2) — the
  shared taxonomy. **Reuse it.** If you need a case it lacks, add the case rather than forking the
  type, and say so in your PR body.

## The hard requirement S2 left you, in its own words

> The invocation bridge must inspect raw `JSValue` kinds **before** Foundation conversion:
> conversion can erase `undefined`/Symbol properties and collapse functions or typed arrays into
> indistinguishable objects. The Foundation-level validator rejects the native analogues, but S4
> must make pre-conversion rejection a hard boundary.

This is the single most important sentence in your brief. §1.3 says `undefined`, functions,
symbols, cyclic objects, non-finite numbers, dates, typed arrays and host objects are all invalid.
By the time a value is an `NSDictionary` you can no longer tell some of those apart from valid
data — so a `JSValue`-kind check after conversion is not a check at all. Test the adversarial
cases directly: an object with an `undefined`-valued property, a function-valued property, a
`Symbol` key, a cycle, `NaN`/`Infinity`, a `Date`, and a `TypedArray`.

## Criterion 7 — the one you own

*"Cancellation prevents every late callback from changing invocation state."*

Per §5: once cancelled, no new host-capability call is accepted, queued calls are removed, active
`URLSession` work is cancelled, and eventual JavaScript or WebKit callbacks are **discarded**. The
runtime waits a short grace period and then destroys an uncooperative context. Extensions cannot
create timers or detached work that outlive the invocation.

"Discarded" is the testable word. Build the adversarial case: an Extension whose callback fires
*after* cancellation must not be able to mutate any invocation state, resolve a result, or emit a
warning. A test that merely shows cancellation returns promptly does not demonstrate this.

## Traps

- **CI is Swift 6.0; local is 6.2.** A JSC bridge is exactly where `@concurrent`,
  `nonisolated(nonsending)`, `Task.immediate` and isolated conformances are most tempting. All are
  **unavailable**. This is called out in the preamble because it will bite you specifically.
- **`JSContext` is not `Sendable`** and JavaScriptCore is not thread-safe across contexts. Decide
  the isolation story deliberately and write it down; do not let it emerge.
- Configuration is **deep-frozen** before invocation (§1.1), and an engine cannot enumerate other
  Sources' configuration or invoke another Source.
- The host, not Extension code, stamps every returned Listing with the invoked Source id (§1.3) —
  S2 enforces this, and your bridge must not hand it a way around.

## Scope boundary

You build the context, the message contract, and cancellation. You do **not** implement
`host.http`, `host.storage`, `host.log` or `host.browser` — that is S5, running beside you. Agree
the shape of `context.host` with S5 early and keep it thin; where you disagree, **the spec
decides**. You do not port WeebCentral (S6) or build the installer (Phase 4).

---

# S5 — Host capabilities: http, storage, log, and the browser

*(Prepend the shared preamble verbatim.)*

**Acceptance criteria you own: 5, 6 (storage half), and 11.**
**Model: Sonnet or Codex. Depends on: S4, thinly. Runs in Wave 2, alongside S4, on a different
provider from S4.**

## What you are building

The capability brokers an Extension is handed: bounded HTTP, per-Source storage, redacted logging,
and the production browser extraction that S3's spike proved out.

Spec sections that own your rules: **§4 (host capabilities)** for all four, **§9 (browser identity
and interaction)**, **§10 (URL policy)**, and **§5** for budgets.

## Build the browser capability on a per-Source store — this is settled, and it is not obvious

**ADR-0003 Amendment 3** closed evidence gate 2: `WKWebsiteDataStore(forIdentifier:)` on iOS 17.5
gives **both** per-Source isolation and persistence across relaunch. Read the amendment first.

- Build `host.browser.extract` on a **per-Source identified store**, **not** on
  `WebViewService`'s shared `.default()` store.
- **`WebViewService` stays unchanged.** It keeps its shared store for the compiled
  `WeebCentralSource` until that Source is ported in S6, so the app deliberately holds both
  mechanisms for now. Do not "unify" them.
- The store identifier is a **name-based (v5) UUID over a fixed namespace and the qualified Source
  id**. **The namespace constant is permanent** — changing it orphans every reader's Cloudflare
  clearance.

### Three rules from the spike, which are one behaviour seen three ways

An identified store **materialises lazily**, so nearly everything about it is true only
*eventually*. Each of these cost the spike real time:

1. **A store no `WKWebView` was ever constructed against never becomes durable.** Writing through
   `WKHTTPCookieStore` and holding the store alive is not enough.
2. **A freshly opened store's cookie jar loads asynchronously** — the first `getAllCookies` returns
   an **empty jar with no error**. Never gate behavior on an immediate jar read; drive the browser
   and let WebKit apply cookies. Losing this race looks exactly like *"Cloudflare keeps
   re-challenging me"*.
3. **A constructed store is not yet on disk**, and `fetchAllDataStoreIdentifiers` will not list it
   until first use. **A data-removal or installer screen that enumerates stores at launch would
   show a reader nothing.** Await one operation before expecting a store to appear.

## Your three criteria

- **5 — "HTTP and browser redirects cannot escape declared HTTPS origins."** Per §10: absolute
  HTTPS only; every redirect hop revalidated; loopback, link-local, multicast and private addresses
  rejected **after DNS resolution** to prevent rebinding. S2 flagged that origin membership at the
  schema layer is **not** a substitute for these runtime checks — they are yours.
- **6 (storage half) — "two configured Sources cannot read each other's storage."** §4.3: storage
  is namespaced by *qualified* Source id, survives updates and disablement, is retained on ordinary
  uninstall, and is erased only by explicit user action. No credentials, no filesystem paths.
- **11 — "logs redact all prohibited reader and request data."** §4.4 is specific: URLs reduce to
  origin plus redacted path shape; queries, bodies, cookies, headers, storage values, search text,
  Listing titles, chapter ids and reader identifiers are rejected or redacted. Test that a log call
  *carrying* those is redacted, not merely that a clean call passes.

## Traps

- **§4.1 header policy:** reject `Host`, `Cookie`, `Authorization`, `Proxy-Authorization` and
  `User-Agent`; strip hop-by-hop headers. Cookies live in a host-owned jar partitioned by Source
  and origin. **The host does not automatically retry** — expose parsed `Retry-After` instead, so
  a POST is never silently duplicated.
- **§4.2:** browser extraction is **globally single-flight in v1**, the UA is host-owned, and the
  script's return value is structured-cloned. **Authors do not call `JSON.stringify`** — that is
  today's `WebViewService` convention and the Host API deliberately drops it.
- **§9 / criterion 8, already built by S3:** a background invocation returns `interaction_required`
  and **never** presents a sheet. Amendment 3 settled the `interaction` enum as `allowForeground`
  and `never`, and made the effective policy the **intersection** of the author's request and the
  host's invocation context — an engine cannot know whether the app is foregrounded, and must not
  be able to talk its way into a sheet during a background refresh.
- Exact numeric budgets are **evidence gate 1 and still open** (§5, §16). Choose conservative
  tunables, keep them in one place, and **say plainly in your PR that they are unmeasured** rather
  than presenting them as settled.

## Scope boundary

You build the capability brokers. You do **not** build the JSC context or cancellation machinery
(S4, running beside you), port WeebCentral (S6), or build the installer (Phase 4). Agree
`context.host`'s shape with S4 early; where you disagree, **the spec decides**.

---

# S6 — WeebCentral port and the engine/configuration proof

*(Prepend the shared preamble verbatim.)*

**Acceptance criteria you own: 1 and 12.**
**Model: strongest available, reviewed. Depends on: S1, S2, S4, S5. Runs in Wave 3.**

## S5 is not merged yet — read this before doing anything else

The dependency table says you depend on S5, and as of this writing S5 is **parked mid-implementation,
uncommitted**, not on `main`. Do not guess at its shape. Before you start:

1. Check `docs/superpowers/handoff/` (the one live file — `CLAUDE.md` → "Handoffs" explains why
   there is only ever one) for S5's current status and where its worktree lives.
2. If S5 has since merged, read the merged `MangaCarta/Services/Host*.swift` files directly —
   `HostHTTPClient`, `HostBrowser`, `HostStorage`, `HostLogger`, `HostURLPolicy`,
   `HostCapabilityTypes`, `HostJSONValueConverter` — for their actual public API. Do not build
   against a name or signature you have only seen in a plan or handoff; both have already stated
   things about merged Phase 3 code that turned out false (see "Hard constraints" in your
   dispatch). If S5 is still unmerged, escalate rather than inventing its interface — this slice
   cannot be honestly finished without it, because criterion 12 requires equivalent behavior
   including the browser-backed pages, and browser access only exists through S5's
   `host.browser` capability.
3. Confirm which `interaction` mode WeebCentral's port should request. Amendment 3 (below) settled
   the enum as `allowForeground`/`never`, chosen by the author and intersected with the host's own
   invocation context — read Amendment 3 in full before picking one.

## What Wave 1 and Wave 2 already built — use it, do not rebuild it

All of this is merged on `main`; read the actual files, not this summary, before writing config.

- **`SourceDeclarationValidator.validate(json:qualifiedId:hostAPI:)`** (S1,
  `MangaCarta/Models/SourceDeclarationValidator.swift`) turns a JSON declaration plus an
  already-minted `QualifiedSourceID` into a `SourceDeclaration` or a `SourceDeclarationError`. It
  also exposes `validateUpdate(from:to:)`, which enforces that `qualifiedId` and `localId` never
  change across an update — the identity invariant S7's brief calls "the trap." You will write the
  JSON declarations WeebCentral needs to pass this validator; you do not touch the validator itself.
- **`SourceDeclaration`** (`MangaCarta/Models/SourceDeclaration.swift`) is the validated Swift
  record: `qualifiedId`, `localId`, `name`, `engine`, `configuration: JSONValue`,
  `adult`, `capabilities: SourceCapabilities`, `languages`, `network`, `presentation`, `hostAPI`,
  `selectedHostAPIVersion`. `configuration` is opaque `JSONValue` — the engine's private
  vocabulary — which is exactly the mechanism criterion 1 needs: three declarations, one engine,
  distinguished only by what is inside `configuration`.
- **`ExtensionDomainValidator`** (S2, `MangaCarta/Models/ExtensionDomainSchemas.swift`) validates
  what an invocation returns: `validateListingPage`, `validateUpdatePage`, `validateDetail`,
  `validateChapters`, `validatePages`, each returning an `ExtensionValidatedResult` or
  `ExtensionValidatedPage` carrying `ExtensionValidationWarning`s. It is constructed with
  `assetOrigins` from the declaration's `network.assetOrigins` — do not invent a second place to
  declare which CDN a cover may come from. Read ADR-0024 (below) before writing any cover-URL test.
- **`ExtensionRuntime`** (S4, `MangaCarta/Services/ExtensionRuntime.swift`) is the thing that
  actually runs your bundle: one `JSContext` per `invoke(_:request:cancellation:)` call, built from
  a `bundleScript` string, a `SourceDeclaration`, and an array of `ExtensionHostCapability`
  (S5's brokers). Your engine script registers itself with the runtime's global `registerEngine(name,
  engine)` function — `engine` is an object with an `invoke` function, and `declaration.engine` is
  the name the runtime looks up. `invoke` receives `(operation, request, context)` where `context =
  { source: { id, configuration, languages }, host, signal }`, exactly the shape in the spec's
  §1.1. **The host, not your script, stamps `source.id`** — you never construct or read structure
  out of it, per the "Source id" trap below.
- **`ExtensionJSBridge`** (S4, `MangaCarta/Services/ExtensionJSBridge.swift`) is what converts your
  script's return value and rejects the eight forbidden JSON-incompatible kinds *before* any
  Foundation conversion. You do not call this directly — `ExtensionRuntime` does — but its
  existence is why your engine script must return plain JSON-shaped objects: no `undefined`
  properties, no functions on the result, no `Date`, nothing cyclic.
- **`ExtensionHostErrorCode`, `ExtensionSchemaError`, `ExtensionValidationWarning`** (S2) are the
  taxonomy your engine's rejected envelopes must use. Read the `ok`/`error`/`value` envelope shape
  in `ExtensionRuntime.envelope(_:bridge:invocationID:)` — your engine returns `{ ok: true, value:
  ... }` or `{ ok: false, error: { code, message, retryAfterSeconds?, details? } }`, and `code`
  must be one of `ExtensionHostErrorCode`'s cases or the runtime rejects the whole envelope as
  `invalidResponse`.
- **ADR-0024** (`docs/adr/0024-a-bad-cover-costs-the-cover-not-the-feed.md`) changed cover-URL
  handling *while S5 was mid-implementation*: a policy-invalid (not merely malformed) optional
  cover URL now drops the field with a `policy_invalid_url` warning and keeps the item, rather than
  rejecting the whole operation. Every other URL kind — pages, `webURL`, request URLs — still
  rejects on policy violation. Write your WeebCentral cover-handling test against this rule, not
  against the literal §10 text, which this ADR amends the reading of.

## What you are building

Port `MangaCarta/Models/WeebCentralSource.swift` — today a compiled Swift `MangaSource` conformer —
to run as a **configuration-backed Extension** on `ExtensionRuntime`, and prove criterion 1 by
writing **at least three differently configured Sources against the same engine**, not just one
WeebCentral-shaped Source.

Read the existing file in full before starting. It is small (about 270 lines) and everything in it
is now a spec for what your ported behavior must equal:

- Five operations: `search`, `popular`, `newTitles`, `latestUpdates`, `mangaDetail` → `detail`,
  `chapters`, `pageURLs` → `pages`, and `webURL`. Map the Swift method names onto the spec's
  Entry-points table (§3) exactly — `mangaDetail` becomes the `detail` operation, `pageURLs`
  becomes `pages`, and so on.
- **`chapterNumber(fromTitle:)`** — the last numeric token in a chapter's title string becomes its
  display number, with `"?"` for titles that carry none (e.g. "Oneshot"). This is domain logic,
  not scraping, and it has no equivalent in the Host API's wire types — it has to live in your
  engine script or in `Chapter`-adapter code your engine's output feeds.
- **`WCSeriesItem`, `WCDetail`, `WCChapterItem`, `WCUpdateItem`** are the DTOs the current JS
  extraction returns. Your engine's `invoke` results must satisfy `ExtensionDomainValidator`'s
  schemas instead — read §2 of the spec for what `Listing`, `Update`, `Detail`, `Chapter`, `Page`
  require, and do not assume the current DTOs already match; they predate the Host API design.
- **The five JS extraction scripts** (`seriesListScript`, `detailScript`, `chaptersScript`,
  `pagesScript`, `latestUpdatesScript`) are, per `CLAUDE.md`, **the volatile part when the site
  redesigns** — they are raw DOM-scraping strings tied to WeebCentral's current markup (`article.
  flex.gap-4`, `.whitespace-pre-wrap`, `time[datetime]`, and so on). Porting them means moving this
  same DOM logic into your engine's bundle script, run through `host.browser.extract` instead of
  today's `SourceContext.webView.extract`. **They do not call `JSON.stringify` any more** — S5's
  brief states plainly that the Host API's browser capability structured-clones its return value
  and "today's `WebViewService` convention" of a final `JSON.stringify` is "deliberately dropped."
  Update the scripts' final expression accordingly, or your extraction result will arrive as a
  string the domain validator rejects instead of the object it expects.
- **`chapterId`/`mangaId` extraction via `seg(href, name)`** is WeebCentral's own URL-segment
  convention, unrelated to `QualifiedSourceID`. Do not conflate the two: `seg` produces the
  *listing* id inside WeebCentral's URL space; the Source's own identity is a separate,
  host-minted `QualifiedSourceID` you never construct (see below).

## The Source id — the trap in this slice too

Same trap S1's brief names, seen from the other side. Your engine receives `context.source.id` as
an opaque string and must pass it through unexamined — never parse it, never reconstruct it, never
assume its shape. `ExtensionDomainValidator`/`ExtensionRuntime` stamp every `Listing` with the
invoked Source's id on the host side (criterion 4, S2's slice); your engine script must never try
to do this itself or override it by returning its own `sourceId` field — if it does, S2's
adversarial test already proves the host's stamp wins, so an engine attempting it only wastes
effort, but do not write an engine that relies on that field being honored.

## The engine/configuration proof — criterion 1

*"One theme engine serves at least three differently configured Sources without code duplication."*

Write **one** engine (call it whatever the bundle names, e.g. `"weebcentral"` or a more generic
theme name if you decide the DOM structure generalizes beyond one site — that is your call, but
name it honestly for what it actually generalizes to). Then write **three `SourceDeclaration`
JSON fixtures** that select that engine with different `configuration` payloads — at minimum a
different base URL and a different set of DOM selectors or path templates, whatever your engine
actually parameterizes. Test that all three:

- validate and register through `SourceDeclarationValidator` independently;
- invoke through `ExtensionRuntime` independently, with no shared mutable state (the runtime
  already gives you this for free — a fresh `JSContext` per invocation — but your test must
  demonstrate it, not assume it);
- produce different results appropriate to their own configuration, proving the engine is generic
  rather than hardcoded to WeebCentral's URLs.

If you cannot find three genuinely different real-world configurations of this engine (WeebCentral
itself only gives you one live site), a synthetic second and third configuration against
fixture/mock HTML is acceptable — the criterion is about the *engine's* genericity, not about
having three live WeebCentral-family sites in production. Say in your PR body which of the three
are live and which are fixtures, and why.

## The equivalence proof — criterion 12

*"The compiled WeebCentral Source can be replaced by a configuration-backed Extension with
equivalent browse/detail/chapter/page behavior, modulo intentional validation improvements."*

"Modulo intentional validation improvements" is doing real work in that sentence — it means you are
not required to reproduce a bug. If the compiled source silently drops a malformed cover and your
ported engine now surfaces `policy_invalid_url` per ADR-0024, that is an improvement to call out in
the PR body, not a regression to explain away. But anything that isn't a deliberate, documented
improvement must match: the same chapters in the same order for the same title, the same page URLs,
the same `chapterNumber` display values.

Write comparison tests that exercise both the compiled `WeebCentralSource` and your ported engine
against the same captured HTML fixtures (do not depend on live network for a merge-blocking test —
`CLAUDE.md`'s flaky-live-network lesson applies here as much as anywhere) and assert the outputs
match field-for-field, modulo the improvements you documented.

## Scope boundary

You port WeebCentral's behavior onto the runtime and prove criteria 1 and 12. You do **not**
build the installer or repository format (Phase 4), change `SourceDeclarationValidator`,
`ExtensionDomainValidator`, `ExtensionRuntime`, or any S5 host capability's public API — if one of
those needs a change to make your port possible, say so in the PR body and propose the change
rather than making it unilaterally in a slice that isn't reviewed for it. You do not remove or
change the compiled `WeebCentralSource` or `WebViewService` — per Amendment 3, `WebViewService`
"is not changed by this amendment" and "keeps its shared store for the compiled `WeebCentralSource`
until that Source is ported" — and "ported" here means your Extension exists and is proven
equivalent, not that the compiled source is deleted or that the app is switched over to it. Cutting
the app over to the ported Extension in place of the compiled Source is a follow-up decision for
whoever owns the registry, not part of this slice.

---

# S7 — Identity lifecycle

*(Prepend the shared preamble verbatim.)*

**Acceptance criterion you own: 10.**
**Model: Sonnet or Codex. Depends on: S1 (merged). Dispatchable now — does not wait on Wave 2 or 3.**

## What you are building

*"Disable/uninstall/reinstall preserves and reconnects Listings and pins for the same qualified
Source id."* Spec §11 ("Identity lifecycle") owns the rules; read it in full, not just the excerpt
below.

An update may change `name`, `engine`, `configuration`, and `capabilities`, but never repository
identity or `localId`. Disablement and uninstall unregister the Source but must **preserve**
Listings, pins, and bounded Source storage — calls simply fail as unavailable, and existing
fallback behavior may choose another registered Source. Reinstalling the *same* repository identity
plus the *same* `localId` must **reconnect** the stored references; an unrelated repository cannot
claim them by coincidentally reusing a `localId` string.

## What S1 already built — use it, do not rebuild it

Read `MangaCarta/Models/SourceDeclaration.swift` and `MangaCarta/Models/SourceDeclarationValidator.swift`
in full before writing anything. Concretely:

- **`QualifiedSourceID`** is `struct QualifiedSourceID: Hashable, Sendable { let rawValue: String
  }`. It is opaque by convention, not by type — the type itself is a bare string wrapper, so the
  discipline of never parsing or constructing one is enforced by review and by your tests, not by
  the compiler. **The installer mints this value; S1 explicitly did not build the installer** ("The
  installer itself is Phase 4. Do not build it.") and neither do you. Your tests take
  already-minted `QualifiedSourceID` values as fixtures, exactly the way S1's own validator tests
  do.
- **`SourceDeclaration.localId`** is the immutable, installer-supplied identity within one
  repository; **`SourceDeclaration.qualifiedId`** is what the installer derives by combining
  repository identity with `localId`. Neither field is derived by anything in this file, and
  neither should be derived by anything you write.
- **`SourceDeclarationValidator.validateUpdate(from previous: SourceDeclaration, to next:
  SourceDeclaration) -> SourceDeclarationError?`** already exists and already enforces the exact
  rule this slice is named for, at the *declaration* level: it returns `.qualifiedIdentityChanged`
  if `qualifiedId` differs and `.localIDChanged(from:to:)` if `localId` differs, and `nil` when the
  update is allowed. **This is not your slice to reimplement.** What it does not cover — and what
  criterion 10 actually asks for — is the *registry/persistence* behavior across disable, uninstall,
  and reinstall: whether Listings and pins keyed by a `QualifiedSourceID` survive those lifecycle
  transitions and reconnect correctly. That is new code you write, consuming `validateUpdate` where
  an update is involved rather than duplicating its logic.

## The trap S1's brief names, and why it matters here specifically

S1's brief calls out: *"The installer owns repository identity and mints an opaque,
repository-qualified Source id ... Extension code receives that id and may never construct or
parse it, and neither may the UI. The same `localId` in a different repository must not collide."*

For this slice that trap becomes concrete: your reconnection logic must key exclusively on
`QualifiedSourceID` equality (`Hashable`/`Equatable`, already derived on the type) and must **never**
fall back to comparing `localId` strings alone to decide whether two installations are "the same
Source." Two different repositories can legally share a `localId`; only the installer-minted
`qualifiedId` says whether they're the same Source. Write the adversarial test explicitly: two
declarations with the same `localId` but different (fixture) `QualifiedSourceID`s must never be
treated as reconnecting to each other's Listings or pins.

## What already exists in the app that you must not silently duplicate or break

`MangaCarta/Services/SourceRegistry.swift` and `MangaCarta/Services/SourcePreferenceStore.swift`
are today's compiled-Source registry and per-Work source pin, keyed by plain `String` source ids
(`MangaDexSource.sourceID`, `WeebCentralSource.sourceID`) — not by `QualifiedSourceID`, because no
installed-Extension Source exists yet on `main`. Read both files before deciding your data model.
You are not required to migrate these to `QualifiedSourceID` or to make installed Extensions and
compiled Sources share one registry — that is a larger integration decision for whoever wires the
installer in Phase 4, and is out of scope here per "Scope boundary" below. What you must not do is
build a second, parallel notion of "pin" or "Listing ownership" that silently disagrees with
`SourcePreferenceStore`'s existing per-Work choice semantics (documented in its own header comment:
a Work id maps to a pinned `ListingKey`, and the pin "outranks both the ranking and the primary
source"). If your lifecycle model needs a `ListingKey`-shaped reference, reuse that type rather than
inventing a second one.

## Traps

- **Reinstall is not "the same JSON declaration comes back."** A Source can be reinstalled with a
  different `name`, `engine`, `configuration`, or `capabilities` — `validateUpdate` allows all of
  those to change — and reconnection must still succeed as long as `qualifiedId` (and therefore
  `localId`, since the validator also pins that) is unchanged. Test reconnection with a
  deliberately *different* declaration body, not just a byte-identical resubmission.
- **Disablement is not uninstall.** Both "unregister the Source but preserve Listings, pins, and
  bounded Source storage," but the spec treats them as distinct lifecycle states with the same
  preservation guarantee, not one collapsed state. Model them as what they are, even if your first
  version's transition logic is the same for both — a future slice may need to tell them apart.
- **"Preserves" includes bounded Source storage**, which is S5's `host.storage` capability
  (criterion 6's storage half, not merged as of this writing — see S6's brief for the current
  state). You are not implementing storage itself; you are asserting the *lifecycle contract*
  that storage keyed by a `QualifiedSourceID` is untouched by disable/uninstall/reinstall. If S5
  is not yet merged when you start, write this part of your test against a fake/mock conforming to
  whatever seam S5 exposes for storage — do not block your whole slice on S5's merge, since your
  declared dependency is S1 only.
- **A missing or unrecognized `adult` classification still prevents registration** (§12, enforced
  by S1) — do not let a reconnection path bypass that by skipping `SourceDeclarationValidator`
  entirely. Reconnection revalidates the incoming declaration; it does not trust a cached one
  blindly.
- Section §11 leaves stable identity **across URL moves, forks, and signing-key rotation**
  explicitly open (evidence gate 3, §16) — that is a repository-format problem, not yours. Your
  slice's contract is scoped to identity that is already stable (an unchanged qualified id); do not
  attempt to solve gate 3, and say so if you find yourself tempted to.

## Scope boundary

You build and test the lifecycle contract: given a `QualifiedSourceID`, disable it, uninstall it,
reinstall it (same id, possibly different declaration body), and prove Listings/pins/storage
references keyed by that id survive and reconnect, while an unrelated Source sharing only a
`localId` never does. You do **not** build the installer, the repository format, or package
signing (Phase 4); you do not migrate `SourceRegistry` or `SourcePreferenceStore` off their current
`String`-keyed model; you do not implement `host.storage` (S5) or port WeebCentral (S6). If your
lifecycle model needs a capability none of those provide yet, model the seam and say so in the PR
body rather than building the missing piece yourself.
