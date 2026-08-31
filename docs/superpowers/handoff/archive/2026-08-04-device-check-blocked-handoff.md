# Session Handoff — 2026-08-04 (later): device check ran and came back NEGATIVE

**Audience:** the next session. Supersedes `2026-08-04-adr-0011-slice-4-handoff.md` for **state
only** — that file's gotchas, parked items, and older open threads all still stand, and its
"Update — 2026-08-04, later session" section is this session's work up to the device check.

**The branch is not ready for a PR.** Slice 4 is still feature-complete and its design is still
settled — nothing here reopens a decision. But the one blocking item, the live device check, was
attempted and **did not pass**, and the reason is not yet known.

## State

| | |
|---|---|
| `main` | `80bd1f6` — unchanged |
| Working branch | **`anilist-ranked-pool`** at **`4c0d45a`**, tree clean, **17 commits ahead of `main`, not pushed, no PR** |
| Unit tests | 417 pass / 1 skipped, unchanged by this session (two docs-only commits) |
| Simulator | **iPhone 17 `A6AA1766-3B5C-4C59-B702-2C4D9F3CF103`**. The slice-4 handoff's `iPhone 16 Pro BE0AB07B…` **no longer exists** — do not look for it |
| agy hook | **fixed and verified working** (below) |

Two commits landed, both docs:

| | |
|---|---|
| `04c1073` | ADR-0011 revisit trigger: the tag-decoding gate is closed again |
| `4c0d45a` | The slice-4 handoff, tracked, with this session's amendments |

## The device check — what actually happened

Run once, on the **existing** container. Facts:

- App built, installed, launched, alive, sitting on Home. **No For You rail rendered.**
- `works.json` (Application Support) holds **5 Works** — above the ≥3 gate. Not a missing-data case.
- `anilist-tag-vocabulary.json` mtime unchanged at **10:51** — the launch kick's `refreshIfNeeded`
  correctly no-oped against a warm cache.
- **No `anilist-pool.json` in `Library/Caches/` after 180s of polling.** This is the gate, and it
  did not open.

### Two things about that run you must not inherit as true

1. **It was not a cold run.** The intended first step was to clear app state; the `simctl uninstall`
   **failed** (simulator was shut down) and the script's `echo "uninstalled (state cleared)"` printed
   anyway because it was unconditional with stderr suppressed. The container — vocabulary, Works,
   history — was fully intact. So the two-launch sequence the slice-4 handoff defines was never
   actually started from its defined starting state.
2. **That failure was lucky, and the plan behind it was wrong.** A successful erase would have taken
   the 5 Works with it. With no library there is nothing to seed pairs from, the pool could never
   populate, and the check would have produced a confident-looking negative that proved nothing.
   **Do not "clear state" by uninstalling.** If you want a cold pool, delete
   `Library/Caches/anilist-pool.json` (and the vocabulary json if you want the full three-build
   sequence) and leave Application Support and the plist alone.

### The open question, and the two hypotheses

**Does `RecommendationEngine.load()` run at all on a cold launch?**

- **H1 — it never ran.** The For You rail may not be in the view hierarchy when it has nothing to
  show, so the provider's own kick never fires and nothing ever seeds. If true this is a **real bug,
  not the wiring-identity hazard**: the pool would never warm on *any* launch, and the launch kick
  would be warming a vocabulary for a rail that never asks for it.
- **H2 — it ran and the refresh failed silently**, e.g. on the network or the limiter. Completely
  different fault, same observable.

The observable is identical either way, which is exactly why this needs
`superpowers:systematic-debugging` rather than a guess. **The app emits no `os_log` of its own** —
`log show` is pure system noise, so logs cannot distinguish H1 from H2. Distinguishing them almost
certainly needs a temporary instrumented build. That is the diagnostic previously argued against
shipping on a finished branch; as a throwaway local build to answer this, it is the right tool.

