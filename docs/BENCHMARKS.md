# DaVinciLab Benchmarks

DaVinciLab compares **DaVinci**, **Kingfisher**, and **PINRemoteImage** on the same feed with the same dataset and settings. This document describes how benchmarks work and what proof you can capture.

---

## How the benchmark works

- **Mode:** **Cold** (caches cleared for all engines before run) or **Warm** (caches kept).
- **Duration:** Configurable (default 15 seconds). The app auto-scrolls the feed at a fixed step; images load as they enter view.
- **Metrics per engine:** Sample count, average load time (ms), average decode time (ms), cache hit rate (%), total bytes loaded.
- **Export:** After a run, tap **Export** to share a **JSON report** (device model, system version, mode, duration, settings, and per-engine snapshots). Use this as proof for your environment.

---

## What the report contains

The exported JSON is a `BenchmarkReport` with:

| Field | Meaning |
|-------|--------|
| `mode` | `"cold"` or `"warm"` |
| `durationSeconds` | Run length |
| `startedAt` / `finishedAt` | ISO8601 timestamps |
| `deviceModel` / `systemVersion` | Device and OS for reproducibility |
| `settings` | `prefetchEnabled`, `downsampleEnabled`, `fadeEnabled` |
| `snapshots` | Array of per-engine snapshots (one per engine): `engineName`, `count`, `avgLoadMs`, `avgDecodeMs`, `cacheHitRate`, `totalBytes` |

---

## Example output (proof)

Below is a **minimal example** of what an exported report looks like. Real numbers depend on device, network, and cache state.

```json
{
  "mode": "warm",
  "durationSeconds": 15,
  "startedAt": "2025-02-24T12:00:00Z",
  "finishedAt": "2025-02-24T12:00:15Z",
  "settings": {
    "prefetchEnabled": true,
    "downsampleEnabled": true,
    "fadeEnabled": true
  },
  "deviceModel": "iPhone",
  "systemVersion": "18.0",
  "snapshots": [
    {
      "engineName": "DaVinci",
      "timestamp": "2025-02-24T12:00:15Z",
      "count": 42,
      "avgLoadMs": 12.5,
      "avgDecodeMs": 3.2,
      "cacheHitRate": 0.85,
      "cacheHitRateIsEstimated": false,
      "totalBytes": 2457600,
      "totalBytesIsEstimated": false
    },
    {
      "engineName": "Kingfisher",
      "timestamp": "2025-02-24T12:00:15Z",
      "count": 42,
      "avgLoadMs": 11.8,
      "avgDecodeMs": 3.1,
      "cacheHitRate": 0.88,
      "cacheHitRateIsEstimated": false,
      "totalBytes": 2400000,
      "totalBytesIsEstimated": false
    },
    {
      "engineName": "PINRemoteImage",
      "timestamp": "2025-02-24T12:00:15Z",
      "count": 42,
      "avgLoadMs": 13.1,
      "avgDecodeMs": 3.4,
      "cacheHitRate": null,
      "cacheHitRateIsEstimated": true,
      "totalBytes": null,
      "totalBytesIsEstimated": true
    }
  ]
}
```

PINRemoteImage’s Swift API does not expose cache source or byte counts, so `cacheHitRate` and `totalBytes` may be `null` and marked estimated where applicable.

---

## How to get proof

1. Open **DaVinciLab** (see [Examples/DaVinciLab/README.md](../Examples/DaVinciLab/README.md)).
2. Choose **Cold** or **Warm** and tap **Run** to start the benchmark.
3. When the run finishes, the results screen shows a summary; tap **Export** to share the JSON.
4. Save or share the file (e.g. `DaVinciLabReport.json`) as proof for your device and settings.

Same dataset, same UI, and same toggles (prefetch, downsampling, fade) are used for all three engines so comparisons are fair.
