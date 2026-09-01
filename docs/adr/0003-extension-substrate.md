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
