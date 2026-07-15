# Handoff — Extension System Phase 2 (Cloudflare WebView + WeebCentral)

**Audience:** a fresh implementing session (run the hard `WebViewService` work on the
**Fable** model). This file is self-contained — you should not need the prior chat.

## Mission

Build **Phase 2** of the app's own extension system: a Cloudflare-bypassing
`WKWebView` service that also extracts HTML, and **WeebCentral** as the first real second
source. When done, the Settings source picker shows **MangaDex + WeebCentral**, and you can
browse/search/read WeebCentral end-to-end.

## Start here

1. `git checkout feature/extension-system-phase-2` (already exists; the spec is committed there).
2. **Read the spec — it is authoritative:**
   `docs/superpowers/specs/2026-07-15-extension-system-phase-2-design.md`.
3. Skim the roadmap memory for the whole initiative:
   `~/.claude/projects/-Users-eliasmagdaleno-xcode-Manga-Reader/memory/multi-source-roadmap.md`.
4. Run **superpowers:writing-plans** to turn the spec into a task-by-task Phase 2 plan
   (save to `docs/superpowers/plans/2026-07-15-extension-system-phase-2.md`).
5. Execute with **superpowers:subagent-driven-development**. Run the `WebViewService`
   implementation task on **Fable**; the source/mapping/registration tasks can be cheaper
   models. There's an SDD progress ledger at `.superpowers/sdd/progress.md` — append a new
   section for this plan.

## Repo state (as of 2026-07-15)

- `main` has: source-abstraction layer, reader image cache, and **Phase 1** (all merged at
  commit `25a11ec`; builds clean).
- Branch `feature/extension-system-phase-2` = main + the Phase 2 spec (commit `b98001a`).
- No Phase 2 code exists yet.

## Architecture you're extending

Data flow: `MangaSource` (protocol) → `@MainActor ObservableObject` view models → SwiftUI.

- **`Models/MangaSource.swift`** — the source contract: `id`, `name`, `isNSFW` (default
  false), `search / popular / newTitles / latestUpdates / mangaDetail / chapters /
  pageURLs`. `newTitles`/`latestUpdates` have default impls that throw
  `SourceError.unsupported`. Bridge-friendly (data in/out) on purpose.
- **`Services/SourceRegistry.swift`** — `@MainActor` singleton (`.shared`, injectable
  `init(sources:)`). `active`, `source(id:)`, `source(for: manga)` (routes by
  `manga.sourceId`), `visibleSources(includeAdult:)`. Persists `activeSourceID`.
- **`Models/MangaDexSource.swift`** — source #1 (thin adapter over `MangaDexAPI`).
- **`Manga`** carries `sourceId: String` (stamped at decode). `LibraryItem`/`ReadingEntry`
  persist an optional `sourceId` (nil → "mangadex"), so saved items already reopen via
  `source(for:)`.
- **Image loading** goes through `Services/ImageCache.swift` + `CachedAsyncImage` (memory+
  disk, current-chapter prefetch). WeebCentral serves plain image URLs → this works as-is.

### What Phase 2 adds (per the spec)

1. **`Services/WebViewService.swift`** — `WebViewExtracting` protocol +
   `@MainActor final class WebViewService`. `extract<T: Decodable>(from:script:as:) async
   throws -> T`: load `url` in a reused off-screen `WKWebView` (persistent
   `WKWebsiteDataStore` so `cf_clearance` survives; consistent UA — cf_clearance is
   UA-bound); if a Cloudflare interactive challenge is detected, surface the WebView for the
   user to solve, else run `script` (JS ending in `JSON.stringify(...)`) via
   `evaluateJavaScript`, parse → `JSONDecoder().decode(T)`. Serialize navigations (one load
   at a time). Typed errors. **This is the Fable task.**
2. **`Services/SourceContext.swift`** — `struct SourceContext { let webView: WebViewExtracting }`.
   `SourceRegistry` builds one shared context and passes it to source inits; `MangaDexSource`
   takes an ignored context (or keep a no-arg convenience init).
