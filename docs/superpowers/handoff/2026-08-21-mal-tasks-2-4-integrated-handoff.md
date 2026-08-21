# Handoff — MAL Tasks 2–4 integrated, PR #72 open

Session of 2026-08-21 (afternoon, second). Task 3 finished, Task 4 delegated to Codex and
landed, and all three MAL branches merged into one PR. **Nothing is blocked on a decision
except the live-authorization and list-mutation gates.**

## Resume here

**PR [#72](https://github.com/eliasmagdaleno/Manga-Reader/pull/72)** (`mal-integration` →
`main`) carries Tasks 2, 3, and 4. Check CI, then merge it. After that, **Task 5** — token
transport and single-flight refresh — is the next unstarted work, per the Task 5 checklist in
`docs/superpowers/plans/2026-08-21-mal-oauth-progress.md` (that plan is *in* #72, so once it
merges the plan is on `main` and no longer needs `git show mal-oauth:...`).

## What landed

**Task 3 finished** (`a8b2787` on `mal-oauth-values`) — the half that the previous handoff
left open:

- `MALTokenRequest` — form bodies for the authorization-code exchange and for refresh against
  MAL's single token endpoint. The exchange repeats `redirect_uri` because the authorization
  request sent it; neither grant carries a `client_secret`, because Task 0 established this
  client is issued none. Encoding percent-escapes everything outside RFC 3986's unreserved
  set, so a space is `%20` and never `+`.
- `MALTokenResponse` / `MALCredential` — expiry is computed from the runtime `expires_in`,
  deliberately never hard-coded, because MAL's own docs say one hour in the overview table and
  ~28 days in the sample response. `debugDescription` omits both tokens, and a test asserts it.
- `MALOAuthSession` — the stateful holder `MALOAuth.outcome` cannot be as a pure function. A
  duplicate callback and a callback after `cancel()` are both `.rejected`. An *unrelated* URL
  does **not** end the attempt, since the genuine redirect may still be coming.

23 `MALOAuthTests` passing.

**Task 4 landed** (`4f5bd2e` on `mal-credentials`) — written by Codex, tested and committed
from Claude Code (see the sandbox note below). One opaque versioned Keychain record with
device-only accessibility behind a `MALCredentialDataStore` seam; replacement is
`SecItemUpdate` with an `SecItemAdd` fallback, so a failed save leaves the previous complete
record readable. Reinstall protection keys off a **UserDefaults marker** — a reinstall clears
UserDefaults while the Keychain item survives, so an absent marker deletes the stale credential
before anything reads it, and a failed cleanup deliberately does not bless the new marker.
Secrets never reach a string: `MALStoredCredential` redacts both `description` and
`debugDescription`, and the error type presents no `OSStatus`. 10 Swift Testing cases.

## Verification on the merged branch

- **544 XCTest cases, 2 skipped, 0 failures**, plus **10 Swift Testing cases**, on iPhone 17
  Pro with `-parallel-testing-enabled NO`.
- `swiftlint lint`: 42 violations, 0 serious, **zero in any MAL file**. All 42 are pre-existing,
  mostly in `Manga_ReaderTests.swift`. Keep it that way.
- The only merge conflicts were in `project.pbxproj`, where each parallel branch had registered
  its own test file with `xcp`. Resolved by keeping every entry — the conflicting hunks are
  additive, so "take both sides" is the correct resolution, not a judgement call.

## Gotchas worth carrying

**Swift Testing tests do not show up in `xcodebuild`'s "Executed N tests" line.** Task 4's
suite made `xcodebuild` print `Executed 0 tests` while all 10 cases passed — the real line is
`Test run with 10 tests in 1 suite passed`, printed separately. Grepping only for
`Executed [0-9]+ tests` reads as though nothing ran. Grep for both.

**Codex is sandboxed to the primary checkout.** Dispatching Task 4 through the
`codex:codex-rescue` subagent failed outright: the sandbox permits writes only under
`/Users/eliasmagdaleno/Manga-Reader`, and the task targeted the sibling worktree
`/Users/eliasmagdaleno/Manga-Reader-mal-credentials`. The patch was rejected before any file
changed. The fix is to call the companion directly with `--cwd`:

```sh
node "$HOME/.claude/plugins/cache/openai-codex/codex/1.0.6/scripts/codex-companion.mjs" \
  task --cwd <worktree> --write "<prompt>"
```

Even then Codex could not finish the job, and both limits will recur:

- it cannot run the simulator (CoreSimulatorService inaccessible), so it can never produce an
  honest test result; and
- it cannot commit in a **linked worktree**, because that worktree's git metadata lives under
  the primary repo's `.git/worktrees/...` — outside its writable root. `index.lock` fails with
  `Operation not permitted`.

So the working division is: **Codex writes the code; Claude Code runs the tests and commits.**
Plan for that rather than discovering it again.

**Which model Codex used is not recorded anywhere I could find.** No `--model` was passed and
`~/.codex/config.toml` sets no default, so it was the Codex CLI's own default. The session
rollout at `~/.codex/sessions/2026/08/21/rollout-*.jsonl` records `model_provider: openai` and
`model_context_window: 258400` but no model id. If the exact model matters, pass `--model`
explicitly rather than trying to recover it afterwards.

## State of the world

- `main` at `a3dcd9f`. PR #72 open; #70 and #71 merged.
- Branches `mal-oauth`, `mal-oauth-values`, `mal-credentials` are all pushed and all merged
  into `mal-integration`. Delete them after #72 merges.
- Four git worktrees, only two Orca-tracked, so `orca worktree ps` under-reports.
- **CI runs only on push/PR to `main`.** A pushed feature branch with no PR gets no run at all.
- A new worktree needs `Secrets.xcconfig` symlinked in by hand or every build fails:
  `ln -s /Users/eliasmagdaleno/Manga-Reader/Secrets.xcconfig <worktree>/Secrets.xcconfig`.

## Still gated

No real authorization and no MAL list mutation without Elias's explicit approval. The `PATCH`
versus `PUT` question (Task 11) stays open: MAL's own reference contradicts itself, so it must
be settled against a known list entry whose prior state is restored afterward.

## Loose threads

- The MAL console has *Commercial / Non-Commercial* set to `commercial` while *Purpose of Use*
  is `hobbyist`. Looks unintended; an account/ToS matter, not a technical blocker.
- Usage budget, as of this session: Claude usage low, Codex at ~60% of the weekly allowance.
  Worth weighing before dispatching more parallel agent work.
