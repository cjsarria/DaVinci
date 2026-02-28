#!/usr/bin/env bash
# Copy the most recent DaVinciBenchmarks run from the iOS Simulator temp dir into
# Artifacts/bench/json/<timestamp>. Run after a full benchmark suite so parse_bench_json.py
# can read real metrics. Finds simulator device data/tmp/DaVinciBenchmarks and copies
# the newest timestamped folder.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
SIM_ROOT="$HOME/Library/Developer/CoreSimulator/Devices"
BENCH="DaVinciBenchmarks"
if [ ! -d "$SIM_ROOT" ]; then
  echo "Simulator data not found at $SIM_ROOT"
  exit 1
fi
SOURCE=$(find "$SIM_ROOT" -path "*/data/tmp/$BENCH" -type d 2>/dev/null | head -1)
if [ -z "$SOURCE" ]; then
  echo "No $BENCH folder found in simulator tmp. Run the benchmark suite first."
  exit 1
fi
LATEST=$(ls -1t "$SOURCE" 2>/dev/null | head -1)
if [ -z "$LATEST" ]; then
  echo "No timestamped run in $SOURCE"
  exit 1
fi
mkdir -p Artifacts/bench/json
DEST="$REPO_ROOT/Artifacts/bench/json/$LATEST"
cp -R "$SOURCE/$LATEST" "$DEST"
echo "Copied $SOURCE/$LATEST → $DEST"
echo "Run: python3 scripts/parse_bench_json.py --json-dir Artifacts/bench/json/$LATEST"
