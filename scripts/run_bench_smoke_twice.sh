#!/usr/bin/env bash
# Run DaVinciBenchmarksTests in smoke mode twice. Exits 0 only if both runs pass.
# Use to validate non-flakiness before merging.
# Expect ~1 min per run; ensure an iOS Simulator is available.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
DEST='platform=iOS Simulator,name=iPhone 16'
TEST_TARGET="DaVinciBenchmarksTests"
export DAVINCI_BENCH_SMOKE=1

echo "Smoke run 1/2 (output streamed; ~1 min)..."
if xcodebuild test -scheme DaVinci -destination "$DEST" -only-testing:"$TEST_TARGET"; then
  R1=0
else
  R1=$?
fi

echo ""
echo "Smoke run 2/2..."
if xcodebuild test -scheme DaVinci -destination "$DEST" -only-testing:"$TEST_TARGET"; then
  R2=0
else
  R2=$?
fi

if [ "$R1" -eq 0 ] && [ "$R2" -eq 0 ]; then
  echo ""
  echo "Both smoke runs passed."
  exit 0
else
  echo ""
  echo "One or both runs failed (Run1=$R1 Run2=$R2)."
  exit 1
fi
