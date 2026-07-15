# Our Own Extension System — Design

Date: 2026-07-14

## Context

The app is a MangaDex reader that, as of the source-abstraction work
(`2026-07-14-source-abstraction-design.md`), talks to a `MangaSource` protocol with
MangaDex as source #1. The goal now is **multiple real sources** — starting with the two
the user named, **comix.to** and **private-source** — on the way to the original vision: "an
extension system that functions like Aidoku and Paperback."

### What research into those two sources revealed

Both are Paperback (iOS) extensions in the community repos the user provided
([inkdex/general-extensions](https://github.com/inkdex/general-extensions),
[karrot0/KakarotExtension](https://github.com/karrot0/KakarotExtension)). Reading them
showed they are **not standalone JSON clients** — they ride the Paperback *runtime*:

- Both declare `SourceIntents.CLOUDFLARE_BYPASS_PROVIDING` — the Paperback app solves the
  Cloudflare JS challenge in a WebView and hands the `cf_clearance` cookie to the source.
- **comix.to** uses `Application.executeInWebView(...)` to load the page, let *the site's
  own JS* sign API requests and decrypt `{e:"blob"}` responses, and captures the plaintext
  by proxying `JSON.parse`. Its page images are **scrambled** (5×5 tile Fisher–Yates
  shuffle keyed by `X-Scramble-*` headers, optional byte-XOR) and must be **descrambled
  on-device from the decoded bitmap**.
- **private-source** needs the Cloudflare cookie + a ~200-line image request throttler (429/503
  backoff); its images are plain (no scramble). Its main extension was dropped from the
  major Tachiyomi repo, confirming it's a hostile, moving target.

So "port these two" really means "reimplement chunks of the Paperback runtime": a
Cloudflare-bypass WebView, a JS-in-WebView executor, HTML parsing, request interception/
throttling, an image byte-transform pipeline, plus the per-source logic.

### Decisions (agreed with the user)

- **Build our own extension system, not Paperback/Aidoku compatibility.** Their code is a
  *reference* for how to beat the hard problems (CF, signing, descrambling), not an API to
  match. Rationale: Paperback's runtime is closed and unversioned; matching it is a
  reverse-engineering treadmill. Owning the contract means only a *site* change can break a
  source — the same risk everyone has.
- **Native Swift sources first, JavaScriptCore (hot-loadable JS) layer last.** We'll debug
  Cloudflare and a tile-descrambler in Swift with real breakpoints, then wrap the proven
  host services in a JS bridge. Same destination, earned in the safe order.
- **The spine is a reusable WKWebView host service.** Every real manga host needs at least
  one of: Cloudflare bypass, HTML parsing, or JS-driven APIs — all of which a WKWebView
  (load page → pass CF → persist cookie → run injected JS → capture result) provides. That
  one service, grown across phases, unlocks all three.
- **Adult sources gated, default OFF.** Sources carry an `isNSFW` flag; a Settings toggle
  hides them from the picker unless enabled.
- **High-difficulty implementation subtasks run on the Fable model** via subagents (CF
  WebView, descrambler + JS-signing capture, JS runtime).

## Architecture: the SDK

A "source" is a thin object; the hard work lives in **host services** the app provides.

- **`MangaSource`** (exists) — the source contract: `search / popular / newTitles /
  latestUpdates / mangaDetail / chapters / pageURLs`, plus `id` / `name`. Gains `isNSFW`.
- **`SourceContext`** (new) — the host-services object injected into each source. Grows by
  phase: Phase 1 provides networking (a reusable JSON-GET helper) + per-source key-value
  storage; later phases add the WKWebView service, HTML extraction, the CF cookie store,
  and the image-transform pipeline.
- **`SourceRegistry`** (exists) — owns registered sources + the active browse source;
  resolves a manga's own source by `sourceId`; persists the active id.

Sources never touch global singletons or `MangaDexAPI` directly — they use their
`SourceContext`. This is what makes them portable to the JS layer later (the JS bridge just
exposes the same `SourceContext` services to JavaScriptCore).

## Phase roadmap

Each phase ships and is verifiable on its own; each hard host capability is built once in
the phase that first needs it, then reused (including by the JS layer in Phase 5).

1. **SDK + multi-source plumbing** ← *this spec details this phase*. `SourceContext`;
   `isNSFW` + "Show adult sources" toggle; `sourceId` in persistence (+ migration); source
   picker. Validated with the existing `MockSource` in tests + a live picker/persistence
   check. No new real source, no Cloudflare — get the machinery correct and clean.
2. **CF-bypass WKWebView + HTML extraction → WeebCentral.** The first real second source
   (popular, Cloudflare + HTML scrape, but no scramble/signing — the gentlest full source).
   Builds the WebView spine.
3. **private-source.** Reuses the CF WebView; adds gallery→single-chapter mapping, NSFW gating in
   practice, and image-request throttling. JSON API (no HTML parser needed).
4. **comix.to.** Extends the WebView service with JS-signing/decryption capture, adds the
   5×5 tile descrambler and a byte-transform image pipeline (`pageURLs` evolves so a page
   can be a fetch-and-transform descriptor, not just a URL). The heaviest infra, last.
5. **JS-loadability (JavaScriptCore).** Expose the proven `SourceContext` services to a JSC
   bridge; define the JS source format; sources become hot-loadable. Later: an
   install/update repo.

## Phase 1 — detailed design

**Goal:** make the extension system real and the app genuinely (and correctly)
multi-source, with zero Cloudflare/scraping risk, so the picker/persistence/NSFW machinery
is nailed before the hard phases.

### 1. `SourceContext` (host services) — `Services/SourceContext.swift` (new)

Injected into each source. Phase 1 surface:

- `net` — a reusable JSON-GET helper factored out of `MangaDexAPI.request` (URL building,
  User-Agent, 429 retry, `.convertFromSnakeCase` decode). MangaDex keeps its own base URL;
  the helper is generic over base URL + path + query.
- `storage` — a per-source key-value store (namespaced by `source.id`) over `UserDefaults`,
  for future source settings.

`MangaDexSource` is refactored to take a `SourceContext` and route network calls through
`net` (behavior-preserving). `SourceRegistry` constructs sources with a shared context.

### 2. `isNSFW` + adult gating

- Add `var isNSFW: Bool { get }` to `MangaSource` (default `false` via protocol extension).
  `MangaDexSource.isNSFW == false`.
- A `@AppStorage` "Show adult sources" flag (default `false`) in Settings.
- The **source picker** lists only sources where `!isNSFW || showAdultSources`.

### 3. `sourceId` in persistence (+ migration)

- Add `sourceId: String` (optional in the Codable init, **defaulted to `"mangadex"`**) to
  `LibraryItem` and `ReadingEntry`. Backward-compatible: existing rows lacking the key
  decode as MangaDex. Mirrors the existing `chapterNumbers: [String]? = nil` pattern.
- `LibraryStore.toggle` / `HistoryStore.record` persist `manga.sourceId`.
- `BookmarksView` / `HistoryView` reconstruct `Manga` with the **stored** `sourceId`
  instead of the current hardcoded `MangaDexSource.sourceID`. This fixes the latent bug
  where a non-MangaDex saved item would reopen through the wrong source.
- `LibraryStore.refresh` resolves each item's source via
  `SourceRegistry.shared.source(id: item.sourceId)` instead of always the active source.

### 4. Source picker — `Views/SettingsView.swift` (+ a small picker view)

- A section in Settings listing eligible sources with the active one checked; selecting one
  sets `SourceRegistry.shared.activeSourceID`. Home's browse feeds already read
  `SourceRegistry.shared.active`, so switching re-sources Home on next load.
- `SettingsView` is currently a stub; this is its first real content. (Note: `Views/` is
  **not** a synchronized group — any new file under `Views/` needs the four `project.pbxproj`
  edits per CLAUDE.md. Prefer adding the picker inline in `SettingsView.swift` to avoid that.)

### 5. Files

- New: `Services/SourceContext.swift` (synchronized group — no pbxproj edit).
- Modify: `Models/MangaDexAPI.swift` (extract the generic JSON-GET into the context's `net`
  helper; `MangaDexAPI.request` becomes a thin wrapper over it so behavior is unchanged),
  `Models/MangaSource.swift` (`isNSFW`), `Models/MangaDexSource.swift` (take context,
  `isNSFW`), `Services/SourceRegistry.swift` (build context; already resolves by id),
  `Services/LibraryStore.swift` + `Services/HistoryStore.swift` (persist/read `sourceId`),
  `Views/BookmarksView.swift` + `Views/HistoryView.swift` (use stored `sourceId`),
  `Views/SettingsView.swift` (picker + adult toggle).

### Testing (TDD)

- `MockSource` gains `isNSFW`; add an NSFW mock. Test the picker's eligibility filter
  (adult hidden unless toggle on).
- `LibraryItem` / `ReadingEntry` decode legacy JSON (no `sourceId`) as `"mangadex"`; encode/
  decode round-trips a non-mangadex `sourceId`.
- `LibraryStore.refresh` resolves per-item source by `sourceId` (via injected registry).
- Existing MangaDex + source-abstraction tests stay green.

### Verification (end-to-end)

1. Build for iPhone 17 simulator.
2. Unit tests pass (existing + new).
3. Live: Settings shows the picker (MangaDex only, since it's the sole non-NSFW source);
   toggling "Show adult sources" changes nothing yet (no adult source); Home browses via the
   active source; saving a title to Library persists `sourceId: "mangadex"` and reopens
   correctly. (Full multi-source switching is exercised for real in Phase 2 with WeebCentral;
   Phase 1's cross-source logic is covered by unit tests with mocks.)

## References (for later phases)

- comix.to technique reference: `inkdex/general-extensions/src/Comix` (`utils/webView.ts`,
  `utils/descramble.ts`, `utils/decryptImage.ts`, `network.ts`).
- private-source technique reference: `karrot0/KakarotExtension/src/private-source` (`interceptors.ts`,
  `main.ts`, `model.ts`).
- WeebCentral reference: `inkdex/general-extensions/src/WeebCentral` (`parsers.ts`,
  `network.ts`).

These are used only to learn *how* each challenge was solved; no code or API is copied or
matched.
