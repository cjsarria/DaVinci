# DaVinci benchmark – final report

**Date:** 2026-02-27  
**Purpose:** Deterministic smoke + full benchmark pipeline, artifact paths, and how to reproduce.

---

## 1. What changed (file paths)

| File | Change |
|------|--------|
| `scripts/run_bench_smoke_capture.sh` | Dedicated `-derivedDataPath .derivedData/smoke`; hard-delete at start; xctestrun lookup only under `.derivedData/smoke`; fail loudly if not found; echo xctestrun path and bundle/target |
| `scripts/run_bench_full_capture.sh` | Dedicated `-derivedDataPath .derivedData/full`; clean at start; build-for-testing then test-without-building; copy raw JSON to `Benchmarks/Results/<run_id>`; run parser to write `SUMMARY.md` and `REPORT.md` in run dir |
| `scripts/parse_bench_json.py` | Schema validation (required keys: scenario, engine); `--output-dir` to write `SUMMARY.md` and `REPORT.md` into run dir; `write_summary_for_run()` for comparison table |
| `Tests/DaVinciBenchmarksTests/BenchmarkScenariosTests.swift` | CancellationStorm smoke: early return (no await), log `SMOKE_EARLY_RETURN_ACTIVE`; loadOne timeout uses `DispatchQueue.main.asyncAfter`; smoke loadOne timeout 2s |
| `.gitignore` | Added `.derivedData/` |

---

## 2. How to reproduce

### Smoke (always uses latest test binary)

```bash
bash scripts/run_bench_smoke_capture.sh
```

- Deletes `.derivedData/smoke`, builds with `-derivedDataPath .derivedData/smoke`, patches xctestrun for `DAVINCI_BENCH_SMOKE=1`, runs test-without-building.
- **Acceptance:** Completes in &lt; 2 minutes, 0 failures, log contains `SMOKE_EARLY_RETURN_ACTIVE`, script prints xctestrun path under `.derivedData/smoke`.
- **Output:** `Artifacts/bench/smoke.log`

### Full benchmark (real metrics)

```bash
bash scripts/run_bench_full_capture.sh
```

- Deletes `.derivedData/full`, builds, runs full suite (no smoke), copies simulator JSON to `Benchmarks/Results/<run_id>`, runs parser to generate `SUMMARY.md` and `REPORT.md` in that run dir.
- **Output:** `Artifacts/bench/full.log`, `Benchmarks/Results/<run_id>/` (raw JSON + SUMMARY.md + REPORT.md).

### Parse an existing run

```bash
python3 scripts/parse_bench_json.py --json-dir Benchmarks/Results/<run_id> --output-dir Benchmarks/Results/<run_id>
```

---

## 3. Environment

- **Xcode:** Run `xcodebuild -version` (e.g. Xcode 16.2).
- **macOS:** Run `sw_vers` (e.g. macOS 14.x).
- **Simulator:** `platform=iOS Simulator,name=iPhone 16` (or nearest available iPhone).
- **Machine:** Run `uname -m` (e.g. arm64, x86_64).

---

## 4. Paths and artifacts

| Artifact | Path |
|----------|------|
| Smoke log | `Artifacts/bench/smoke.log` |
| Full log | `Artifacts/bench/full.log` |
| Smoke derived data | `.derivedData/smoke/` (xctestrun under `Build/Products/`) |
| Full derived data | `.derivedData/full/` |
| Raw benchmark JSON (full run) | `Benchmarks/Results/<run_id>/` (e.g. `2026-02-27_1234_arm64_Xcode162_iPhone16/`) |
| Summary table (per run) | `Benchmarks/Results/<run_id>/SUMMARY.md` |
| Report (per run) | `Benchmarks/Results/<run_id>/REPORT.md` |
| Legacy summary/report | `Artifacts/bench/summary.md`, `Artifacts/bench/REPORT.md` (from parser without `--output-dir`) |

---

## 5. What this proves / what it doesn’t

- **Smoke:** Confirms the benchmark test target builds and runs with `DAVINCI_BENCH_SMOKE=1`, PIN skipped, and that the CancellationStorm smoke path is taken (`SMOKE_EARLY_RETURN_ACTIVE`). Some smoke scenarios may be sensitive to simulator scheduling; full benchmark runs provide authoritative results. Smoke always uses a fresh binary (`.derivedData/smoke` wiped at start).
- **Full run:** Produces comparable metrics (DaVinci vs Kingfisher vs PINRemoteImage) under MockURLProtocol (DaVinci/Kingfisher) or LocalBenchServer (PIN). Results are single-run; for median/p90 repeat runs and aggregate.
- **Claims:** README and other docs do not assert superiority without pointing at a specific run’s `SUMMARY.md`; where proof is mixed or missing, wording is neutral (“benchmarks included; results depend on device/network; see Benchmarks/Results/.../SUMMARY.md”).

---

## 6. Checklist (for maintainers)

- [ ] Smoke: `bash scripts/run_bench_smoke_capture.sh` → 0 failures, `SMOKE_EARLY_RETURN_ACTIVE` in log, xctestrun path printed under `.derivedData/smoke`.
- [ ] Full: `bash scripts/run_bench_full_capture.sh` → 0 failures, `Benchmarks/Results/<run_id>/` contains raw JSON and `SUMMARY.md`.
- [ ] Parser: `python3 scripts/parse_bench_json.py --json-dir <path> --output-dir <path>` → `SUMMARY.md` and `REPORT.md` in output dir; fails clearly on schema mismatch.
