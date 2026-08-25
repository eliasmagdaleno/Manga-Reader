# Native UI Audit — 2026-08-24

Target: `Manga-Reader/Views` and `Manga-Reader/ContentView.swift`

## Score

| Dimension | Score | Evidence |
|---|---:|---|
| Accessibility | 3/4 | Semantic Dynamic Type mapping, 44 pt reader controls, accessibility values/actions, Reduce Motion and Reduce Transparency handling. Device-level VoiceOver traversal remains unverified. |
| Performance | 3/4 | Lazy containers and bounded card rendering are used; remote image behavior remains dependent on `AsyncImage` and network state. |
| Theming | 4/4 | Ink & Seal tokens cover light/dark surfaces, semantic color, typography, spacing, and reusable components. |
| Platform conformance | 4/4 | Native navigation, tab structure, sheets, menus, refresh, alerts, and accessibility APIs follow SwiftUI conventions. |
| Adaptivity | 3/4 | Library/category grids and the detail hero adapt to width and accessibility sizes; device capture exposed and prompted a fix for a Home section-header collision, while horizontal cover rails still merit stress testing. |
| **Total** | **17/20** | **Good native quality with one remaining verification gap.** |

## Findings

### [P1] Manual VoiceOver completion evidence is still missing

Source inspection confirms labels, values, selected states, custom actions, and combined elements, but it cannot prove traversal order or task completion. Verify browse → detail → start/continue → close reader, Library refresh, chapter mark read/unread, and empty-state navigation on a physical device or simulator with VoiceOver. Suggested command: `$impeccable audit`.

### [P2] Horizontal rails remain the least adaptive surface

Cover rails preserve visual rhythm at large text sizes, but fixed card geometry can separate metadata from the user's preferred reading size. Confirm clipping, focus order, and readable summaries at accessibility sizes. Suggested command: `$impeccable adapt`.

### [P2] Source scope has improved wording but retains conceptual overlap

Home's browse source, Search's local search source, and Settings' source configuration are now more explicit, yet still ask users to understand three scopes. Suggested command: `$impeccable clarify`.

### [P2] Service errors should be normalized before display

Adjacent Retry actions are now present, but some `errorMessage` content can still expose transport-oriented wording. Map common failures to task-oriented messages while retaining diagnostic detail for logs. Suggested command: `$impeccable harden`.

Finish with `$impeccable polish` after any additional fixes.

## Verification Record

- Static polishing detector: exit 0, raw result `[]` across 26 Swift UI files.
- Unit tests: 76 tests in 14 suites passed.
- Full UI suite: exercised the seeded iPhone 17 Pro fixture; one state-sensitive library-label assertion failed after reaching the intended detail screen. The accessibility-text settings case passed. Remaining live-network fixtures were intentionally stopped before completion.
- Build: iPhone 17 Pro and iPad Pro 13-inch (M5) builds succeeded. The final iPhone build also passed after the Home collision and Voice Control semantics fixes; existing Swift 6 concurrency warnings remain outside this UI audit.
- Device captures: iPhone light/dark/AX XXXL and iPad light/dark are stored under `screenshots/`. The first AX XXXL capture exposed overlapping Home header/action text; `iphone-axxxl-dark-fixed.png` confirms the action now stacks without collision.
- Voice Control semantics: source logos are decorative rather than stray traversal stops, source choices have short spoken input labels, and reader close/mode controls expose short spoken aliases.
- Manual VoiceOver traversal remains required for a strict completion-gate sign-off.
