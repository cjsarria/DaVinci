# DaVinci — Privacy and Data Ownership

This document describes how DaVinci uses storage and network so you can meet privacy and data-deletion requirements (e.g. GDPR, CCPA, or app-store guidelines).

---

## Where data lives

| Data | Location | Scope |
|------|----------|--------|
| **Memory cache** | In-process (RAM) | Decoded images; cleared when the app is terminated or when you call `clearAllCaches()` / `clearSharedCaches()`. |
| **Disk cache** | App Caches directory | Raw image bytes and metadata (e.g. ETag). Path: `FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("DaVinci")`. |

- All cache data is **scoped to your app**. DaVinci does not share caches with other apps or with the system outside the app container.
- DaVinci does **not** send any data to third-party servers. Network requests are only to the URLs you pass to `setImage(with:)` or `loadImage(url:)` (your own or your CDN). If you use `DaVinciDebug.metricsCallback`, it is your responsibility if that callback sends data off-device.

---

## Clearing data

When the user logs out or requests that their data be deleted, clear DaVinci’s caches so that cached images are not left on disk or in memory:

```swift
// Clear memory and disk for the shared client (most common)
DaVinciClient.clearSharedCaches()
```

If you use a custom `DaVinciClient` instance (e.g. for tests or a non-shared client), call:

```swift
myClient.clearAllCaches()
```

Call these from the main thread or any thread; they are safe to invoke when other loads may be in progress (in-flight loads will complete or fail; new loads will see empty caches).

---

## Low Data Mode and prefetch

To respect the system Low Data Mode (or a user “reduce data” setting), set:

```swift
DaVinciClient.lowDataModeEnabled = true
```

When `true`, **prefetch** will not start new network requests. Visible-item loads (via `setImage(with:)` or `loadImage`) are still performed so the UI can load images the user is viewing. You can tie `lowDataModeEnabled` to:

- **iOS:** `NWPathMonitor` and `path.isConstrained` (or `path.isExpensive`), or a user preference.
- **macOS:** Similarly use `NWPathMonitor` or a preference.

Example (iOS) using Network framework:

```swift
import Network

let monitor = NWPathMonitor()
monitor.pathUpdateHandler = { path in
    DaVinciClient.lowDataModeEnabled = path.isConstrained
}
monitor.start(queue: DispatchQueue.global(qos: .utility))
```

---

## Memory pressure

On iOS, DaVinci’s memory cache subscribes to `UIApplication.didReceiveMemoryWarningNotification`. When a memory warning occurs, the cache **trims** to reduce memory use (it keeps a fraction of the configured capacity). This helps avoid the system killing your app under memory pressure. No user data is sent off-device; only in-memory cached images are discarded or reduced.

---

## Summary

- **Data:** Memory + disk caches live in the app container; no cross-app or third-party sharing.
- **Deletion:** Call `DaVinciClient.clearSharedCaches()` (or `client.clearAllCaches()`) on logout or when the user requests data deletion.
- **Low Data:** Set `DaVinciClient.lowDataModeEnabled = true` when the system or user restricts data (e.g. Low Data Mode) so prefetch does not run.
- **Network:** Only your URLs are loaded; no telemetry or analytics by DaVinci.
