# DaVinci

[![CI](https://img.shields.io/github/actions/workflow/status/cjsarria/DaVinci/ci.yml?branch=main)](https://github.com/cjsarria/DaVinci/actions/workflows/ci.yml)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-F05138.svg)](https://swift.org)
[![Version](https://img.shields.io/github/v/tag/cjsarria/DaVinci)](https://github.com/cjsarria/DaVinci/releases)
[![SPM](https://img.shields.io/badge/SPM-supported-brightgreen.svg)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Deterministic image loading for Apple platforms.** One API. Scroll-safe. Production-ready.

DaVinci gives you predictable, high-performance image loading with a minimal API. Built on Swift concurrency and a single pipeline from request to render, it avoids the race conditions and callback complexity that plague many image libraries. You get token-based cancellation, idempotent same-URL semantics, and two-tier caching with ETag revalidation—without a large dependency graph or a separate DSL to learn.

```swift
imageView.dv.setImage(with: url)  // That's it.
```

---

## Why DaVinci

- **Deterministic** — Token-based cancellation and same-URL no-op mean no stale images in cells and no thrashing on reconfigure. What you request is what you get, or nothing.
- **Scroll-safe by default** — Every new URL cancels the previous load; completion is only called for the request that won. No callbacks after reuse.
- **Performance under load** — Single pipeline with URL deduplication, priority (visible vs prefetch), and off-main-thread decode. Handles long lists and cancellation storms without dropping frames.
- **Minimal API** — One method to load, one type for options. Fluent overrides where you need them; defaults that work everywhere.
- **Production-ready** — Two-tier cache (memory + disk), ETag/304, Low Data Mode, clear-on-logout, accessibility, and optional metrics. Ship it.

---

## Philosophy

Correctness and determinism come first. DaVinci does not fire-and-forget: when a view is reused or the user scrolls away, the previous task is cancelled and its completion is never invoked with stale data. Same URL on the same view is a no-op, so list reconfigures don't trigger redundant work. The pipeline is linear—Request → Scheduler → Fetch → Decode → Cache → Render—so behavior is observable and testable. No hidden queues, no callback ordering surprises.

---

## Designed For

- **Lists and feeds** — Table and collection views where cells are reused and scroll speed is high.
- **Swift concurrency** — Async/await and actors from the ground up; no legacy completion-handler APIs.
- **Apple platforms** — UIKit, SwiftUI, and programmatic loading share the same pipeline and caches.
- **Teams that care about correctness** — Tests can inject HTTP and caches; no network in unit tests.

---

## Lightweight by Design

DaVinci is a single Swift package with no external image or networking dependencies beyond the system. No subspecs, no optional modules. Add the package, configure defaults if you want, and use `imageView.dv.setImage(with: url)`. The API surface stays small: options are one type, processors are a closed set, and observability is opt-in. You get production behavior without the weight.

---

## Table of contents

- [Architecture](#architecture)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Usage](#usage)
  - [UIKit](#uikit)
  - [SwiftUI](#swiftui)
- [Options](#options)
- [Caching](#caching)
- [Prefetching](#prefetching)
- [Cancellation and reuse](#cancellation-and-reuse)
- [Downsampling](#downsampling)
- [Processors](#processors)
- [Privacy and Low Data Mode](#privacy-and-low-data-mode)
- [Accessibility](#accessibility)
- [Observability](#observability)
- [Migrating from Kingfisher or PINRemoteImage](#migrating-from-kingfisher-or-pinremoteimage)
- [DaVinciLab](#davincilab-benchmark-app)
- [Benchmarking](#benchmarking)
- [Documentation](#documentation)
- [🤝 Collaboration & Feedback](#collaboration-feedback)
- [License](#license)

---

## Architecture

DaVinci's pipeline is **Request → Scheduler → Fetch → Decode → Cache → Render**. Every load goes through the same path so behavior is predictable and observable.

```mermaid
flowchart LR
    A[Request] --> B[Scheduler]
    B --> C[Fetch]
    C --> D[Decode]
    D --> E[Cache]
    E --> F[Render]
```

| Stage | What happens |
|-------|----------------|
| **Request** | `setImage(with: url)` or `loadImage(url:)`; previous request for that view is cancelled; same URL → no-op (idempotent). |
| **Scheduler** | `ImageTaskCoordinator` deduplicates by URL, applies priority (visible vs prefetch); one network task per URL. |
| **Fetch** | HTTP via `URLSession` (memory/disk cache miss); ETag/304 for revalidation. |
| **Decode** | Off main thread via ImageIO; optional downsampling to `targetSize`; concurrency cap to avoid CPU spikes. |
| **Cache** | Memory (decoded image) and disk (raw bytes + metadata); then result returned. |
| **Render** | On main thread: token check, set `imageView.image` or SwiftUI state, run completion. |

---

## Requirements

- **iOS 15+** / **macOS 13+** / **tvOS 15+** / **visionOS 1+**
- **Swift 5.9+**
- **Xcode 15+** (recommended)

---

## Installation

Add DaVinci via **Swift Package Manager** in Xcode (File → Add Package Dependencies) or in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/cjsarria/DaVinci.git", from: "0.0.1")
]
```

Then add the `DaVinci` target to your app or package target.

---

## Quick start

**UIKit — load an image into an image view:**

```swift
import DaVinci
import UIKit

let imageView = UIImageView()
let url = URL(string: "https://example.com/photo.jpg")!
imageView.dv.setImage(with: url)
```

**SwiftUI — use the declarative view:**

```swift
import DaVinci
import SwiftUI

struct ProfileView: View {
    let avatarURL: URL
    var body: some View {
        DaVinciImage(url: avatarURL, options: .default) {
            Image(systemName: "person.circle.fill")
                .font(.largeTitle)
        }
    }
}
```

---

## Usage

### UIKit

**Basic load**

```swift
imageView.dv.setImage(with: url)
```

**With placeholder and options**

```swift
imageView.dv.setImage(
    with: url,
    placeholder: UIImage(systemName: "photo"),
    targetSize: CGSize(width: 120, height: 120),
    cachePolicy: .memoryAndDisk
)
```

**Using `DaVinciOptions` (recommended for full control)**

```swift
let options = DaVinciOptions(
    cachePolicy: .memoryAndDisk,
    priority: .normal,
    targetSize: CGSize(width: 120, height: 120),
    processors: [],
    retryCount: 1,
    transition: .fade(duration: 0.25)
)
options.placeholder = UIImage(systemName: "photo")
imageView.dv.setImage(with: url, options: options) { result, metrics in
    switch result {
    case .success(let image):
        print("Loaded: \(image.size), source: \(metrics?.cacheSource ?? .network)")
    case .failure(let error):
        print("Failed: \(error)")
    }
}
```

**In a collection view cell (scroll-safe)**

```swift
func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath) as! MyCell
    let item = items[indexPath.item]
    // Same URL as current? Idempotent — no reload.
    cell.imageView.dv.setImage(with: item.imageURL, options: cellOptions)
    return cell
}
```

**Check current image (e.g. to avoid redundant work)**

```swift
if imageView.dv.currentImageURL != newURL {
    imageView.dv.setImage(with: newURL)
}
```

### SwiftUI

`DaVinciImage` uses the same pipeline as UIKit (same caches and behavior).

```swift
DaVinciImage(url: url, options: .default) {
    Rectangle().fill(Color.gray.opacity(0.2))
}
```

With custom placeholder and metrics:

```swift
DaVinciImage(url: url, options: .default.withFade(0.2)) {
    ProgressView()
} onCompletion: { result, metrics in
    if let metrics { print("Source: \(metrics.cacheSource)") }
}
```

**AsyncImage-style (custom loading/success/failure):**

```swift
DaVinciAsyncImage(url: url, options: .default) { phase in
    switch phase {
    case .empty: EmptyView()
    case .loading: ProgressView()
    case .success(let image, _): Image(uiImage: image).resizable()
    case .failure: Image(systemName: "photo")
    }
}
```

---

## Options

`DaVinciOptions` controls caching, priority, size, and presentation.

| Property        | Purpose |
|----------------|--------|
| `cachePolicy`  | `.memoryAndDisk`, `.memoryOnly`, `.diskOnly`, `.noCache` |
| `priority`     | `.normal`, `.high`, `.low` — affects load order and URLSession task priority |
| `targetSize`   | Downsample to this size (e.g. cell size) to save memory |
| `placeholder`  | Shown until the load completes |
| `transition`   | `.none` or `.fade(duration:)` |
| `processors`   | Resize, crop, round corners, blur (order matters for cache key) |
| `retryCount`   | Number of retries on network failure |
| `logContext`   | String passed to `DaVinciDebug` logs |

**Example: fade transition**

```swift
let options = DaVinciOptions.default.withFade(0.2)
imageView.dv.setImage(with: url, options: options)
```

**App-wide defaults**

Set `DaVinciClient.defaultOptions` at launch; the overload `setImage(with: url, completion:)` (no `options` parameter) uses it.

```swift
// At app launch
DaVinciClient.defaultOptions = DaVinciOptions(cachePolicy: .memoryAndDisk, priority: .normal)
    .withFade(0.2)
// Later: uses defaultOptions
imageView.dv.setImage(with: url)
```

---

## Caching

DaVinci uses a **two-tier cache**:

1. **Memory** — Decoded `UIImage` instances (LRU, cost-based).
2. **Disk** — Raw image bytes in the app Caches directory, with metadata (ETag, expiry).

**Cache policy**

```swift
imageView.dv.setImage(with: url, cachePolicy: .memoryAndDisk)  // default
imageView.dv.setImage(with: url, cachePolicy: .memoryOnly)
imageView.dv.setImage(with: url, cachePolicy: .diskOnly)
imageView.dv.setImage(with: url, cachePolicy: .noCache)
```

**HTTP behavior**

- Conditional requests with **ETag / If-None-Match**.
- **Cache-Control: max-age** respected when present.
- On revalidation, **304 Not Modified** reuses cached bytes.

Disk cache is trimmed automatically by size and age so it does not grow without bound.

---

## Prefetching

Prefetch URLs so that the next `setImage(with: sameUrl)` hits memory or disk.

```swift
let prefetcher = ImagePrefetcher()
prefetcher.prefetch(urls, cachePolicy: .memoryAndDisk, priority: .low)
prefetcher.cancel(urls)  // cancel in-flight prefetches when needed
```

Prefetch uses **low** priority by default so visible-item loads are preferred.

---

## Cancellation and reuse

- **Cancel on new URL** — When you call `setImage(with: otherURL)`, the previous load is cancelled and the underlying network request is cancelled.
- **Idempotent same URL** — If you call `setImage(with: url)` and `url == imageView.dv.currentImageURL`, the call is a **no-op** (no new load, completion not called). Use this when reconfiguring cells to avoid redundant work.
- **Current URL** — `imageView.dv.currentImageURL` returns the URL of the image currently displayed (or last successfully loaded); `nil` if none.
- **Completion** — The completion handler is **always called on the main thread** so you can update UI safely.

---

## Downsampling

Pass `targetSize` to decode a smaller image (faster and lower memory). The disk cache still stores the original bytes; only the decoded result is sized.

```swift
imageView.dv.setImage(
    with: url,
    targetSize: CGSize(width: 120, height: 120),
    cachePolicy: .memoryAndDisk
)
```

Use the size of your image view (e.g. cell size) for optimal results.

---

## Processors

Processors run off the main thread and are part of the memory cache key (order matters).

```swift
let options = DaVinciOptions(
    targetSize: CGSize(width: 120, height: 120),
    processors: [
        RoundCornersProcessor(radius: 12),
        BlurProcessor(radius: 2)
    ]
).withFade(0.2)
imageView.dv.setImage(with: url, options: options)
```

Available processors: `ResizeProcessor`, `CropProcessor`, `RoundCornersProcessor`, `BlurProcessor`.

---

## Privacy and Low Data Mode

- **Clearing caches:** Call `DaVinciClient.clearSharedCaches()` when the user logs out or requests data deletion (e.g. for GDPR). This clears both memory and disk caches.
- **Low Data Mode:** Set `DaVinciClient.lowDataModeEnabled = true` when the system or user restricts data (e.g. from `NWPathMonitor.path.isConstrained`). Prefetch will not start new network requests; visible-item loads still run. See [Privacy and data](docs/PRIVACY_AND_DATA.md).

---

## Accessibility

Set an **accessibility label** so VoiceOver can describe the image:

```swift
var options = DaVinciOptions.default
options.accessibilityLabel = "Product photo: blue running shoes"
imageView.dv.setImage(with: url, options: options)
```

See [Accessibility](docs/ACCESSIBILITY.md) for Dynamic Type and Reduce Motion.

---

## Observability

**Structured logging**

```swift
DaVinciDebug.enabled = true
DaVinciDebug.logLevel = .info
```

**Metrics callback** (every completed load: cache source, decode time, bytes)

```swift
DaVinciDebug.metricsCallback = { url, metrics in
    // Called on an arbitrary queue — dispatch to main if updating UI.
    DispatchQueue.main.async {
        print(metrics.cacheSource, metrics.decodeTimeMs ?? 0, metrics.downloadedBytes ?? 0)
    }
}
```

**Debug overlay** (DEBUG builds only — badge showing M/D/N for cache source)

```swift
imageView.dv.enableDebugOverlay()
```

---

## Migrating from Kingfisher or PINRemoteImage

DaVinci's API is close to Kingfisher and PINRemoteImage, so switching is mostly a find-and-replace plus a few option renames.

### From Kingfisher

| Kingfisher | DaVinci |
|------------|---------|
| `imageView.kf.setImage(with: url)` | `imageView.dv.setImage(with: url)` |
| `imageView.kf.setImage(with: url, placeholder: img)` | `imageView.dv.setImage(with: url, placeholder: img)` |
| `imageView.kf.setImage(with: url, options: [.transition(.fade(0.2))])` | `imageView.dv.setImage(with: url, options: .default.withFade(0.2))` |
| `ImageCache.default.clearMemoryCache()` | `DaVinciClient.clearSharedCaches()` (memory + disk) |
| `ImagePrefetcher().startPrefetching(urls)` | `ImagePrefetcher().prefetch(urls)` |
| `imageView.kf.cancelDownloadTask()` | Automatic when you call `setImage(with: newURL)` |

**Options:** Use `DaVinciOptions(cachePolicy:priority:targetSize:processors:...)` and `options.placeholder`; transitions use `.withFade(duration)`. Processors (resize, round corners, blur) are in `DaVinciOptions.processors` and run off the main thread like Kingfisher.

**SwiftUI:** Replace `KFImage(url)` with `DaVinciImage(url: url, options: .default) { placeholder }` or use `DaVinciAsyncImage` for phase-based UI (loading/success/failure).

### From PINRemoteImage

| PINRemoteImage | DaVinci |
|----------------|---------|
| `imageView.pin_setImage(from: url)` | `imageView.dv.setImage(with: url)` |
| `imageView.pin_setImage(from: url, completion: { ... })` | `imageView.dv.setImage(with: url) { result, metrics in ... }` |
| `imageView.pin_cancelImageDownload()` | Automatic when you call `setImage(with: newURL)` |
| Prefetch / cancel | `ImagePrefetcher().prefetch(urls)` / `prefetcher.cancel(urls)` |

**Priority:** Set `DaVinciOptions(priority: .high)` for visible items; prefetch uses low priority by default so visible loads win. **Metrics:** Use `DaVinciDebug.metricsCallback` or the completion's `ImageLoadMetrics` (cache source, decode time, bytes) instead of PIN's cache flags.

**Steps to migrate:** Add the DaVinci package, replace `kf.` / `pin_` calls with `dv.` and the table above, remove the old dependency, then run and fix any option names (e.g. processor types) to match DaVinci's API.

---

## DaVinciLab Benchmark App

The repo includes a benchmark and showcase app at `Examples/DaVinciLab` that compares:

- **DaVinci**
- **Kingfisher**
- **PINRemoteImage**

**Run**

- Open `Examples/DaVinciLab/Package.swift` (or the Xcode project under `Examples/DaVinciLab/XcodeApp`) in Xcode.
- Select the **DaVinciLabApp** scheme and run on an iOS 15+ simulator or device.

**Run on device**

- Use the Xcode project under `Examples/DaVinciLab/XcodeApp` for device installs. Configure signing in Signing & Capabilities. See `Examples/DaVinciLab/README.md` for details.

**Benchmark**

- **Warm** — Reloads the feed without clearing caches.
- **Cold** — Clears caches for all engines and reloads.
- Tap **Run** to start an auto-scroll benchmark; tap **Export** to share a JSON report (device, mode, duration, per-engine metrics).

Same dataset and feed UI are used for all engines for a fair comparison. For methodology and example report format, see **[Benchmarks](docs/BENCHMARKS.md)**.

---

## Benchmarking

**Run smoke** (quick validation; PIN scenarios skipped):

```bash
bash scripts/run_bench_smoke_capture.sh
```

**Run full** (all scenarios, real metrics):

```bash
bash scripts/run_bench_full_capture.sh
```

Artifacts are generated locally under:

`Benchmarks/Results/<run_id>/`

Each run produces raw JSON and (after the script runs the parser) `SUMMARY.md` and `REPORT.md` in that folder.

Benchmark results depend on device, simulator, and environment. Run locally for authoritative results.

---

## Proof: Benchmarks & Reliability

A **deterministic benchmark suite** compares DaVinci, Kingfisher, and PINRemoteImage under identical conditions (mock network, same payloads). No internet required; suitable for CI and local proof.

- **Harness:** `DaVinciBenchmarksTests` (XCTest). Uses `MockURLProtocol` for DaVinci/Kingfisher and a small in-process HTTP server for PIN so all three see the same data and latency. No random data: payloads and latency are seeded for reproducibility.
- **Scenarios:** Cold cache (200 images), warm cache, dedup (same URL 100× concurrent), cancellation storm, memory pressure (scroll sim).
- **Output:** JSON per run under the test run's artifact directory; `REPORT.md` can be generated from results (see `ArtifactWriter` in the test target).

The benchmark tests use UIKit and must run on an **iOS Simulator**. The `swift test` command does not support a simulator destination; use **xcodebuild** from the repo root. List simulators: `xcrun simctl list devices available | grep iPhone`.

### Commands

| Goal | Command | Typical duration |
|------|--------|------------------|
| **Single-test sanity** (correctness gate) | `xcodebuild test -scheme DaVinci -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DaVinciBenchmarksTests/BenchmarkScenariosTests/testColdCache_Load200_DaVinci` | ~30–60 s |
| **Smoke: full suite, small counts** (PIN skipped) | `export DAVINCI_BENCH_SMOKE=1` then `xcodebuild test -scheme DaVinci -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DaVinciBenchmarksTests` | ~1–2 min |
| **Capture smoke log** | `./scripts/run_bench_smoke_capture.sh` → `Artifacts/bench/smoke.log` | ~1–2 min |
| **Run smoke twice** (check for flakiness) | `bash scripts/run_bench_smoke_twice.sh` | ~2 min |
| **Full benchmark** (real metrics) | `./scripts/run_bench_full_capture.sh` or same xcodebuild **without** `DAVINCI_BENCH_SMOKE` | 5–15+ min |

- **When to run single-test:** Before committing; quick check that the harness and one engine path work.
- **When to run smoke:** Before merging; full scenario coverage with small counts; **PIN scenarios are skipped in smoke** so the suite finishes in ~1 min without LocalBenchServer. Use `scripts/run_bench_smoke_twice.sh` to confirm two consecutive passes.
- **When to run full mode:** When you need real numbers for REPORT.md or comparisons (DaVinci vs Kingfisher vs PIN). Not required for routine correctness.

Use any simulator name from the list (e.g. `iPhone 16 Pro`). In **Xcode**: open the package, select the **DaVinci** scheme, choose an iOS Simulator, then **Product → Test** (⌘U). For smoke in Xcode, add **Environment Variable** `DAVINCI_BENCH_SMOKE=1` in the scheme's Test action.

**Artifacts:** Full-run output is written to `Benchmarks/Results/<run_id>/` (raw JSON, `SUMMARY.md`, `REPORT.md`). Smoke and full logs are written locally to `Artifacts/bench/` (not committed).

### Latest captured results

**Last updated:** 2026-02-26

After a full run, results are in `Benchmarks/Results/<run_id>/` with `SUMMARY.md` and `REPORT.md`. The table below shows the expected scenario structure; DaVinci and Kingfisher for key scenarios, PIN only in full mode.

| Scenario | Engine | Duration (s) | Network starts |
|----------|--------|--------------|----------------|
| ColdCache_Load200 | DaVinci | — | 200 |
| ColdCache_Load200 | Kingfisher | — | 200 |
| WarmCache_Load200 | DaVinci | — | (cached) |
| Dedup_SameURL_100Concurrent | DaVinci | — | 1 |
| Dedup_SameURL_100Concurrent | Kingfisher | — | 1 |
| CancellationStorm | DaVinci | — | — |
| MemoryPressure_ScrollSim | DaVinci | — | — |
| ColdCache_Load200 | PINRemoteImage | (full only) | 200 |

See `Benchmarks/Results/<run_id>/SUMMARY.md` and `REPORT.md` after a full run for the comparison table and caveats.

- **Smoke:** With `DAVINCI_BENCH_SMOKE=1` (via [run_bench_smoke_capture.sh](scripts/run_bench_smoke_capture.sh) or xctestrun patch), log shows `[BENCH] SKIP: PINRemoteImage scenarios disabled in smoke mode` and PIN test *skipped*; suite ~1–2 min.
- **Full:** DaVinci/Kingfisher use MockURLProtocol; PIN uses LocalBenchServer. The full-capture script writes to `Benchmarks/Results/<run_id>/` and runs the parser to generate `SUMMARY.md` and `REPORT.md`.

---

## Documentation

- **[Getting started from scratch](docs/GETTING_STARTED_FROM_SCRATCH.md)** — Step-by-step: new Xcode app, add DaVinci, run on simulator or device (no Examples folder).
- **[CHANGELOG](CHANGELOG.md)** — Version history and semantic versioning.
- **[DaVinci at a glance](docs/DaVINCI_AT_A_GLANCE.md)** — Flow, cancellation, threading, options, prefetch, observability.
- **[Privacy and data](docs/PRIVACY_AND_DATA.md)** — Where data lives, clearing caches, Low Data Mode.
- **[Accessibility](docs/ACCESSIBILITY.md)** — VoiceOver, Dynamic Type, Reduce Motion, and `accessibilityLabel` in options.
- **[App Extensions and Widgets](docs/APP_EXTENSIONS_AND_WIDGETS.md)** — Using DaVinci in extensions and widgets; smaller cache; App Groups.
- **[Ecosystem and platforms](docs/ECOSYSTEM_AND_PLATFORMS.md)** — tvOS/visionOS, `DaVinciAsyncImage` / `DaVinciPhase`, progressive preview, background URLSession.

**Generate API docs (DocC):** `swift package generate-documentation` (uses the Swift-DocC plugin).

---

<a id="collaboration-feedback"></a>

## 🤝 Collaboration & Feedback

Feedback, ideas, and collaboration are always welcome.

For discussions around performance, architecture, or potential integrations, the fastest way to reach me is via LinkedIn:

**Carlos Sarria**  
LinkedIn: [linkedin.com/in/carlossarria](https://www.linkedin.com/in/carlossarria/)

---

## License

See the [LICENSE](LICENSE) file in this repository (if present). Contributions are welcome; please open an issue or pull request.
