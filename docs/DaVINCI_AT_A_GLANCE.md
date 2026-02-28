# DaVinci at a Glance

One-page overview of flow, cancellation, threading, and options.

---

## Flow

1. **View API** — `imageView.dv.setImage(with: url)` (or SwiftUI `DaVinciImage(url: url)`).
2. **Cancel previous** — If the view had another URL in progress, that task is cancelled (token check).
3. **Idempotent** — If `url == imageView.dv.currentImageURL`, nothing is done and completion is not called.
4. **Load pipeline** — `DaVinciClient.shared.loadImage(url:scale:options:)`:
   - **Memory** → return if cached (no decode).
   - **Disk** → read, decode (with optional downsampling), fill memory cache, return.
   - **Network** → `ImageTaskCoordinator` (deduplicates by URL), HTTP, decode, write to disk + memory, return.
5. **Apply** — On main thread: token check, set `imageView.image`, call completion, update `currentImageURL`.

---

## Cancellation

- Each `setImage` creates a new **token**. When the async load finishes, the view checks `token == currentToken`; if not (e.g. cell reused with a different URL), the result is ignored and the image is not set.
- Cancelling the in-flight task is done when starting a new load (different URL) via `dv_cancelCurrentImageTask()`.
- **Same URL:** If the new URL equals `currentImageURL`, no cancel and no new task (idempotent).

---

## Threading

- **Completion:** The public completion from `setImage(with:options:completion:)` is **always invoked on the main thread** so you can safely update UI.
- **Load work:** HTTP, disk I/O, and decoding run off the main thread (coordinator actor, dedicated decode queue with a concurrency cap).
- **Metrics callback:** `DaVinciDebug.metricsCallback` is called on an arbitrary queue; dispatch to main if you update UI.

---

## Options (DaVinciOptions)

| Option | Purpose |
|--------|--------|
| `cachePolicy` | `.memoryAndDisk`, `.memoryOnly`, `.diskOnly`, `.noCache` |
| `priority` | `.normal`, `.high`, `.low`, … — affects `Task` priority and URLSession task priority |
| `targetSize` | Downsample to this size (e.g. cell size) to save memory |
| `placeholder` | Shown until the load completes |
| `transition` | `.none` or `.fade(duration)` |
| `processors` | Resize, crop, round corners, blur, etc. |
| `retryCount` | Number of retries on network failure |
| `logContext` | String passed to `DaVinciDebug` logs |

---

## Prefetch

- `ImagePrefetcher().prefetch([url1, url2, ...])` uses the same pipeline and caches.
- Prefetch runs with **low** priority by default; visible-item loads use **normal** (or high) and are preferred by the HTTP layer.
- After prefetch, `setImage(with: sameUrl)` will hit memory or disk and avoid network.

---

## Observability

- **Structured logging:** Set `DaVinciDebug.enabled = true` and `DaVinciDebug.logLevel` (e.g. `.info`). Logs include cache source, decode time, bytes.
- **Metrics callback:** Set `DaVinciDebug.metricsCallback = { url, metrics in ... }` to record every completed load (cache source, `networkTimeMs`, `decodeTimeMs`, `downloadedBytes`) without DEBUG prints.

---

## Related

- Demo app: [Examples/DaVinciLab/README.md](../Examples/DaVinciLab/README.md).
