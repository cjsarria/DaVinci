#!/usr/bin/env bash
# Run benchmark suite in smoke mode and capture full output to Artifacts/bench/smoke.log.
# Smoke mode: PIN scenarios are SKIPPED; suite finishes in ~1–2 min.
# Uses a DEDICATED derivedDataPath (.derivedData/smoke) so the test binary is ALWAYS freshly built (no cache).
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
mkdir -p Artifacts/bench
DEST='platform=iOS Simulator,name=iPhone 16'

# Dedicated derived data for smoke: hard-delete at start so we always use latest compiled test binary.
SMOKE_DERIVED="$REPO_ROOT/.derivedData/smoke"
echo "[SMOKE] Removing existing smoke derived data: $SMOKE_DERIVED"
rm -rf "$SMOKE_DERIVED"
mkdir -p "$SMOKE_DERIVED"

export DAVINCI_BENCH_SMOKE=1

echo "[SMOKE] Building for testing (derivedDataPath=$SMOKE_DERIVED)..."
xcodebuild build-for-testing \
  -scheme DaVinci \
  -destination "$DEST" \
  -derivedDataPath "$SMOKE_DERIVED" \
  -only-testing:DaVinciBenchmarksTests \
  2>&1 | tail -8

# xctestrun MUST be inside our smoke derived data; fail loudly if not found.
XCTESTRUN=$(find "$SMOKE_DERIVED" -name "*.xctestrun" -type f 2>/dev/null | head -1)
if [ -z "$XCTESTRUN" ]; then
  echo "[SMOKE] ERROR: No .xctestrun found under $SMOKE_DERIVED. Cannot run test-without-building." >&2
  find "$SMOKE_DERIVED" -type f -name "*.xctestrun" 2>/dev/null || true
  exit 1
fi

echo "[SMOKE] Resolved xctestrun: $XCTESTRUN"
echo "[SMOKE] Bundle/target: DaVinciBenchmarksTests"

echo "[SMOKE] Patching xctestrun to pass DAVINCI_BENCH_SMOKE=1 to test process..."
python3 "$SCRIPT_DIR/patch_xctestrun_smoke.py" "$XCTESTRUN" || true

echo "[SMOKE] Running smoke suite (output → Artifacts/bench/smoke.log)..."
xcodebuild test-without-building \
  -xctestrun "$XCTESTRUN" \
  -destination "$DEST" \
  -only-testing:DaVinciBenchmarksTests \
  2>&1 | tee Artifacts/bench/smoke.log

echo "[SMOKE] Done. Check for 'SMOKE_EARLY_RETURN_ACTIVE' and 0 failures in Artifacts/bench/smoke.log"
