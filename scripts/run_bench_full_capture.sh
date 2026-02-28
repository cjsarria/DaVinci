#!/usr/bin/env bash
# Run full benchmark suite (no smoke): all scenarios including PIN.
# Uses dedicated .derivedData/full and persists raw JSON to Benchmarks/Results/<run_id>.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
mkdir -p Artifacts/bench
DEST='platform=iOS Simulator,name=iPhone 16'

# Do NOT set DAVINCI_BENCH_SMOKE so the test process runs in full mode.
unset DAVINCI_BENCH_SMOKE

# Dedicated derived data for full run; clean at start for deterministic build.
FULL_DERIVED="$REPO_ROOT/.derivedData/full"
echo "[FULL] Removing existing full derived data: $FULL_DERIVED"
rm -rf "$FULL_DERIVED"
mkdir -p "$FULL_DERIVED"

echo "[FULL] Building for testing (derivedDataPath=$FULL_DERIVED)..."
xcodebuild build-for-testing \
  -scheme DaVinci \
  -destination "$DEST" \
  -derivedDataPath "$FULL_DERIVED" \
  -only-testing:DaVinciBenchmarksTests \
  2>&1 | tail -8

XCTESTRUN=$(find "$FULL_DERIVED" -name "*.xctestrun" -type f 2>/dev/null | head -1)
if [ -z "$XCTESTRUN" ]; then
  echo "[FULL] ERROR: No .xctestrun found under $FULL_DERIVED." >&2
  exit 1
fi

echo "[FULL] Resolved xctestrun: $XCTESTRUN"
echo "[FULL] Running full benchmark suite (output → Artifacts/bench/full.log; may take 5–15+ min)..."
xcodebuild test-without-building \
  -xctestrun "$XCTESTRUN" \
  -destination "$DEST" \
  -only-testing:DaVinciBenchmarksTests \
  2>&1 | tee Artifacts/bench/full.log

# Build run_id: YYYY-MM-DD_HHMM_<machine>_<xcode>_<sim>
# e.g. 2026-02-26_1200_arm64_Xcode162_iPhone16
TIMESTAMP=$(date +"%Y-%m-%d_%H%M")
MACHINE=$(uname -m 2>/dev/null || echo "unknown")
XCODE_VER=$(xcodebuild -version 2>/dev/null | head -1 | sed 's/[^0-9]//g' | head -c 4)
SIM_NAME="iPhone16"
RUN_ID="${TIMESTAMP}_${MACHINE}_Xcode${XCODE_VER}_${SIM_NAME}"

RESULTS_ROOT="$REPO_ROOT/Benchmarks/Results"
RUN_DIR="$RESULTS_ROOT/$RUN_ID"
mkdir -p "$RUN_DIR"

# Copy raw JSON from simulator temp into repo (deterministic path).
SIM_ROOT="${HOME}/Library/Developer/CoreSimulator/Devices"
BENCH="DaVinciBenchmarks"
SOURCE=$(find "$SIM_ROOT" -path "*/data/tmp/$BENCH" -type d 2>/dev/null | head -1)
if [ -n "$SOURCE" ]; then
  LATEST=$(ls -1t "$SOURCE" 2>/dev/null | head -1)
  if [ -n "$LATEST" ]; then
    cp -R "$SOURCE/$LATEST"/* "$RUN_DIR/" 2>/dev/null || true
    echo "[FULL] Copied raw JSON: $SOURCE/$LATEST → $RUN_DIR"
  fi
fi

echo "[FULL] Raw results path: $RUN_DIR"
if [ -d "$RUN_DIR/DaVinci" ] || [ -d "$RUN_DIR/Kingfisher" ]; then
  python3 "$SCRIPT_DIR/parse_bench_json.py" --json-dir "$RUN_DIR" --output-dir "$RUN_DIR" && echo "[FULL] Wrote $RUN_DIR/SUMMARY.md and $RUN_DIR/REPORT.md"
fi
echo "[FULL] Done. Check Artifacts/bench/full.log and $RUN_DIR"
