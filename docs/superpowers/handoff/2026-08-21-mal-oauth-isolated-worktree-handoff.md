# Handoff — MAL OAuth work continues in the isolated worktree

Session of 2026-08-21. The MyAnimeList OAuth and push-progress design is approved, researched,
planned, and isolated from the shared checkout. No production implementation has started.

## Start here

1. Open a fresh Codex session rooted at:
   `/Users/eliasmagdaleno/Manga-Reader-mal-oauth`
2. Confirm the branch is `mal-oauth`, the worktree is clean, and HEAD is `56800b5` or a known
   descendant.
3. Read, in order:
   - `docs/superpowers/research/2026-08-21-mal-oauth-and-manga-progress-api.md`
   - `docs/superpowers/specs/2026-08-21-mal-oauth-progress-design.md`
   - `docs/superpowers/plans/2026-08-21-mal-oauth-progress.md`
4. Check PRs #70 and #71 before implementation. Both are open, mergeable, and green as this
   handoff is written. Once their disposition is known, fetch `origin/main` and integrate the
   resulting main into `mal-oauth` before changing production code.
5. Begin with Task 0 in the plan: confirm the MAL native/public-client and callback registration
   boundary. Pure unit-tested implementation may proceed while nonessential live details remain
   open, but do not perform a real authorization or list mutation without the plan's explicit gate.

Fresh-session completion criterion: the agent is operating only in the isolated worktree, has
integrated the intended post-#69 main state, and either records Task 0's non-secret outcome or
reports the exact human/account action still required.

## Current repository state

- Worktree: `/Users/eliasmagdaleno/Manga-Reader-mal-oauth`
- Branch: `mal-oauth`
- HEAD: `56800b5 Clarify MAL completion trigger semantics`
- Parent design commit: `6f47072 Design MyAnimeList progress tracking`
- Base: `eb8a2de Land the 2026-08-21 MAL handoff (#69)`
- Working tree: clean when this handoff was written.
- `Secrets.xcconfig` is an ignored symlink to the primary checkout's existing file. Never stage it.
- The branch is local and unpushed.

Merged before this branch:

- #68 — backdated seeded history;
- #69 — MAL-next handoff.

Open when this handoff was written:

- #70 — corrects the documented `isRead` semantics, makes `AGENTS.md` a symlink to `CLAUDE.md`,
  and commits the shared Swift/iOS skills. Both checks pass.
- #71 — records the shared-worktree/interop handoff. Both checks pass.

`AGENTS.md` does not exist on the current `mal-oauth` base. Do not create or edit it. PR #70 is the
authority for making it a symlink; after that lands, edit `CLAUDE.md` for shared instructions.

## Approved v1 product contract

- Sign-in is optional; signed-out reading remains fully functional.
- Synchronization is push-only. A per-title status read before a write is a safety check, not list
  import.
- An absent title is added explicitly as `reading` when **Automatically add new titles** is on.
- Only a genuine `ReadingEntry.isComplete` transition from the reader can enqueue MAL progress.
- Manual mark-read, mark-all-below, mark-unread, history deletion, and history clear remain local.
- Automatic progress is monotonic and never deliberately lowers the last observed MAL progress.
- Existing MAL list status is preserved. V1 never infers `completed`.
- Decimal chapter labels floor to the completed whole number (`12.5 -> 12`); zero, negative,
  named-special, range, blank, and overflow labels do not sync.
- Credentials live in device-only Keychain storage. Progress waits in a durable, account-bound,
  coalescing outbox.
- V1 performs no background network assertion; it drains while active and flushes durable state on
  backgrounding.

## Load-bearing read-state correction

`Manga-Reader/Services/HistoryStore.swift` is authoritative:

- a history entry means the chapter was opened and provides resume/history data;
- opening also mints the Work and enables vertical-reader recording;
- `HistoryStore.isRead` means a **completed** history entry or a manual read mark;
- completion is `pageCount > 0 && page >= pageCount - 1`;
- opening alone does not mark a chapter read and must not trigger MAL progress.

The seeded simulator has 18 history entries but only 14 completed entries. Four are mid-chapter.
A result of 14 on read/completion assertions is correct, not a regression.

## Official MAL gaps that remain visible

The official-source research established the usable contract and recorded these unresolved points:

- MAL documents plain-only PKCE, not `S256`.
- Native callback forms and denial/error callbacks are not specified.
- The OAuth page contradicts itself on access-token lifetime; runtime `expires_in` is authoritative.
- No user token-revocation endpoint is documented; logout is local device credential deletion.
- The API reference contradicts itself on PATCH versus PUT for manga-list updates.
- `num_chapters_read` is integer-only with no documented decimal, range, or completion mapping.
- No numeric quota, 429, or `Retry-After` contract is published.

Do not hide any of these behind an implementation assumption. The update verb requires a controlled
live test against a known list entry, an exact mutation/restoration preview, and explicit approval
immediately before the write.

## Implementation route

Follow `docs/superpowers/plans/2026-08-21-mal-oauth-progress.md` task by task. Its major slices are:

1. native-client/callback registration gate;
2. pure chapter mapping and HistoryStore completion event;
3. persistent account-bound outbox;
4. pure OAuth values/callback validation;
5. Keychain credentials and reinstall protection;
6. token transport and single-flight refresh;
7. authenticated per-title MAL client;
8. account state and `ASWebAuthenticationSession` presentation;
9. serial reconciliation/drain with retry classification;
10. Work metadata promotion and AppComposition lifecycle wiring;
11. Settings account surface;
12. explicitly approved live verification and full delivery checks.

The existing read-only `MyAnimeListAPI` remains unchanged for discovery and entity resolution.
Authenticated operations belong behind new narrow protocols composed in `AppComposition`.

Every `xcodebuild test` invocation must target:

```sh
xcodebuild -scheme Manga-Reader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO test
```

New `Models/` and `Services/` files compile through synchronized groups. New `Views/` or
`Manga-ReaderTests/` files require `xcp` project registration. Treat `project.pbxproj` as able to
change while Xcode is open and inspect it immediately before staging.

## Worktree tooling

A tested helper exists separately at:

`/Users/eliasmagdaleno/Manga-Reader-worktree-helper/scripts/worktree.sh`

Its commit is `869f55b Add guarded worktree helper` on local branch `worktree-helper`. That branch is
not pushed. The helper supports `new`, `list`, `path`, and clean-only `remove`, and automatically
links ignored `Secrets.xcconfig`. It is not yet present in the `mal-oauth` branch.

Orca's app runtime was healthy from the user's interactive terminal but inaccessible from this
Codex sandbox because of a macOS `task_name_for_pid` failure. The plain Git worktree above is the
active isolation mechanism; do not move MAL work back to the shared checkout merely to regain Orca
metadata.
