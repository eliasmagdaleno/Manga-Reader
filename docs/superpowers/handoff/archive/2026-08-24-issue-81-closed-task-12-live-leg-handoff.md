# Handoff — #81 closed, `.refreshing` wired, Task 12's live leg run

Session of 2026-08-24 (afternoon). Everything below is on **`fix-81-and-refreshing-state`**,
pushed, with **draft PR #84** open and CI green (SwiftLint 16s, Build & unit tests 11m38s).
`main` is untouched at `7827f26`.

## Resume here

1. **PR #84 is a draft.** CI passed. Review and mark ready / merge.
2. **The rest of Task 12's manual exercise** is still unticked: offline completion, relaunch
   persistence, foreground retry, toggle disable/enable, logout cleanup, and reauthorization on
   the seeded simulator, plus "build and manually verify signed-out reading is unchanged".
3. `docs/agents/triage-labels.md` is **no longer** drifted — all five labels now exist.

## Issue #81: neither failure was an app bug

**The issue's WeebCentral hypothesis was wrong.** The detail page renders fine — the UI hierarchy
captured at failure shows Junjou Romantica complete with badge, tags and synopsis. Live checks:
`detailScript`'s selectors (`.whitespace-pre-wrap`, the `strong` labels) all still match, and
`/series/{id}/full-chapter-list` still works (One Piece: 1191 chapter links). No scraper rot.

Two independent test-isolation defects:

- **The mint test** asserted `Add to Library` on a title it had itself added on a previous run,
  where the button reads `In Library`. It was never idempotent.
- **The show-all test** inherited the browse source (`SourceRegistry` persists `source.activeID`).
  Pinning it with a DEBUG `-uitest-source` argument was **necessary but not sufficient** — with
  MangaDex pinned it still failed 3/3, and the hierarchy dump showed why: Home's first card was
  **"6000: Rokusen", 3 AVAILABLE**. The test's own caveat that "popular Home titles reliably
  qualify" was false. It now searches for Berserk.

A third bug was found on the way: the tap-retry at the old line 200 fired whenever the label was
not exactly `"Add to Library"` — which an already-in-library title never is — so it tapped *into*
the detail page and the later assertion failed for an unrelated reason.

**Both pass on two consecutive live runs.**

## `.refreshing` had no producer

`MALAccountStore.State.refreshing` was declared, mapped to `isRefreshing: true`, and unit-tested,
but **nothing ever set it**. That is why Task 12's "inspect the refreshing state" box had never
been ticked — the state was unreachable, not merely unvisited.

`MALTokenManager` now takes `refreshDidChange`, called at the single-flight boundary so a burst of
pushes sharing one token request shares one notification, and a throwing refresh still clears via
the existing `defer`. `AppComposition` wires it through a weak box mirroring `MALDrainHandle`.
Both store transitions are guarded, so a permanently failed refresh — already moved to
`reauthorizationRequired` — is not talked back into looking signed in.

## The four states now render

`-uitest-mal-state <signed-in|refreshing|reauthorization-required|account-switch>` seeds the
account on the same ephemeral stores `-uitest-mal-signed-out` uses, under the stand-in name
`UITestReader`. **Nothing reads or writes the real account.** Signed-in and
reauthorization-required go through `restore()`'s genuine branches; `refreshing` goes through its
real producer; only the switch alert needs a seam, and only for presentation.

**Look at the screenshots, don't trust the checkmark.** Two bugs hid behind a passing test: the
simulator was left in landscape by an earlier test, and asserting the header was `isHittable`
stopped scrolling with the section's card still behind the tab bar.

## Task 12's live leg — done, account restored

Horimiya (MAL **42451**), `reading` at **100** chapters, verified before starting; outbox empty;
`syncEnabled` true.

| Step | Result |
|---|---|
| Before (fresh process) | `status=reading chapters=100` |
| Read chapter 124 to its last page in the reader | — |
| After (fresh process) | `status=reading chapters=124` |
| Restore | `was=124 now=100 status=reading` |
| Confirm (fresh process) | `status=reading chapters=100` |

**The account is exactly as it was found.** This exercised the whole path — reader completion →
`HistoryStore` → outbox → coordinator → `PATCH` — and confirmed again that omitting `status`
preserves it.

**Chapter 124, not 101.** The coordinator treats a desired progress at or below the remote value
as already delivered (`MALProgressCoordinator.swift:281`), so anything ≤ 100 verifies nothing —
and 101 does not exist: MangaDex's English list for this title runs 1–30, then jumps to 123.1.

`testLiveHorimiyaCompletionPushesProgress` is committed but **skips unless `MAL_LIVE_WRITE=1`**
— from the CLI, set it as `TEST_RUNNER_MAL_LIVE_WRITE=1` (`xcodebuild` strips the prefix).

## Gotchas

**The previous handoff's harness-recovery instruction is wrong.** It says to recover
`MALContractCheck.swift` from `6606695`. That commit does not contain it and neither does any
other — `git log --all --name-status | grep -i contractcheck` is empty. It was never committed.
I rewrote it this session and deleted it again; **the source is in the appendix below.**

