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
