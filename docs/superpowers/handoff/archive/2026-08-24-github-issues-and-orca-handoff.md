# Handoff — tracking moved to GitHub Issues; Orca runs Claude and Codex

Session of 2026-08-24 (late evening). Continues
`2026-08-24-settings-fix-merged-impeccable-package-pr-handoff.md`.

## Read this first

**This is the last handoff that should carry a backlog.** What to do next now lives in GitHub
Issues, not here. Handoff docs are write-once and have gone stale twice in two days — the
UI-test env-var claim and the triage-label drift both got re-derived from scratch because a
doc said something that was no longer true.

So: `gh issue list` is the queue. This document records only the state a fresh session cannot
reconstruct from the repo.

## Repository state

- Branch: `main` at **`b9a9a5c`**
- Working tree clean except two intentionally untracked handoffs (preserve them):
  - `docs/superpowers/handoff/archive/2026-08-24-mal-oauth-progress-complete-handoff.md`
  - `docs/superpowers/handoff/archive/2026-08-24-task-12-verified-claude-priorities-handoff.md`
- No open PRs.

Three merges tonight:

| Commit | What |
|---|---|
| `e70cf9e` | Ink & Seal accessibility package (#89) |
| `3f16966` | Repo-wide strict SwiftLint clean (#94, closed #91) |
| `b9a9a5c` | ADR-0021 spec + plan (#95; #92 deliberately stays open) |

## What to do next

Four issues, three milestones. Two are **not delegable to an agent**.

| # | Title | Label | Who |
|---|---|---|---|
| [#90](https://github.com/eliasmagdaleno/Manga-Reader/issues/90) | Manual VoiceOver traversal: browse → detail → reader | `ready-for-human` | human, with VoiceOver on a device |
| [#92](https://github.com/eliasmagdaleno/Manga-Reader/issues/92) | Implement ADR-0021 background refresh | `ready-for-agent` | agent; spec + plan already written |
| [#93](https://github.com/eliasmagdaleno/Manga-Reader/issues/93) | Fire the live MAL write leg | `ready-for-human` | human; writes to a real MAL account |

#91 is closed. #90 and #92 had stale "blocked by PR #89" lines; both corrected after #89 merged.

**#92 is the biggest one and is ready to start.** Its spec and plan landed in #95:

- `docs/superpowers/specs/2026-08-24-adr-0021-background-refresh-design.md`
- `docs/superpowers/plans/2026-08-24-adr-0021-background-refresh.md` (8 checkbox tasks)

Six design questions were decided; the reasoning is in PR #95's body. The two worth knowing
before touching the code:

- **`WorkStore.didMerge` was rejected** in favour of deriving merge effects from the alias
  chain. **Revival condition, pinned in the spec and on `reconcileMerges`: if `WorkStore` ever
  prunes aliases, this mechanism dies silently.**
- **`maxNotifiedChaptersPerWork = 12`** caps the notification event, not the frontier. It is
  the deliberate mitigation for the unproven chapter-frontier bet (a source that renumbers a
  run reads as ~100 releases). The plan tells the executor not to "simplify away" what looks
  like a magic number.

All thresholds live in one `UpdateTuning` namespace under a header saying none are measured.

## Orca is set up and proven

Both agents ran end to end tonight, each in its own worktree, both reaching merged PRs.

- Managed accounts: **Claude and Codex both registered** (`orca account add [--agent codex]`).
  Codex needs device-code authorization *enabled in ChatGPT Security Settings first*, or the
  browser rejects the code with a banner and the CLI must be re-run for a fresh one.
- Worktrees: `orca worktree create --repo name:Manga-Reader --base-branch main --issue <n>
  --no-parent`. The `--issue` link is what makes `orca worktree list` a status board.
- Dispatch: `orca terminal create --worktree issue:<n> --command claude|codex`, then
  `orca terminal send --terminal <handle> --enter --text '<brief>'`.
- Cleanup: `orca worktree rm --worktree name:<name>`. A squash-merged branch is **not** an
  ancestor of `main`, so `git merge-base --is-ancestor` reports "not merged" and is the wrong
  safety check. Use `git diff origin/main HEAD --stat` and confirm the only differences belong
  to some *other* branch.

Only `main` and `worktree-helper` remain registered.

### Gotchas that cost time

- **Orca launches Claude with `--dangerously-skip-permissions`.** The agent then sits on the
  Bypass Permissions warning until a human accepts it. Worth finding where Orca sets this and
  deciding deliberately, since every Claude worktree inherits it. Codex launches into its own
  sandbox and does not prompt — the two agents run under **different trust assumptions**.
- **`tengu_prompt_suggestion: true`** in `~/.claude.json` renders a suggested next prompt as
  ghost text in the agent's input box. It looks exactly like someone typed an unsent command.
  It is a suggestion, not input, and never self-submits.
- `orca worktree rm` was refused once by the Claude Code permission classifier as destructive,
  then allowed later. If it is blocked, the user has to run it.

## The lesson worth carrying

**Both agents reported success; one was wrong.**

Codex reported "iPhone 17 Pro simulator build: succeeded" and CI failed to compile:

```
Manga_ReaderTests.swift:145:13: error: binary operator '+' cannot be applied to
operands of type 'String' and 'Data'
```

It had line-wrapped a long string literal, so the trailing `.data(using: .utf8)!` bound to only
the second operand of the `+`. The report was not dishonest — a plain `xcodebuild build`
**does not compile the test targets**, so the command it ran genuinely could not have caught
this.

**Rule: any change touching `Manga-ReaderTests/` or `Manga-ReaderUITests/` must be verified
with `build-for-testing` or a full `test` run. A plain `build` is not evidence.**

The general form: re-run the verification that would actually fail, not the one the agent
reports passing. Independently re-running `swiftlint --strict` confirmed the half that held;
not re-running a build is exactly where the defect slipped through.

## Still true, still unfinished

- `worktree-helper` holds commit `869f55b` — `scripts/worktree.sh`, 167 lines, existing on no
  remote and not on `main`. Orca supersedes it. Deleting the worktree keeps the branch; only
  `git branch -D` loses the script.
- ADR-0021 remains **documented and specced, not implemented**. Nothing polls for new chapters;
  refresh is still pull-to-refresh only.
