#!/bin/bash
#
# The cross-process half of the S3 spike (Host API design §16, evidence gate 2).
#
# `WKWebsiteDataStore(forIdentifier:)` vends the SAME live object for an identifier
# already open in this process, so a same-process "close and reopen" reads the session,
# not the disk. Durability can only be observed across two launches — which is what this
# script arranges: three separate `xcodebuild test` runs, three separate app processes.
#
#   1. verify BEFORE seeding  — must FAIL. Without it, a green step 3 proves nothing;
#                               it could be reading a store an earlier run left behind.
#   2. seed                   — one launch earns clearance.
#   3. verify AFTER relaunch  — must PASS, and the neighbouring Source must still see
#                               nothing.
#   4. cleanup                — removes the store so a re-run starts from step 1's red.
#
# The phases live in MangaCartaTests/WebKitPartitioningSpikeTests.swift and skip unless
# WEBKIT_SPIKE_PHASE selects them, so an ordinary `xcodebuild test` and CI run none.
#
# Usage: scripts/webkit-partitioning-spike.sh
set -uo pipefail

SCHEME="MangaCarta"
# Defaults to the repository's usual device. Override to re-run the experiment on another
# runtime — e.g. the iOS 17.5 runtime the design's evidence gate names:
#   xcodebuild -downloadPlatform iOS -buildVersion 17.5
#   UDID=$(xcrun simctl create spike "iPhone 15 Pro" com.apple.CoreSimulator.SimRuntime.iOS-17-5)
#   SPIKE_DESTINATION="platform=iOS Simulator,id=$UDID" scripts/webkit-partitioning-spike.sh
DESTINATION="${SPIKE_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
ONLY="MangaCartaTests/WebKitRelaunchSpikeTests"
LOG_DIR="${TMPDIR:-/tmp}/webkit-partitioning-spike"
mkdir -p "$LOG_DIR"

cd "$(dirname "$0")/.."

run_phase() {
  local phase="$1" log="$LOG_DIR/$1.log"
  # TEST_RUNNER_-prefixed shell variables reach the test process with the prefix
  # stripped. This works for the hosted unit bundle, not just UI tests.
  env "TEST_RUNNER_WEBKIT_SPIKE_PHASE=$phase" \
    xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" \
    -only-testing:"$ONLY" test-without-building >"$log" 2>&1
  local status=$?
  grep -E "^SPIKE|XCTAssert" "$log" | sed 's/^/    /'
  return $status
}

echo "building once; every phase reuses the same product..."
if ! xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" \
     build-for-testing >"$LOG_DIR/build.log" 2>&1; then
  echo "build failed; see $LOG_DIR/build.log" >&2
  exit 1
fi

# A wedged simulator fails every phase while naming no failing test. Boot it first.
xcrun simctl boot "${DESTINATION##*=}" >/dev/null 2>&1 || true

FAILED=0

echo "1/4 verify BEFORE seeding (expected to FAIL)"
if run_phase verify; then
  echo "  UNEXPECTED PASS: clearance was already there before this run seeded it." >&2
  echo "  A leftover store makes step 3 meaningless. Run phase 'cleanup' and retry." >&2
  FAILED=1
else
  echo "  failed as expected"
fi

echo "2/4 seed one launch"
if run_phase seed; then echo "  seeded"; else echo "  SEEDING FAILED" >&2; FAILED=1; fi

echo "3/4 verify AFTER relaunch (expected to PASS)"
if run_phase verify; then
  echo "  clearance survived the relaunch and stayed isolated"
else
  echo "  clearance did NOT survive the relaunch" >&2
  FAILED=1
fi

echo "4/4 cleanup"
run_phase cleanup >/dev/null 2>&1 || echo "  cleanup phase did not complete" >&2

echo
if [ "$FAILED" -eq 0 ]; then
  echo "RESULT: persistent + isolated. WKWebsiteDataStore(forIdentifier:) satisfies gate 2."
else
  echo "RESULT: gate 2 is NOT satisfied by this mechanism; logs in $LOG_DIR" >&2
fi
exit "$FAILED"
