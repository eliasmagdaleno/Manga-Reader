# Brief for Codex — MAL Task 4: credential storage and reinstall protection

## Context you need

Task 0 is **answered**: the MAL client is App Type `ios`, **no client secret is issued**, and
`mangareader://oauth/mal` registers verbatim as the single redirect URI. Evidence is a dated
section at the end of
`docs/superpowers/research/2026-08-21-mal-oauth-and-manga-progress-api.md` on `mal-oauth`.
Nothing confidential ships in the binary, so the backend-exchange fallback is off the table.

**Task 2 is complete** — the durable outbox is finished and committed (`d1f0c42` on
`mal-oauth`): quarantine of unreadable on-disk state, retry/permanent-block, deferred Works
keyed by `WorkID` with promotion, per-account summary, exact-account clear, and the
`MALProgressOutboxProtocol` seam. 16 outbox tests; full unit suite 521 passing, 2 skipped.
`mal-oauth` is now pushed to `origin` — pull before you branch.

**SwiftLint 0.65.0 is now installed locally.** `swiftlint lint` from a worktree root is the
CI-equivalent command. Current state: 42 violations, 0 serious, exit 0, and **zero** in any
MAL file. Please keep it that way.

## Your task: Task 4 only

`Manga-Reader/Services/MALCredentialStore.swift` plus
`Manga-ReaderTests/MALCredentialStoreTests.swift`, per the Task 4 checklist in
`docs/superpowers/plans/2026-08-21-mal-oauth-progress.md`. In short: load/save/delete over a
Keychain-backed adapter plus an in-memory fake; one versioned record (token type, access
token, refresh token, expiry, MAL user id) with a device-only accessibility class;
transactional replacement so a failed save leaves the old complete record readable; an
injectable installation-marker store that deletes surviving credentials on a new install;
tests for first install, relaunch, simulated reinstall, corrupt record, logout, and Keychain
errors; and an audit proving no secret is interpolated into any debug description or error.

## Division of labour — please respect this

Claude Code is doing **Task 3** (`MALOAuth.swift` / `MALOAuthTests.swift`) on branch
`mal-oauth-values`, in the worktree `/Users/eliasmagdaleno/Manga-Reader-mal-oauth-values`.
The two file sets are disjoint; neither task depends on the other. **Do not touch
`MALOAuth*`**, and Task 3 will not touch `MALCredentialStore*`.

Please branch **off `main`**, not off `mal-oauth` and not off `mal-oauth-values` — stacked PRs
in this repo close unrecoverably when their base is deleted. Work in your own worktree.

The one file you will both edit is `project.pbxproj`, because each new test file needs
registering with `xcp`. That is a known, small merge conflict; keep the `xcp` churn collapsed
to the four intentional entries per file so it stays trivial to resolve.

## Gotchas that already cost time here

- Check `git branch --show-current` before every `git add`. Agents have switched branches
  under one another in this repo.
- `xcp` reformats the three synchronized-root declarations in `project.pbxproj`; collapse only
  that formatting churn. Check `git diff --stat` immediately before `git add`, not right after
  `xcp` — Xcode rewrites the file on its own schedule.
- Every test command: iPhone 17 Pro, `-parallel-testing-enabled NO`.
- `Secrets.xcconfig` is a gitignored symlink. Never stage it. The repo is **public**.

## Still gated — do not cross these

- No real authorization and no MAL list mutation without explicit approval from Elias.
- The `PATCH` vs `PUT` question (Task 11) stays open; MAL's own reference contradicts itself,
  and it must be settled against a known list entry whose prior state is restored afterward.
