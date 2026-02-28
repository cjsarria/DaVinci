# DaVinci — App Extensions and Widgets

DaVinci can be used inside **App Extensions** (e.g. Share Extension, Widget Extension) and **Widgets**. The same pipeline (memory → disk → network) and APIs apply, with a few constraints and recommendations.

---

## Using the shared client in extensions

- **`DaVinciClient.shared`** uses the same process as your app. In an **app extension**, the extension runs in a **separate process** from the main app, so the shared client in the extension has its **own** memory and disk caches (extension’s container, not the app’s).
- **Disk cache path:** `DiskImageCache.defaultDirectoryURL()` uses `FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!`, which in an extension points to the **extension’s** Caches directory. So app and extension do **not** share disk cache.
- **Memory:** Extension process memory limits are typically **lower** than the main app. Use a smaller memory cache and avoid loading many large images at once.

---

## Recommendations for extensions

1. **Smaller memory cache**  
   Create a custom client with a reduced memory cap and use it in the extension instead of relying on the default shared client:

   ```swift
   // In your extension, at startup:
   let config = DaVinciClient.Configuration(
       memoryCacheMaxCostBytes: 5 * 1024 * 1024, // 5 MB
       diskCache: .init(maxSizeBytes: 20 * 1024 * 1024, maxAge: 60 * 60 * 24 * 7)
   )
   DaVinciClient.shared = DaVinciClient.makeDefault(configuration: config)
   ```

2. **Limit concurrency**  
   The library already caps decode concurrency (default 4). In a widget or small extension, loading 1–3 images at a time is usually enough; avoid large prefetch lists.

3. **Prefetch**  
   Use prefetch sparingly in extensions; consider setting `DaVinciClient.lowDataModeEnabled = true` by default and only enabling prefetch when the extension is in the foreground or when the user has unlimited data.

4. **Clearing data**  
   If the user clears the app’s data, the **extension’s** caches are in the extension container. To clear extension caches from the main app, you would need to use App Groups and a shared container, or document that extension cache is cleared when the user deletes the app. For logout-from-app flows, call `DaVinciClient.clearSharedCaches()` in the **app**; the extension’s caches are separate unless you use a custom client with a shared container (see below).

---

## Optional: shared cache between app and extension

To share disk cache between the app and an extension (e.g. so the widget can show cached images):

1. **App Groups**  
   Enable an App Group for the app and the extension (e.g. `group.com.you.app`).

2. **Custom disk cache directory**  
   Create a `DiskImageCache` that uses the group container:

   ```swift
   guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.you.app") else { return }
   let diskCacheDir = groupURL.appendingPathComponent("Library/Caches/DaVinci", isDirectory: true)
   let diskCache = DiskImageCache(directoryURL: diskCacheDir, configuration: .init())
   ```

3. **Custom client**  
   Build a `DaVinciClient` with this disk cache and a small memory cache, and set it as shared in both the app and the extension (each process still has its own memory cache, but disk is shared).

---

## Widgets (WidgetKit)

- **Timeline provider:** Load images in your timeline provider using `DaVinciClient.shared.loadImage(url:...)` or a custom client. Prefer small `targetSize` to keep memory and decode time low.
- **SwiftUI:** Use `DaVinciImage(url: options:)` in the widget view as in the main app. Ensure URLs are valid when the widget is displayed (e.g. from your backend or cached).
- **Background refresh:** If the widget refreshes in the background, avoid starting many network requests; use cache-first and small prefetch or no prefetch.

---

## Summary

| Context        | Shared client | Disk cache        | Memory |
|----------------|---------------|--------------------|--------|
| Main app       | Same process  | App Caches         | Normal |
| Extension      | Extension process | Extension Caches | Prefer smaller cap |
| Widget         | Same as extension if in same target | Extension Caches (or App Group) | Prefer smaller cap |

- Use a **smaller** `Configuration` (memory + disk) in extensions and widgets.
- Optionally use **App Groups** and a custom `DiskImageCache` directory to share disk cache between app and extension.
- Call **`DaVinciClient.clearSharedCaches()`** in each process (app and extension) if you need to clear caches on logout, unless you use a shared container and a single logical cache.
