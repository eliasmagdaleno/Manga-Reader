# ADR-0003 — Extensions are JavaScript: JavaScriptCore for logic, WKWebView for fetching

- **Status:** Accepted in principle (2026-07-24); host API undesigned. **Amendment 1 below
  narrows "ship zero built-in aggregator sources": MangaDex stays built in as the resolution
  bridge, and extensions are additive.**
- **Related:** ADR-0001, ADR-0002, ADR-0004, ADR-0016, ADR-0022

## Context

The goal is user-installable sources, in the shape Paperback and Aidoku have — the app ships as
an empty reader and the user adds source extensions themselves. Distribution target is the **App
Store, plus TestFlight for other users**, which constrains the design more than the engineering
does.

iOS forbids shipping executable code downloaded after review: no dylibs, no JIT. The established
workaround, and the reason both comparable apps look the way they do, is an **interpreter plus a
defined host API** — interpreted content is not executable code for guideline purposes. Paperback
runs JavaScript; Aidoku runs WebAssembly.

The codebase is already most of the way here, by earlier design rather than by accident:

- `MangaSource` was deliberately written bridge-friendly — "every parameter is an `Int`/`String`
  and every return value is a value/Codable domain type … keeps the door open for a future
  dynamic-extension runtime (JS/WASM)" (`MangaSource.swift`).
- `WebViewService` already loads a page in a shared off-screen `WKWebView`, injects a JS script
  whose final expression is a `JSON.stringify(...)`, and decodes the result into Codable DTOs.
- **`WeebCentralSource` is effectively a hardcoded JavaScript extension already** — its
  per-page extraction scripts are co-located raw strings, explicitly noted as "the volatile part
  when the site redesigns."

## Decision

**Two substrates, one extension model.**

- **JavaScriptCore runs extension logic** — parsing, URL construction, mapping a site's shape
  onto `MangaSource`. It is a system framework, needs no WebView, and bridges cleanly to the
  `String`/`Int`-in, Codable-out contract `MangaSource` already has.
- **`WKWebView` performs fetches that require being a browser.** This is not an optimization:
  Cloudflare-protected sources can only be fetched by something with real cookies, a real TLS
  fingerprint, and a real DOM. `WebViewService` already holds `cf_clearance` in a persistent data
  store and surfaces interactive challenges.

An extension is therefore **one kind of thing** (a JS bundle) with **two fetch strategies**
available to it — plain HTTP, or via the WebView — chosen per request by the extension, not two
different extension formats.

WebAssembly is rejected: strongest sandboxing, but the worst authoring experience, and the
authoring cost is paid on every source written.

## Consequences

- **The host API is the real work, and it is a forever contract.** The functions exposed to
  extension code — `fetch`, `fetchViaWebView(url, script)`, `log`, `storage`, and the
  `MangaSource`-shaped entry points — cannot be broken once third-party extensions exist.
  Extension systems die of API churn far more often than of engine choice. **Undesigned; this
  ADR does not decide it.**
- **Ship zero built-in aggregator sources.** The app is an empty reader; the user adds extension
  repos. This follows from the distribution target: copyright complaints, not guideline 2.5.2,
  are the more common takedown vector for reader apps. It also means the **extension installer
  and repo format are day-one features**, not a later addition.
- `WeebCentralSource` becomes the migration proving-ground: porting it from a compiled Swift
  source to a JS extension validates the host API against a real, Cloudflare-protected site.
- A JS layer sits between the app and every source — new failure modes (script errors, bad
  extension output) that the typed Swift sources cannot currently produce.

## Sequencing

This ADR is **third** in the build order, deliberately. Per ADR-0001 and ADR-0002, Work/Listing
identity is buildable today against the two existing sources, and the extension system exists to
make that identity *pay off at scale*. Building extensions first, before Works exist, means every
new source multiplies duplicate entries with nothing to reconcile them.

## Amendment 1 — MangaDex stays built in (2026-08-31)

"Ship zero built-in aggregator sources" above is **narrowed**: the app ships with MangaDex
registered, and the empty-reader posture applies to every *other* source.

The reason is not convenience. ADR-0016 makes MangaDex the **resolution bridge** — it is the one
source whose entries carry `links.mal`, which is what lets the app know that a title here and a
title there are the same manga. For You, More Like This and MyAnimeList progress sync are all
built on top of that bridge. An install with no MangaDex is not an empty reader; it is a reader
with recommendations that silently return nothing and a MAL list that never moves, and the reader
has no way to know that installing one particular extension is what would fix it.

The original consequence was reasoned from a takedown argument — copyright complaints being the
likelier vector for reader apps than guideline 2.5.2. That argument still stands, and this
amendment does not weaken it: MangaDex is an API with public documentation and a required
attribution, which the app carries, and it is the source the app is already named around in its
own README.

So **extensions are additive**. The built-in set is the bridge and nothing more; everything a
reader adds, they add themselves. If the bridge is ever replaced — a metadata provider that does
not need a chapter source attached — this narrowing should be revisited rather than inherited.

This was decided during the fulfillment work and recorded only in a session handoff, which under
`CLAUDE.md`'s document-ownership rule is not a record at all: handoffs are archived, and archived
handoffs are explicitly never to be worked from. Phase 2's host API design will amend this ADR
again, and that amendment should assume MangaDex is present.

## Amendment 2 — the Host API is declarative, capability-based, and configuration-first (2026-09-02)

