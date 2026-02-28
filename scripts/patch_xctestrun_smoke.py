#!/usr/bin/env python3
"""Patch an xctestrun plist to add DAVINCI_BENCH_SMOKE=1 for the DaVinciBenchmarksTests target."""
import plistlib
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: patch_xctestrun_smoke.py <path to .xctestrun>", file=sys.stderr)
        return 1
    path = Path(sys.argv[1])
    if not path.exists():
        print(f"File not found: {path}", file=sys.stderr)
        return 1
    with open(path, "rb") as f:
        plist = plistlib.load(f)
    configs = plist.get("TestConfigurations") or []
    for config in configs:
        for target in config.get("TestTargets") or []:
            if target.get("BlueprintName") == "DaVinciBenchmarksTests":
                env = target.get("EnvironmentVariables")
                if env is None:
                    target["EnvironmentVariables"] = {"DAVINCI_BENCH_SMOKE": "1"}
                else:
                    env["DAVINCI_BENCH_SMOKE"] = "1"
                with open(path, "wb") as f:
                    plistlib.dump(plist, f)
                print(f"Patched {path}: DAVINCI_BENCH_SMOKE=1 for DaVinciBenchmarksTests")
                return 0
    print("DaVinciBenchmarksTests target not found in xctestrun", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
