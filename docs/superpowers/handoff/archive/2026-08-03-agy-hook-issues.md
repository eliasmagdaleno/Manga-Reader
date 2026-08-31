# Issues with the `agy` post-commit review hook

Observed 2026-08-03 on `Manga-Reader`, branch `anilist-ranked-pool`, across two consecutive commits
(`d945315`, `540d7f3`). Written for whoever maintains the hook.

## The hook as it stands

`.git/hooks/post-commit`:

```bash
#!/bin/bash
echo "🤖 [AGY] Triggering automated verification of recent commit in Manga-Reader..."

if [ ! -f "Secrets.xcconfig" ]; then
  echo "MAL_CLIENT_ID = ci-placeholder" > Secrets.xcconfig
fi

agy --model gemini-3.1-pro --effort high --dangerously-skip-permissions --prompt "Audit the latest commit (git show HEAD --stat -p). Run 'swiftlint lint' and run unit tests via 'xcodebuild -scheme Manga-Reader -destination \"platform=iOS Simulator,name=iPhone 17 Pro\" -parallel-testing-enabled NO test -only-testing:Manga-ReaderTests'. Verify zero compiler errors, failing tests, or style violations. Summarize the changes and any architectural notes at the end for Claude." | tee .agy_code_review.md
```

## What happened

Two commits were made. After both, `.agy_code_review.md` contained exactly this, and nothing else:

```
I've started running the unit test suite via `xcodebuild` on the iPhone 17 Pro simulator. I'll analyze the test results as soon as the build finishes.
```

151 bytes, one line. No audit, no lint result, no test result, no architectural notes. Both commits
went unreviewed, and per `CLAUDE.md` this file is the mechanism by which Claude "stays in the loop
regarding recent changes, errors, and architectural notes" — so the loop was silently open.

## Issue 1 — `tee` truncates the previous review before the new one exists (worst one)

`| tee .agy_code_review.md` opens the file for writing **when the pipeline starts**, not when `agy`
finishes. So the moment any commit happens, the previous — possibly complete and useful — review is
destroyed. If the new run then aborts, times out, or emits only a preamble, the repo is left with
*less* information than before the commit.

That is what happened here twice in a row.

**Suggested fix:** write to a temp file and move it into place only on success.

```bash
tmp="$(mktemp)"
if agy … --prompt "…" > "$tmp"; then
  mv "$tmp" .agy_code_review.md
else
  echo "review failed, keeping previous .agy_code_review.md" >&2
  rm -f "$tmp"
fi
```

## Issue 2 — the output has no way to say "this review did not finish"

A consumer reading `.agy_code_review.md` cannot distinguish:

- a completed review that found nothing,
- a review that died halfway,
- a review of a *different, older* commit.

There is no commit SHA, no timestamp, no exit status, and no terminator. Freshness can't be inferred
from mtime either, because `tee` touches the file at the *start* of a run that may never produce
findings — the file's mtime was recent and its contents were meaningless.

**Suggested fix:** a header and a footer written by the hook, not by the model.

```
# agy review — d945315 — 2026-08-03T15:19:04-07:00
…model output…
# agy review complete — exit 0
```

Absence of the trailing line then means "did not finish", which is checkable by a human or an agent
in one glance.

## Issue 3 — the model streams a preamble that looks like output

The captured line is conversational narration ("I've started running… I'll analyze the results as
soon as the build finishes"), not a report. It reads like a *result* to anything parsing the file,
which is what made the failure quiet rather than loud.

**Suggested fix:** either suppress intermediate narration in the piped output (a `--quiet` /
report-only mode), or instruct the prompt to emit the report as a single final block with a fixed
sentinel the hook can grep for before accepting the run.

## Issue 4 — the hook is synchronous and blocks `git commit` for minutes

`post-commit` runs in the committing shell, so `git commit` does not return until a full
`xcodebuild … test` finishes. In this session both commits **timed out a 10-minute agent shell**.
The commit itself had already succeeded, so the failure is cosmetic — but only if you know that.
It looks exactly like a failed commit, and the natural recovery (re-running `git commit`) is wrong.

**Suggested fix:** detach the review.

```bash
nohup bash -c 'agy … > "$tmp" && mv "$tmp" .agy_code_review.md' >/dev/null 2>&1 &
disown
```

The review is inherently asynchronous — nothing about it needs to hold the commit open.

## Issue 5 — it fights whoever else wants to build

Because it runs `xcodebuild` immediately and holds the build database lock, any build started while
it runs fails with `database is locked`. The practical rule this forces on a human or agent — "do
not build until the hook exits" — is unenforceable, because the hook gives no signal that it is
still running.

**Suggested fix:** a lock/PID file the hook writes on entry and removes on exit
(`.agy_review_running`), so anyone can check before building. This composes well with Issue 4's
detachment.

## Issue 6 — it targets a different simulator than the project mandates

The prompt hardcodes `name=iPhone 17 Pro`. `CLAUDE.md` mandates **`iPhone 17`** for every
`xcodebuild` invocation in this repo. Both simulators exist here, so this is not a hard failure —
but it means the hook boots and keeps a *second* simulator running alongside the one the developer
is using, doubling simulator load and worsening Issue 5's contention for no benefit.

**Suggested fix:** `name=iPhone 17`, matching `CLAUDE.md`.

## Issue 7 — the placeholder `Secrets.xcconfig` is written unconditionally into the working tree

The hook creates `Secrets.xcconfig` if absent. It is gitignored, so this will not be committed —
but a developer who has *deliberately* removed the file to test the missing-secret path will find it
silently recreated by an unrelated `git commit`.

Minor, and arguably worth the convenience. Noting it only because it is a side effect on the working
tree from a hook whose name implies read-only verification.

## Priority

1. **Issue 1** — actively destroys good reviews. Everything else is a missing signal; this one loses
   information that already existed.
2. **Issue 2 + 3** — together they turn a failed review into a silent one, which is how both of
   today's commits went unreviewed without anyone noticing until the file was opened and read.
3. **Issue 4 + 5** — quality-of-life, but they are what makes committing feel broken.
4. **Issue 6 + 7** — small.
