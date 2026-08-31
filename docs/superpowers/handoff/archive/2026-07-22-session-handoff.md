# Session Handoff — 2026-07-22

**Audience:** a fresh session picking up this project. Self-contained — you shouldn't need the prior chat.

## TL;DR

Everything from this session is **merged to `main` and pushed** (`main` HEAD `5fb47f9`). Working
tree clean. No feature is mid-flight. The repo now has **CI + branch protection**, so all future
work goes through the PR flow (see "Operational rules" below — this is the biggest change to how
you work here).

## What shipped this session (all on `main`)

1. **More Like This (subsystem 3) — finished & merged.** Resumed from a mid-execution handoff at
   Tasks 5–6: `MoreLikeThisViewModel` + the detail-page "More Like This" rail, debug probe, and
   two live UI tests. Completes Phase 2 (MAL cross-source recs).
2. **Collapsible chapters — merged.** The detail page shows a 5-chapter preview + "Show all N
   chapters" → new `ChapterListView` (full list + sort + multi-select). Shared `ChapterRow`
   extracted to `Views/Components/`. Spec/plan in `docs/superpowers/{specs,plans}/2026-07-22-collapsible-chapters*`.
3. **CI (GitHub Actions) — merged.** `.github/workflows/ci.yml`: builds + runs the **unit suite
   only** (not the live UI tests) on push/PR to `main`. Required shared-scheme + Secrets.xcconfig
   handling (see gotchas).
4. **SwiftLint — merged.** `.swiftlint.yml` tuned to the codebase; runs as a second CI job.
5. **Branch protection on `main` — enabled.** Requires a PR + both CI checks green.
6. **For You + MAL blend — merged (PR #6).** Folded MAL collaborative signal into the "For You"
   home rail. Spec/plan in `docs/superpowers/{specs,plans}/2026-07-22-foryou-mal-blend*`.

## Operational rules now in force (READ THIS)

`main` is **branch-protected**. You **cannot push to `main` directly** — it's rejected. Every change:
```
git checkout -b some-branch → commit → git push → gh pr create → CI runs → both checks green → gh pr merge --rebase --delete-branch → git checkout main && git pull
```
- **Required checks** (must be green to merge): `Build & unit tests` and `SwiftLint`.
- PRs require **0 approvals** (solo-friendly) but the PR itself is mandatory.
- `enforce_admins: false` — the user (admin) retains a manual bypass, but use the PR flow.
- Config details + rationale live in the [[ci-on-main]] memory. To change protection: `gh api -X PUT repos/eliasmagdaleno/Manga-Reader/branches/main/protection`.
- The private `nhentai` branch never triggers CI (never pushed) — keep it that way (see [[nhentai-private-branch]]).

## CI gotchas (so you don't rediscover them)

- **Runner `macos-15`** (Xcode 16 matches project objectVersion 70; iOS 18 sims cover the 17.5
  target). Simulator is chosen dynamically in the workflow.
- **`Secrets.xcconfig` is gitignored** (holds `MAL_CLIENT_ID`) and is the app target's base config —
  CI recreates it with a placeholder (`MAL_CLIENT_ID = ci-placeholder`); unit tests never call MAL.
- **The `Manga-Reader` scheme is now shared** (`.xcodeproj/xcshareddata/xcschemes/`) so `xcodebuild`
  finds it on a clean checkout. Don't delete it.
- **SwiftLint is NOT preinstalled** on the runner — the workflow falls back to `brew install swiftlint`
  (prints harmless brew tap-trust noise; the job still passes). A lighter/cached setup is a possible
  future optimization.

## Build / test commands (local)

- Build: `xcodebuild -scheme Manga-Reader -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Unit tests: `… -parallel-testing-enabled NO test -only-testing:Manga-ReaderTests` (163 tests, ~4s)
- Lint: `swiftlint lint` (installed locally via brew; 0 error-severity, ~13 informational warnings)
- **Always iPhone 17 + `-parallel-testing-enabled NO`** (see [[no-parallel-test-clones]], [[ui-verification-technique]]).
- **Ignore SourceKit "cannot find type" / "No such module XCTest"** — indexer false alarms; judge by `xcodebuild` only.

## The "For You + MAL blend" (most recent feature — context for tuning/extension)

`RecommendationEngine → CompositeCandidateProvider → { TagCandidateProvider, MALCandidateProvider → MoreLikeThisProvider }`
- `TasteProfile.seeds` = top-5 read/saved manga by the existing per-manga engagement weight.
- `MALCandidateProvider` (`Models/CandidateProvider.swift`) scores per-seed MAL recs `seedWeight × 1/(1+position)`, summed.
- `CompositeCandidateProvider` normalizes each pool to [0,1], blends `1.0·tag + 0.85·MAL`, `+0.25`
  overlap bonus, degrades to tag-only when MAL empty. **Tuning constants** (`wTag`, `wMal`,
  `overlapBonus`, seed cap 5, perSeedLimit 8) are plain code — adjust after seeing real output.
- Full detail + open threads in the [[recommender-roadmap]] memory.

## Suggested next steps (nothing urgent, no WIP)

- **Run the app and eyeball the blended For You rail**, then tune `wTag`/`wMal`/`overlapBonus`. The
  live rail only renders with reading history present (fresh sim shows nothing) — use a sim/state
  that has history.
- **Open threads** (from [[recommender-roadmap]]): retire the throwaway `MyAnimeListDebugView`;
  extend More Like This reverse-resolution beyond MangaDex-only; add `malId` to `LibraryItem` so
  saved recommendation seeds skip the title search (tracked minor).
- **Optional CI polish:** cache/speed up the SwiftLint job; consider `enforce_admins: true` for full
  strictness once comfortable.

## Working style notes (from memory)

- User is a **new-grad dev learning SWE from this project** — teach + give rationale, don't just do
  ([[user-new-grad-learning]]).
- Prefer **prose discussion at big forks** over AskUserQuestion ([[works-discussion-at-forks]]).
- Features here follow **brainstorm → spec → plan → subagent-driven-development → whole-branch review
  → PR** (superpowers skills). Sonnet implementers, opus for the subtle reviews, has worked well.

## SDD ledger

The last feature's progress ledger is at `.superpowers/sdd/progress.md` (gitignored scratch; overwrite
per feature). All tasks marked complete are done — trust it + `git log` over recollection.
