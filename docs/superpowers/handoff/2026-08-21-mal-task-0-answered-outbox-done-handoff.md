# Handoff — Task 0 answered, Task 2 done, Task 3 half-built

Session of 2026-08-21 (afternoon). Three MAL tasks moved. **Nothing is blocked on a
decision any more except the live-mutation gate.**

## Resume here

Task 3 is half-finished on `mal-oauth-values` in
`/Users/eliasmagdaleno/Manga-Reader-mal-oauth-values` (branched off `main`, commit
`a40a56f`, 10 tests green). What remains from the Task 3 checklist in
`docs/superpowers/plans/2026-08-21-mal-oauth-progress.md` (that plan lives on `mal-oauth`,
not on this branch — read it from the other worktree):

- form encoding for the authorization-code exchange and for refresh, including the exact
  redirect URI and the **absence** of a client secret;
- token request/response and stored-credential value types;
- rejection of a duplicate completion and of a callback arriving after cancellation — this
  needs a small stateful holder, since `MALOAuth.outcome` is a pure function today.

Then run `MALOAuthTests`, and `swiftlint lint` from the worktree root.

## What landed

**Task 0 is answered** — the gate that could have killed the feature is open. The MAL client
is App Type **`ios`** and is issued **no client secret**; `mangareader://oauth/mal` registers
verbatim as the single redirect URI. Nothing confidential ships in the binary, so the
backend-exchange fallback is off the table. Evidence is a dated section at the end of
`docs/superpowers/research/2026-08-21-mal-oauth-and-manga-progress-api.md` (`23ccbfb` on
`mal-oauth`). The client id is deliberately not recorded there.

**Task 2 is complete** (`d1f0c42` on `mal-oauth`): quarantine of unreadable on-disk state,
retry and permanent-block, deferred Works keyed by `WorkID` with promotion to a MAL id, a
count-only per-account summary, exact-account clearing, and the `MALProgressOutboxProtocol`
seam. 16 outbox tests; full unit suite **521 passing, 2 skipped**.

Two invariants the tests pin down, both easy to regress: a result for progress the caller has
since superseded never overwrites retry state for the newer value, and promotion merges
*through* `enqueue`, so it can only ever raise queued progress.

**Task 3, partially** (`a40a56f` on `mal-oauth-values`): PKCE (`plain` only — the challenge is
the verifier verbatim, which is MAL's documented contract, not a shortcut), the six-parameter
authorization URL, and callback validation that checks `state` before reading anything else.

## State of the world

- `main` is at `a3dcd9f`. PRs #70 and #71 both merged; no open PRs.
- `mal-oauth` is **pushed** to origin — it was local-only until this session, with the whole
  subsystem living on one disk. No PR opened yet.
- `mal-oauth-values` is local-only. Push it.
- Four git worktrees now, only two of them Orca-tracked, so `orca worktree ps` under-reports.
  The shared-checkout collision described in the previous handoff is resolved.
- **SwiftLint 0.65.0 is installed** (it was not, all previous sessions). `swiftlint lint` from
  a worktree root is the CI-equivalent command. Current: 42 violations, 0 serious, exit 0,
  **zero in any MAL file**. All 42 are pre-existing, mostly in `Manga_ReaderTests.swift`.
- **CI does not run on feature branches** — `.github/workflows` triggers only on push/PR to
  `main`. A pushed branch with no PR gets no run at all. Do not assume a push means CI ran.
- A new worktree needs `Secrets.xcconfig` symlinked in by hand or every build fails on an
  unopenable base configuration:
  `ln -s /Users/eliasmagdaleno/Manga-Reader/Secrets.xcconfig <worktree>/Secrets.xcconfig`.

## Codex

Codex was handed **Task 4** (`MALCredentialStore.swift` — Keychain storage and reinstall
protection). The brief told it to branch off `main` in its own worktree and to leave
`MALOAuth*` alone; Task 3 leaves `MALCredentialStore*` alone. The one shared file is
`project.pbxproj`, because each new test file is registered with `xcp` — a small known
conflict. Confirm Codex actually picked this up before starting Task 4 yourself.

## Still gated

No real authorization and no MAL list mutation without Elias's explicit approval. The
`PATCH` versus `PUT` question (Task 11) stays open: MAL's own reference contradicts itself,
so it must be settled against a known list entry whose prior state is restored afterward.

## One loose thread

The MAL console has *Commercial / Non-Commercial* set to `commercial` while *Purpose of Use*
is `hobbyist`. Looks unintended; an account/ToS matter, not a technical blocker.