**The app data container changes under you.** `xcrun simctl get_app_container` returned
`3CBA61A4…` early in the session and `5FF847FA…` later; a `simctl install` or a UI-test install
can swap it. An early experiment of mine edited prefs in a container that was later replaced, so
treat "I edited the plist and the behaviour changed" as weak evidence. Re-resolve the path every
time. The fixture (`works.json`, 19KB) is intact in the current container.

**`source.activeID` is currently the string `"b"`** in the fixture container — matching no source,
so `SourceRegistry` falls back to the first. Harmless, but unexplained; it is not a value the app
should be able to write.

**Reader chrome is hidden until tapped.** The page indicator (`"n · total"`) does not exist in the
hierarchy until you tap the center of the screen, which cost one failed run.

**`plutil -extract` still treats dots as a keypath** — `mal.account.preferences` reads as missing.
Use `plistlib` from Python, or `plutil -p` and grep.

## State of the world

- Branch `fix-81-and-refreshing-state`, 5 commits, pushed; **draft PR #84**, CI green.
- Unit suite: **647 tests, 0 failures, 2 skipped** (was 641). SwiftLint 42 warnings, 0 serious —
  unchanged baseline. `project.pbxproj` untouched all session.
- Open issues: **#81** (fixed on the branch; close it when #84 merges).
- All five triage labels now exist on GitHub.
- The simulator is still signed in to the real MAL account (`Proxylink`, id 10146880), outbox
  empty, `automaticallyAddsTitles` **true** — so an unlisted title *can* be added by a real
  completion. Worth knowing before driving the reader on a title that is not on the list.

## Appendix — the read/restore harness

Recreate at `Manga-Reader/Services/MALContractCheck.swift` (a synchronized group, so it compiles
with no `project.pbxproj` edit), call `MALContractCheck.runIfRequested(client: malClient)` from
`AppComposition.init` right after `malClient` is built, and **delete both again afterwards**.

Safety properties, all deliberate: read and restore are separate arguments; the restore refuses a
title that is not already listed, so it can never *add* one even with automatic addition on;
`status` is always nil; a failed restore logs `ACCOUNT LEFT ALTERED` loudly. Logs at `.notice` —
`.debug` records live in a memory buffer and `log show` returns nothing.

Usage:

```sh
xcrun simctl launch 'iPhone 17 Pro' Elias-Magdaleno.Manga-Reader -mal-contract-read 42451
xcrun simctl launch 'iPhone 17 Pro' Elias-Magdaleno.Manga-Reader -mal-contract-restore 42451 100
xcrun simctl spawn 'iPhone 17 Pro' log show --last 2m \
  --predicate 'subsystem == "Elias-Magdaleno.Manga-Reader"' --style compact | grep CONTRACT
```

```swift
#if DEBUG
import Foundation
import OSLog

enum MALContractCheck {
    private static let log = Logger(subsystem: "Elias-Magdaleno.Manga-Reader",
                                    category: "mal-contract")

    static func runIfRequested(client: MALAuthenticatedClient) {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-mal-contract-read"),
           arguments.indices.contains(index + 1),
           let malID = Int(arguments[index + 1]) {
            Task { await read(malID: malID, client: client) }
        }
        if let index = arguments.firstIndex(of: "-mal-contract-restore"),
           arguments.indices.contains(index + 2),
           let malID = Int(arguments[index + 1]),
           let chapters = Int(arguments[index + 2]) {
            Task { await restore(malID: malID, to: chapters, client: client) }
        }
    }

    private static func read(malID: Int, client: MALAuthenticatedClient) async {
        do {
            guard let status = try await client.listStatus(mangaID: malID) else {
                log.notice("CONTRACT READ \(malID, privacy: .public): NOT LISTED")
                return
            }
            log.notice("""
                CONTRACT READ \(malID, privacy: .public): \
                status=\(status.status, privacy: .public) \
                chapters=\(status.numChaptersRead, privacy: .public)
                """)
        } catch {
            log.notice("CONTRACT READ \(malID, privacy: .public) FAILED: \(String(describing: error), privacy: .public)")
        }
    }

    private static func restore(malID: Int, to chapters: Int, client: MALAuthenticatedClient) async {
        do {
            guard let before = try await client.listStatus(mangaID: malID) else {
                log.notice("CONTRACT RESTORE \(malID, privacy: .public): NOT LISTED — refusing to add")
                return
            }
            let after = try await client.updateProgress(
                mangaID: malID,
                update: MALListStatusUpdate(numChaptersRead: chapters))
            log.notice("""
                CONTRACT RESTORE \(malID, privacy: .public): \
                was=\(before.numChaptersRead, privacy: .public) \
                now=\(after.numChaptersRead, privacy: .public) \
                status=\(after.status, privacy: .public)
                """)
            if after.numChaptersRead != chapters {
                log.notice("CONTRACT RESTORE \(malID, privacy: .public): ACCOUNT LEFT ALTERED")
            }
        } catch {
            log.notice("CONTRACT RESTORE \(malID, privacy: .public): ACCOUNT LEFT ALTERED — \(String(describing: error), privacy: .public)")
        }
    }
}
#endif
```