3. **`Models/WeebCentralSource.swift`** (+ small DTOs / JS scripts) — `MangaSource` with
   `id="weebcentral"`, `name="WeebCentral"`, `isNSFW=false`; each method builds a URL, calls
   `context.webView.extract(...)`, maps JSON DTOs → domain types (stamp
   `sourceId="weebcentral"`).
4. **Register** `WeebCentralSource(context:)` in `SourceRegistry.shared.sources`.

## WeebCentral facts (researched — verify selectors against live HTML)

Domain `https://weebcentral.com`. All **server-rendered HTML** (no JSON API):

| Purpose | URL |
|---|---|
| Homepage / latest | `/` , `/latest-updates/{page}` |
| Details | `/series/{mangaId}` |
| Chapter list | `/series/{mangaId}/full-chapter-list` |
| Chapter images | `/chapters/{chapterId}/images?reading_style=long_strip` |
| Search | `/search?text=…` (+ genre/status/order filters — DEFER filters) |

- **Cloudflare** is signaled by a `cf-mitigated: challenge` response header. A real WKWebView
  clears non-interactive JS challenges automatically; only interactive Turnstile needs a user
  tap — surface the WebView then.
- Content rating **EVERYONE** (no NSFW gating needed; the adult toggle is for private-source, Phase 3).
- Chapter page images are **plain image URLs** (no scrambling) → return `[URL]` normally.

## Testing strategy

- `WebViewExtracting` is a protocol → test `WeebCentralSource` with a **`MockWebView`**
  returning canned JSON per `(url, script)`; assert URL construction + DTO→domain mapping
  (search, details, chapters, page URLs, `sourceId=="weebcentral"`).
- Unit-test pure helpers (URL building, DTO decoding) with fixture JSON.
- `WebViewService` itself: **verified live**, not in unit tests.

## Verification (end-to-end, live)

Build for **iPhone 17** sim; unit tests (mock-webView source tests) pass; then live: Settings
→ pick WeebCentral → Home browses it → open a title → detail → open a chapter → reader pages
load (through the image cache); if a CF challenge appears, the WebView surfaces for a tap.
Confirm switching back to MangaDex works and a saved WeebCentral bookmark reopens via WeebCentral.

## Project conventions & gotchas

- **Pure SwiftUI + Foundation. NO third-party deps / package managers.** (This is why we use
  WebView JS extraction instead of an HTML parser.)
- **Synchronized Xcode groups** — files in `Models/`, `Services/`, `Components/` auto-compile
  (no `project.pbxproj` edits). **`Views/` is NOT synchronized** — a new file there needs 4
  pbxproj edits, so prefer adding to existing Views files or put new types in the synchronized
  groups. All Phase 2 new files land in `Models/`/`Services/` → no pbxproj edits.
- After any build, Xcode may **cosmetically reshuffle `project.pbxproj`** (reorders two
  existing entries). If `git status` shows it, `git checkout -- Manga-Reader.xcodeproj/project.pbxproj`.
- Build: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Unit tests (the UI-test target's runner is flaky here — scope to unit target):
  `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:Manga-ReaderTests`
  Builds/tests take a few minutes; be patient (don't chain short sleeps).
- **Commit trailers** — every commit ends with:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_019uB9Pu9FgykTjHDjJt2QDV
  ```
  (If a different session id applies, use the current one.)
- Stateful-store tests use an isolated `UserDefaults(suiteName: "test.…\(UUID())")`.

## Reference extensions (technique only — never copy code or match their API)

Paperback (iOS) WeebCentral extension shows the endpoints, DOM selectors, and CF detection:
`inkdex/general-extensions/src/WeebCentral/{network.ts,parsers.ts,models.ts}` (GitHub). Read
`parsers.ts` for the DOM selectors to port into your JS extraction scripts, then **verify
against live weebcentral.com HTML** — selectors are the most volatile part.

## Scope boundaries

- **This phase:** WebViewService + SourceContext + WeebCentralSource (browse/search/details/
  chapters/read) + registration.
- **Deferred:** private-source (Phase 3), comix.to descrambler + JS-signing (Phase 4), JS-loadability
  (Phase 5); within WeebCentral: advanced search filters, settings form, `SourceContext.net`/
  `storage`.
