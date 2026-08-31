# Handoff — MAL Tasks 0–11 complete and merged; Task 12 and one real bug remain

Session of 2026-08-24. **Every task in the MAL OAuth plan except Task 12 is done and on
`main`.** Both live gates were opened with explicit approval, both contract questions were
settled by measurement, and the user's MyAnimeList account was left exactly as it was found.

`main` is at `4a25fac`. No open PRs. Merged this session: **#78** (Task 10 Settings section),
**#79** (Task 0), **#80** (Task 11a + a test-isolation fix), **#82** (Task 11b).

## Resume here

Two candidates, and the user has not chosen between them:

1. **Issue #81 — the WeebCentral detail page is broken.** Undiagnosed. This is the only item
   here that plausibly affects real users, and it is the recommendation.
2. **Task 12 — full verification and delivery.** Mostly confirming work that is already done,
   *except* for one genuine gap: see "What has never been seen" below.

Also outstanding, trivial: `docs/agents/triage-labels.md` names five canonical triage labels
(`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). **Only
`wontfix` actually exists** — `gh label list` returns the GitHub defaults and nothing else.
Either create the labels or fix the doc.

## What was measured (the point of this session)

Three things MAL's own documentation gets wrong or contradicts itself about are now settled by
observation. All of it is written up in the dated Task 11a/11b sections of
`docs/superpowers/research/2026-08-21-mal-oauth-and-manga-progress-api.md`.

**`expires_in` is `2678400` — exactly 31 days.** The official overview table says *one hour*;
the documented example says `2415600` (≈28 days). Both are wrong for this client. The design
already computed expiry from the runtime value, which is the only reading that survives contact
with the API. `refreshMargin` is 5 minutes, comfortable against 31 days and still correct if MAL
ever shortens the token because the margin is relative.

**The list-status setter is `PATCH`.** Verified against Horimiya (MAL 42451), `reading` at 100
chapters: sent `num_chapters_read=101`, MAL echoed `reading`/101, restored to 100, and the
restoration was confirmed **from a fresh process** rather than from the restoring write's own
response. `AppComposition.malUpdateVerb` — the guess the previous handoff flagged — is deleted;
`MALAuthenticatedClient.updateVerb` now defaults to `.patch`.

**Omitting `status` preserves the entry's existing status.** This one was a bonus, and it
matters: `MALListStatusUpdate` was *designed* around the claim that a progress update must not
rewrite `reading`/`completed`, and that claim had never been tested against the live API. It
now has been.

**`PUT` was deliberately not tested.** The question was which verb is supported and `PATCH`
answers it; a second mutation of the user's account would have changed no decision. Same
reasoning for the add-an-unlisted-title path — the harness refused to write to an unlisted title
by design, so that path is still unit-test-only. Both are recorded as open in the research note.

## The Task 11 harness is gone — rebuild it if you need it

Verification used a `#if DEBUG` launch-argument harness (`MALContractCheck.swift`) with
`-mal-contract-read <id>` and `-mal-contract-write <id> <patch|put>`. **It was deleted in the
same commit that locked the verb in** (`6606695`) — recover it from there if a future contract
question needs re-measuring.

It was deliberately *not* a test. `CLAUDE.md` requires that unit tests never touch a real
Keychain or MAL account, and a test could run in CI. A launch argument cannot fire by accident.
Its safety properties are worth reproducing if you rebuild it: read and write are separate
arguments, the write aborts if the title is not already listed (so it can never *add* one, even
with *Automatically add new titles* on), `status` is always `nil`, and a failed restore logs
`ACCOUNT LEFT ALTERED` loudly rather than swallowing it.

## What has never been seen

**Only two MAL Settings states have ever been rendered on a device: signed-out and signed-in.**
Refreshing, reauthorization, the account-switch alert, and large-text are covered by presentation
tests only. Task 12's "inspect signed-in, retry, reauthorization, and large-text states"
checkbox is therefore **still legitimately unticked** — do not tick it on the strength of this
session.

**`skippedCount` is in-memory and resets on relaunch.** The outbox has no skipped storage and a
skipped title is dropped rather than stored. If Settings must show it across launches, that is an
outbox change nobody has scoped.

**No sync-summary line appears in the signed-in section.** Probably correct for an empty outbox,
but it was never confirmed to be the intended empty state rather than a missing label.

## Gotchas worth carrying

**Two documents lied this session; grep before trusting either.** The previous handoff listed
Task 0 as outstanding when the console inspection had already been recorded three days earlier
(`23ccbfb`) — work was redone before that was noticed. And `docs/agents/triage-labels.md`
describes labels the repository does not have. Verify a doc's absence claim against the repo
before acting on it.

**`.debug` log records cannot be read back.** They live in a memory buffer; `log show` returns
nothing. The first `expires_in` probe captured nothing for exactly this reason. Use `.notice`.
Also note `log stream` needs `--level debug` to show debug lines at all, which is a *different*
problem with the same symptom.

**The bundle identifier is `Elias-Magdaleno.Manga-Reader`**, not `com.eliasmagdaleno.*`. Both a
Logger subsystem and a `CFBundleURLName` were written wrong on that assumption before
`simctl launch` rejected the guess.

**`plutil -extract` treats dots in a key as a keypath.** Checking `mal.account.preferences` that
way reports the key missing and briefly looked like the user's account had been wiped. Read the
plist with `plutil -p` and grep instead.

**Two UI tests fail on `main` and are not flake** — see #81. They reproduce on re-run and were
confirmed pre-existing by stashing the branch and re-running against `main` itself. **CI will not
catch them**: it runs unit tests only. Do that stash-and-compare before blaming any branch for a
UI failure.

**A UI test that asserts app state must establish it.** `testSettingsShowsTheSignedOutMyAnimeListSection`
read the real Keychain, so it passed on fresh CI forever and failed the moment anyone signed in.
Fixed with `-uitest-mal-signed-out`. Note that in-memory *credentials alone are not enough* to
reach `.signedOut` — `restore()` reads preferences first, and a cached profile with no credential
is `.reauthorizationRequired`. Both halves must be ephemeral.

## State of the world

- `main` at `4a25fac`; no open PRs; all feature branches deleted locally and remotely.
- Open issues: **#81** only.
- The iPhone 17 Pro simulator is **signed in** to the user's real MAL account (`Proxylink`).
  That is now a live account on the dev machine — anything that drains the outbox there will
  write to it for real. The outbox was empty at the end of this session.
- Unit tests: **639 passed, 0 failed, 2 skipped of 641**. The two UI failures are #81.