**Nothing here suggests the composition root is wrong.** Re-reading `Manga_ReaderApp.swift:56-59`
and `:82-83`, `vocab` and `pool` are `let`s stored as properties and captured by the `makeProvider`
closure, so the provider struct being rebuilt per rail build is fine and only the actors need
identity. That reads correct; it is simply still unproven, because the run never got far enough to
exercise it.

## The agy hook — diagnosed, fixed, verified. Do not re-investigate.

**It was never broken.** `.agy_code_review.md` was stale because `agy` **failed on four consecutive
commits**, and the hook's fail-safe correctly preserved the good review instead of overwriting it
with junk. The stale file was a *complete* review of `9dac7db` — header, body, `# agy review
complete — exit 0` terminator. Nothing was lost.

Cause: commits at 10:34, 10:44, 10:48, 10:52 — four in 18 minutes, each detaching an `agy` that runs
a full `xcodebuild test` under a 20m timeout. Every run after the first collided with one already
holding the build database lock. `9dac7db` is in the file because it is the only commit that ran
alone. **The hook wrote `.agy_review_running` but never read it** — the 2026-08-03 investigation's
Issue 5 fix published the lock for others and then ignored it itself.

Fixed in `.git/hooks/post-commit`: atomic `noclobber` lock acquisition that exits 0 if a review is
already running, plus a 25m stale-lock reap (> the 20m timeout, so it can never reap a live run).
Verified live this session — `04c1073` took the lock and wrote a complete review; `4c0d45a`, committed
seconds later, skipped cleanly and left the lock's mtime untouched.

- **`.git/hooks/` is not version-controlled.** This fix is machine-local and rides in no commit. A
  fresh clone will not have it. There is no tracked hooks directory to mirror it into.
- **Rejected: queue-on-exit** (re-run against the new `HEAD` when the current review finishes). It
  would review the **last** commit of a burst rather than the first, which is the one you actually
  want — but it needs real stale-lock handling and was out of scope for a timeboxed diagnosis. This
  is the better behaviour if the current skip ever annoys you.
- **New, minor:** the review file is now 281 lines of raw `xcodebuild` log rather than a report, so
  the 2026-08-03 investigation's Issue 3 (narration/noise leaking into captured output) has partly
  resurfaced. Not blocking. Trust its pass/fail numbers; read the diff for what changed.

## Decisions taken this session, still unexecuted

Both were grilled and settled; do not re-litigate.

- **`MALReverseResolver` lands after the merge, not on this branch.** The extraction is worth doing
  and the golden is in place to prove it moved nothing — but the branch's riskiest claim is the
  untestable one, and touching `recommendations(for:)` would give a failed device check two candidate
  causes instead of one. That single-cause property is what the two-commit golden split bought.
- **The device check gates on the on-disk pool cache, not the rail.** The hazard is object identity,
  and a rail blended at `wAniList = 0.6` can move subtly enough that reading rank order off a
  screenshot proves nothing either way. Rail screenshot is corroboration only.

## Pick up here

1. **`superpowers:systematic-debugging` on H1 vs H2.** Instrumented throwaway build; first question
   is whether `load()` runs on a cold launch at all.
2. **Then re-run the device check properly** — clear only `anilist-pool.json`, keep Application
   Support. Pool populated after run one, candidates flowing on run two, third empty run means the
   capture is wrong.
3. **Then the full suite in the background, then one PR** of the whole branch to `main`. Do not
   stack.

## Gotchas — all of the slice-4 handoff's still apply

Plus, new this session:

- **`simctl uninstall` against a shut-down simulator fails.** Boot first, and never suppress its
  stderr behind an unconditional success `echo` — that is how this session produced a false claim.
- **The simulator gets shut down by `agy`'s test runs.** It was booted at 15:30 and shut down by
  15:32. Re-check with `simctl bootstatus` before installing, not once at the start.
- **The app has no logging.** Any behavioural question about it needs an instrumented build; there
  is no log to read.