The substrate decision above stands. This amendment settles the architectural boundary that the
original ADR deliberately left undesigned. The versioned wire contract is specified in the
[Phase 2 Host API design](../superpowers/specs/2026-09-02-host-api-design.md); this amendment owns
the decisions and their reasons.

### Context

The first extension cannot define the architecture by accident. Paperback's catalog evidence shows
that most sources are instances of reusable site themes: 55 generic-theme sites and 23 bespoke
ones, with Madara alone accounting for 29 sites. A design in which every installed Source must be a
separate hand-written program would make configuration masquerade as code, multiply review and
update work, and prevent a theme fix from repairing every site that uses it.

The existing Swift seam also cannot simply be exported. It mixes discovery metadata, UI copy,
optional behavior inferred in several ways, Foundation values, source-specific pagination, and an
unbounded `throws` channel. `SourceContext` exposes no plain HTTP capability, while its WebView
capability accepts a Swift metatype and returns a decoded Swift value. Those are useful internal
seams, not a stable cross-runtime contract.

### Decision

**An Extension is an engine; a Source is a manifest-declared, configured instance of that engine.**
One installed bundle may declare many Sources and may apply one executable theme engine to many
configuration records. Source identity, display metadata, adult classification, supported
operations, language behavior, allowed origins, and presentation hints are declarative. The host
can therefore inspect, gate, and register a Source without executing untrusted code. Executable
entry points implement only the operations declared for that Source and receive its immutable
configuration as invocation context.

**The Host API is a versioned message boundary, not a projection of `MangaSource`.** Requests,
results, and failures cross as JSON-compatible values validated by the host. The host owns mapping
to Swift domain types, source-id stamping, input validation, URL policy, and user-facing error
copy. Optional behavior is declared, never discovered by calling code and waiting for an
unsupported error. Compatibility is negotiated from an Extension-declared Host API range; no
best-effort execution occurs when the ranges do not intersect.

**Host services are explicit capabilities with least authority.** Version 1 exposes plain HTTP,
browser extraction, bounded key/value storage, and redacted structured logging. Network access is
restricted to manifest-declared HTTPS origins. Browser identity and cookies are host-owned and
partitioned by Source plus origin; an Extension cannot set the browser user agent or access another
Source's browser state. Secrets and arbitrary filesystem access are not part of version 1.

**The host schedules and bounds all work.** Extensions may not create detached host operations.
Cancellation ends the invocation and invalidates later callbacks. HTTP concurrency, origin rate,
response size, browser occupancy, script time, and image prefetch width are host-enforced budgets;
manifest values are requests within host clamps, not authority. Exact numeric defaults are tuning
policy and require measurement, so they are not frozen into this ADR.

**Interactive browser work is foreground-only.** A background invocation that encounters a
challenge returns a distinct interaction-required outcome without presenting UI. A foreground
caller may retry and the host identifies the Source and origin before showing the browser. Decline,
timeout, cancellation, and background deferral remain distinct outcomes.

**Stable Source ids are repository-qualified and immutable.** The installer derives the installed
identity from repository identity plus the manifest's local Source id and rejects collisions.
Updates cannot rename that identity. Disablement or uninstall makes the Source unavailable without
rewriting Listings or pins; reinstalling the same qualified identity reconnects them. Replacement
by an unrelated repository is a different identity even if it uses the same local id.

**Adult classification is mandatory, declarative, and fail-closed.** A missing or invalid
classification prevents Source registration. Repository review may strengthen a declaration but
cannot weaken it; the host may also elevate a specific Listing when validated output marks it
adult. The trust and signing policy by which repositories earn review status belongs to the later
repository-format design and remains open until that evidence exists.

### Alternatives rejected

- **One program per Source.** Rejected because it duplicates generic-theme logic and makes one
  site configuration the unit of executable maintenance.
- **Export `MangaSource` directly.** Rejected because Swift defaults, metatypes, Foundation URLs,
  unconstrained errors, and source-specific paging do not form a stable language-neutral ABI.
- **Infer capabilities from exported functions or failures.** Rejected because the host must know
  what it may display and schedule before running extension code, and failure is not discovery.
- **Give extension code a general network/browser/filesystem object.** Rejected because origin,
  privacy, resource, and lifecycle policy would become unenforceable or depend on author
  cooperation.
- **Share one browser identity across Sources.** Rejected because cookies can carry authentication
  or tracking state and must not become an undeclared cross-extension communication channel.
- **Permit best-effort version mismatches.** Rejected because silent semantic drift is harder to
  diagnose and less safe than refusing an incompatible Extension with an actionable reason.
- **Trust `adult: false` as an optional author hint.** Rejected because that value controls source
  visibility and notification disclosure; absence cannot safely mean non-adult.

### Consequences

- Theme engines and their configurations can evolve independently: one engine fix can repair many
  Sources without inventing a new Host API operation.
- The runtime adapter will be deeper than a JavaScriptCore wrapper around `MangaSource`; it needs
  manifest validation, message validation, capability brokers, scheduling, and domain mapping.
- Existing compiled Sources remain internal adapters. MangaDex remains built in under Amendment 1;
  the WeebCentral port is the first conformance test for the external contract.
- Repository installation must establish repository identity, validate Source-id uniqueness, and
  define review/signing metadata. That work is deliberately sequenced after the Host API contract.
- Version 1 omits credentials and arbitrary cache files. Adding either later requires a new
  optional Host API capability rather than widening storage or network authority implicitly.
