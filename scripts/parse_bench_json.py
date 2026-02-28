#!/usr/bin/env python3
"""
Parse DaVinci benchmark JSON artifacts and emit summary + REPORT (+ optional SUMMARY.md in run dir).
Usage:
  scripts/parse_bench_json.py [--json-dir PATH] [--output-dir PATH]
If --json-dir is omitted, uses the most recent directory under Artifacts/bench/json/.
Reads all <engine>/<scenario>.json files. Expected JSON keys: scenario, engine, durationSeconds, networkStartCount, totalRequests.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

REQUIRED_KEYS = ("scenario", "engine")  # durationSeconds, networkStartCount expected but defaulted if missing


def find_latest_json_dir(repo_root: Path) -> Path | None:
    bench_json = repo_root / "Artifacts" / "bench" / "json"
    if not bench_json.exists():
        return None
    dirs = sorted([d for d in bench_json.iterdir() if d.is_dir()], reverse=True)
    return dirs[0] if dirs else None


def load_results(json_dir: Path) -> list[dict]:
    results = []
    for engine_dir in json_dir.iterdir():
        if not engine_dir.is_dir():
            continue
        for f in engine_dir.glob("*.json"):
            with open(f, encoding="utf-8") as fp:
                data = json.load(fp)
            if not isinstance(data, dict):
                raise SystemExit(f"Unexpected JSON schema in {f}: root is not an object")
            for key in REQUIRED_KEYS:
                if key not in data:
                    raise SystemExit(f"Unexpected JSON schema in {f}: missing required key '{key}'")
            data.setdefault("durationSeconds", 0)
            data.setdefault("networkStartCount", 0)
            if "engine" not in data or data["engine"] is None:
                data["engine"] = engine_dir.name
            results.append(data)
    return results


def run_cmd(cmd: list[str]) -> str:
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "—"


def write_summary_md(results: list[dict], out_path: Path, run_timestamp: str) -> None:
    by_scenario: dict[str, list[dict]] = {}
    for r in results:
        sc = r.get("scenario", "?")
        by_scenario.setdefault(sc, []).append(r)

    lines = [
        "# Benchmark summary",
        "",
        f"*From JSON artifacts (run: {run_timestamp})*",
        "",
        "| Scenario | Engine | Duration (s) | Network starts | Total requests | Notes |",
        "|----------|--------|--------------|----------------|----------------|-------|",
    ]
    for scenario in sorted(by_scenario.keys()):
        for r in sorted(by_scenario[scenario], key=lambda x: x.get("engine", "")):
            eng = r.get("engine", "?")
            dur = r.get("durationSeconds")
            dur_s = f"{dur:.2f}" if isinstance(dur, (int, float)) else "—"
            net = r.get("networkStartCount", "—")
            total = r.get("totalRequests", "—")
            note = ""
            if eng == "PINRemoteImage":
                note = "LocalBenchServer (full only)"
            elif r.get("dedupSupported") is True:
                note = "dedup"
            lines.append(f"| {scenario} | {eng} | {dur_s} | {net} | {total} | {note} |")
    lines.extend(["", "PIN runs only in full mode; smoke skips PIN scenarios.", ""])
    out_path.write_text("\n".join(lines), encoding="utf-8")


def write_summary_for_run(results: list[dict], out_path: Path, run_id: str) -> None:
    """Write SUMMARY.md comparison table (DaVinci vs Kingfisher vs PIN) for FINAL_REPORT / run dir."""
    by_scenario: dict[str, list[dict]] = {}
    for r in results:
        sc = r.get("scenario", "?")
        by_scenario.setdefault(sc, []).append(r)
    lines = [
        "# Benchmark comparison",
        "",
        f"Run: {run_id}",
        "",
        "| Scenario | Engine | Duration (s) | Network starts | Total requests |",
        "|----------|--------|--------------|----------------|----------------|",
    ]
    for scenario in sorted(by_scenario.keys()):
        for r in sorted(by_scenario[scenario], key=lambda x: x.get("engine", "")):
            eng = r.get("engine", "?")
            dur = r.get("durationSeconds")
            dur_s = f"{dur:.2f}" if isinstance(dur, (int, float)) else "—"
            net = r.get("networkStartCount", "—")
            total = r.get("totalRequests", "—")
            lines.append(f"| {scenario} | {eng} | {dur_s} | {net} | {total} |")
    lines.extend([
        "",
        "Single-run values. DaVinci/Kingfisher use MockURLProtocol; PIN uses LocalBenchServer.",
        "",
    ])
    out_path.write_text("\n".join(lines), encoding="utf-8")


def write_report_md(
    results: list[dict],
    out_path: Path,
    run_timestamp: str,
    json_dir_name: str,
    dest: str,
) -> None:
    sw_vers = run_cmd(["sw_vers", "-productVersion"])
    uname_m = run_cmd(["uname", "-m"])
    xcode_vers = run_cmd(["xcodebuild", "-version"]).split("\n")[0] if run_cmd(["xcodebuild", "-version"]) != "—" else "—"

    by_scenario: dict[str, list[dict]] = {}
    for r in results:
        sc = r.get("scenario", "?")
        by_scenario.setdefault(sc, []).append(r)

    lines = [
        "# DaVinci benchmark report",
        "",
        f"- **Run timestamp:** {run_timestamp}",
        f"- **JSON source:** `Artifacts/bench/json/{json_dir_name}`",
        f"- **Machine:** macOS {sw_vers} ({uname_m})",
        f"- **Xcode:** {xcode_vers}",
        f"- **Simulator destination:** {dest}",
        "",
        "## Metrics",
        "",
        "| Scenario | Engine | Duration (s) | CPU (s) | Peak Mem (MB) | Network starts |",
        "|----------|--------|--------------|---------|---------------|----------------|",
    ]
    for scenario in sorted(by_scenario.keys()):
        for r in sorted(by_scenario[scenario], key=lambda x: x.get("engine", "")):
            eng = r.get("engine", "?")
            dur = r.get("durationSeconds")
            dur_s = f"{dur:.2f}" if isinstance(dur, (int, float)) else "—"
            cpu = r.get("cpuSeconds")
            cpu_s = f"{cpu:.2f}" if isinstance(cpu, (int, float)) else "—"
            mem = r.get("peakMemoryBytes")
            mem_s = f"{mem / 1_048_576:.1f}" if isinstance(mem, (int, float)) else "—"
            net = r.get("networkStartCount", "—")
            lines.append(f"| {scenario} | {eng} | {dur_s} | {cpu_s} | {mem_s} | {net} |")
    lines.extend([
        "",
        "## Caveats",
        "",
        "- **PINRemoteImage** uses LocalBenchServer (real TCP); DaVinci and Kingfisher use MockURLProtocol.",
        "- **Smoke mode** skips PIN scenarios so the suite finishes in ~1–2 min; PIN runs only in full mode.",
        "",
    ])
    out_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Parse benchmark JSON and emit summary + REPORT (+ SUMMARY.md in run dir)")
    parser.add_argument("--json-dir", type=Path, help="Directory containing engine subdirs with scenario JSON files")
    parser.add_argument("--output-dir", type=Path, help="If set, write SUMMARY.md and REPORT.md here (e.g. Benchmarks/Results/<run_id>)")
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--destination", type=str, default="platform=iOS Simulator,name=iPhone 16")
    args = parser.parse_args()

    repo = args.repo_root
    json_dir = args.json_dir or find_latest_json_dir(repo)
    if not json_dir or not json_dir.exists():
        print("No JSON dir found. Use --json-dir or run full benchmark and copy artifacts.", file=sys.stderr)
        return 1

    try:
        results = load_results(json_dir)
    except SystemExit as e:
        print(e, file=sys.stderr)
        return 1

    if not results:
        print(f"No JSON files found under {json_dir}", file=sys.stderr)
        return 1

    run_timestamp = json_dir.name.replace("_", " ") if json_dir.name.replace("_", " ").strip() else "unknown"
    bench_dir = repo / "Artifacts" / "bench"
    bench_dir.mkdir(parents=True, exist_ok=True)

    write_summary_md(results, bench_dir / "summary.md", run_timestamp)
    write_report_md(results, bench_dir / "REPORT.md", run_timestamp, json_dir.name, args.destination)

    if args.output_dir:
        args.output_dir.mkdir(parents=True, exist_ok=True)
        write_summary_for_run(results, args.output_dir / "SUMMARY.md", json_dir.name)
        write_report_md(results, args.output_dir / "REPORT.md", run_timestamp, json_dir.name, args.destination)
        print(f"Wrote {args.output_dir / 'SUMMARY.md'} and {args.output_dir / 'REPORT.md'} from {len(results)} results.")
    else:
        print(f"Wrote {bench_dir / 'summary.md'} and {bench_dir / 'REPORT.md'} from {len(results)} results.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
