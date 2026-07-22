# Handoff — "More Like This" (subsystem 3) mid-execution

**Date:** 2026-07-22
**Audience:** a fresh session resuming the subagent-driven execution of this feature. Self-contained — you should not need the prior chat.

## TL;DR — where to resume

Tasks 1–4 of a 6-task plan are **implemented, committed, and review-approved** on branch
`feature/more-like-this`. **Resume at Task 5** (view model + detail-page rail), then Task 6
(debug probe + live UI tests), then finish the branch.

Working tree is **clean**. HEAD is `50916ea`. Do NOT re-run Tasks 1–4 — trust the ledger
and `git log`.

## What this feature is

Subsystem 3 (final piece) of the cross-source recommendations effort: a Netflix-style
**"More Like This" rail on the manga detail page**, sourced from MyAnimeList per-title
`recommendations` and reverse-resolved to openable MangaDex titles. Subsystems 1 (read-only
MAL client) and 2 (cross-source entity resolution) are already merged to `main`.

- **Spec:** `docs/superpowers/specs/2026-07-21-more-like-this-design.md`
- **Plan (the source of truth for execution):** `docs/superpowers/plans/2026-07-21-more-like-this.md`

## Execution method in use

**superpowers:subagent-driven-development** — one fresh implementer subagent per task, a
task reviewer (spec + quality) after each, then a whole-branch review at the end. Progress
ledger at `.superpowers/sdd/progress.md` is the durable record — read it first on resume.

Conventions that have worked this run:
- **Implementers:** the plan contains complete code, so tasks are transcription + testing.
  Used **haiku** for pure/mechanical tasks (1, 2, 3) and **sonnet** for the
  integration/concurrency task (4). Task 5 (SwiftUI view wiring) → haiku or sonnet; Task 6
  (debug probe + two live UI tests) → sonnet (it's judgment-y and network-dependent).
- **Reviewers:** **sonnet** for small diffs; **opus** for Task 4 (concurrency stakes). Task 5
  → sonnet; Task 6 → sonnet.
- Each implementer dispatch: give it its **task brief file path** (generated via
  `scripts/task-brief PLAN N`), the interfaces from prior tasks it depends on, the global
  constraints, and a **report file path**. Templates are in the SDD skill dir
  (`implementer-prompt.md`, `task-reviewer-prompt.md`). Generate the review package with
  `scripts/review-package BASE HEAD` and hand the reviewer the printed path.
- SDD skill scripts dir:
  `/Users/eliasmagdaleno/.claude/plugins/cache/claude-plugins-official/superpowers/6.1.1/skills/subagent-driven-development/scripts/`

## Ledger state (verbatim intent)

| Task | Status | Commit range |
|------|--------|--------------|
| 1 — `MALTitleMatcher.bestMatch<ID>` generic | ✅ complete, review clean | `d4e4d9d..75fc5c2` |
| 2 — `MoreLikeThis.pickMatch` pure helper | ✅ complete, review clean | `75fc5c2..9023612` |
| 3 — reverse cache in `EntityResolutionStore` | ✅ complete, review clean | `9023612..a960e89` |
| 4 — `MoreLikeThisProvider` orchestration | ✅ complete, review clean | `a960e89..50916ea` |
| 5 — `MoreLikeThisViewModel` + detail rail | ⬜ **NEXT** | — |
| 6 — debug probe + live UI verification | ⬜ pending | — |

Baseline commit (branch start, off local `main`): `d4e4d9d` (which also holds the plan).

## Immediate next step (Task 5)

The **current, correct Task 5 brief already exists** at `.superpowers/sdd/task-5-brief.md`
(regenerate with `scripts/task-brief docs/superpowers/plans/2026-07-21-more-like-this.md 5`
if in doubt). Task 5:

1. Create `Manga-Reader/Manga-Reader/Models/MoreLikeThisViewModel.swift` — `@MainActor
   ObservableObject`, `@Published private(set) items/isLoading`, idempotent
   `load(for manga:) async` (guards on `manga.id` so repeat `.task` calls are no-ops),
   backed by `MoreLikeThisProvider` (Task 4, default init uses `EntityResolutionStore.shared`).
2. Edit `Manga-Reader/Manga-Reader/Views/MangaDetailView.swift` — add `@StateObject private
   var moreLikeThis = MoreLikeThisViewModel()`, append a `moreLikeThisRail` section **last**
   in the body `VStack` (after `chapters`), gated `if !moreLikeThis.items.isEmpty`, and a
   `.task { await moreLikeThis.load(for: manga) }`. The rail is `InkSectionHeader("More Like
   This", eyebrow: "Similar titles")` + `MangaRail(items:)` — both apply their own
   `.padding(.horizontal, Gutter.page)`, so no extra padding (matches the `description`/
   `chapters` sections). `MangaRail` already builds `NavigationLink(destination:
   MangaDetailView(manga:))` per card.
3. Verify with a **build** (not a unit test — this is view wiring):
   `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' build`
   → `** BUILD SUCCEEDED **`. Commit.

The brief has the exact code. After the implementer reports DONE, run the review loop
(review-package → sonnet reviewer), update the ledger, then Task 6.

## ⚠️ Stale SDD artifacts — regenerate, don't trust

`.superpowers/sdd/` is shared scratch and contains **leftover files from earlier subsystems**
(subsystem 2 had 9 tasks). These are NOT for this feature:
- `task-5-report.md` — STALE ("MALEntityResolver" from subsystem 2). No Task 5 report has
  been written yet for *this* feature; the implementer will overwrite it.
- `task-6-brief.md` / `task-6-report.md` / `task-7..9` — STALE. **Regenerate the Task 6
  brief fresh** from the plan: `scripts/task-brief docs/superpowers/plans/2026-07-21-more-like-this.md 6`.
- The many `review-*.diff` files are prior-run packages; ignore.

`task-1..4-brief.md`/`report.md` and `progress.md` ARE current for this feature.

## Task 6 preview (after Task 5)

Extend the throwaway `MyAnimeListDebugView` with a "More Like This" probe field (types a
title → runs `MoreLikeThisProvider().recommendations(for:)` on a synthetic MangaDex `Manga`
with `malId: nil` → lists resolved titles), then add **two live UI tests** against the real
MAL + MangaDex APIs: the probe (`testMoreLikeThisDebugProbeLiveVerification`, types "Berserk",
asserts ≥1 `mltResultRow_*`) and the real detail-page rail
(`testMoreLikeThisDetailRailLiveVerification`, opens a Home title, scrolls to bottom, asserts
the "More Like This" header + ≥1 `mangaCoverCard`). Full code is in the plan's Task 6.

## Verification conventions (unchanged, important)

- **Always iPhone 17 simulator** (no iPhone 16 on this machine — the plan's CLAUDE.md example
  is outdated; use 17) with **`-parallel-testing-enabled NO`** (user dislikes cloned sim
  instances — see `no-parallel-test-clones` memory).
- **SourceKit/LSP false alarms:** standalone diagnostics like "No such module 'XCTest'" and
  "Cannot find type 'Manga'/'MALTitleMatcher' in scope" fire constantly because the indexer
  can't resolve module-internal types. **Judge correctness ONLY by the `xcodebuild` run**,
  never the diagnostics.
- Live UI tests are network-dependent and slow; MAL soft-rate-limits (HTTP 429, app retries
  once). A flake there is API availability, not a logic bug — re-run after a pause.

## Gotchas already navigated (so you don't re-hit them)

- **`nonisolated` on `topRecommendations`** (Task 4): a `static` member of a `@MainActor`
  class is actor-isolated by default, which broke synchronous test calls. The implementer
  added `nonisolated`; the opus reviewer confirmed it correct and behavior-preserving. Any
  new pure static on a `@MainActor` type needs the same.
- **App sources live under `Manga-Reader/Manga-Reader/…`** (double nesting), e.g.
  `Manga-Reader/Manga-Reader/Services/MoreLikeThisProvider.swift`. The plan's paths omit the
  second segment in places — the briefs are corrected. `Services/` and `Models/` are Xcode
  synchronized groups (auto-compiled, no `project.pbxproj` edit). `MangaDetailView.swift` and
  `MyAnimeListDebugView.swift` already exist, so editing them needs no pbxproj change either.
- **Reverse cache keyed `String(malId)`**, `EntityResolutionStore.missTTL` stays
  `nonisolated static let`, `EntityResolutionStore.shared` is the app-wide instance the
  provider defaults to.

## Open Minor findings (for the final whole-branch review to triage — none block)

- **T1:** `testMALBestMatchRejectsAmbiguousAndBelowThreshold` bundles 4 scenarios in one
  method (plan-mandated); opaque on regression.
- **T2:** `pickMatch` first-wins on a `malId` collision (untested/unstated); no near-tie
  fuzzy-boundary test — both outside brief scope.
- **T3:** `ReverseResolution.isFresh` duplicates `MALResolution.isFresh` (plan-mandated
  mirror); stale-miss retry not tested through the store (inherited pattern).
- **T4:** self-drop `resolved.id != manga.id` only catches self when the source manga is
  MangaDex-sourced (theoretical edge; rec surface is MangaDex-only).

## Finishing (after Task 6 review is clean)

1. Run the **full unit suite** as a regression gate:
   `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:Manga-ReaderTests` (expect the pre-existing 144 + new pure tests).
2. Dispatch the **whole-branch review** (opus) via superpowers:requesting-code-review's
   `code-reviewer.md`, packaged with `scripts/review-package $(git merge-base main HEAD) HEAD`;
   feed it the open Minor findings above to triage.
3. **superpowers:finishing-a-development-branch** — merge to `main` AND push to origin
   (subsystem 2 was merged+pushed; match that).

## Cleanup owed (deferred — NOT this branch, per spec YAGNI)

Leave the throwaway `MyAnimeListDebugView` + its live UI tests (subsystem 2's two, plus
Task 6's new probe test) in place. Retiring the debug screen is a later cleanup once the real
rail is proven. The permanent feature is the detail-page rail +
`testMoreLikeThisDetailRailLiveVerification`.

---
*Note: a separate `/doctor` run happened this session and enabled auto mode as the default
permission mode (`~/.claude/settings.json` → `permissions.defaultMode: "auto"`). Unrelated to
this feature; mentioned only so it isn't a surprise.*
