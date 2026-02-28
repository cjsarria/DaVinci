# DaVinci — Ecosystem and Platforms

Phase C adds tvOS/visionOS, AsyncImage-style SwiftUI, progressive preview, and optional background URLSession.

---

## Platform support

DaVinci supports:

- **iOS 15+**
- **macOS 13+**
- **tvOS 15+**
- **visionOS 1+**

The same APIs (UIKit `dv.setImage`, SwiftUI `DaVinciImage` / `DaVinciAsyncImage`, `DaVinciClient.loadImage`) and caches apply. On tvOS and visionOS, `UIImage` is used (via UIKit). Use the library in apps and extensions on these platforms as on iOS; for extensions and widgets, see [APP_EXTENSIONS_AND_WIDGETS.md](APP_EXTENSIONS_AND_WIDGETS.md).

---

## AsyncImage-style SwiftUI API

For custom layouts (e.g. loading/success/failure UI), use **`DaVinciAsyncImage`** and **`DaVinciPhase`**:

```swift
DaVinciAsyncImage(url: url, options: .default) { phase in
    switch phase {
    case .empty:
        EmptyView()
    case .loading:
        ProgressView()
    case .success(let image, _):
        Image(uiImage: image)
            .resizable()
    case .failure:
        Image(systemName: "photo")
    }
}
```

`DaVinciPhase` is `.empty` | `.loading` | `.success(DVImage, ImageLoadMetrics?)` | `.failure(Error)`.

---

## Progressive preview (network)

When loading from **network**, you can receive a **small preview** first, then the full image:

```swift
let (image, metrics) = try await DaVinciClient.shared.loadImage(
    url: url,
    scale: scale,
    options: options,
    onPreview: { preview in
        // Called on main with a small decoded preview (~240pt) before the full decode.
        imageView.image = preview
    }
)
// Then the full image is returned and you can set it again (or the preview was already shown).
```

`onPreview` is only used when the image is loaded from the network (not from memory or disk) and the response body is larger than 2 KB. The preview is decoded at a small size (240×240 pt) and delivered on the main actor.

---

## Background URLSession

For **background downloads** (e.g. large images that should complete when the app is backgrounded), create a client with a custom **background** `URLSession`:

```swift
let config = URLSessionConfiguration.background(withIdentifier: "com.you.app.davinci")
let session = URLSession(configuration: config, delegate: myDelegate, delegateQueue: nil)
let client = DaVinciClient.makeDefault(configuration: .init(), session: session)
DaVinciClient.shared = client
```

**Important:** Background sessions do not use the default completion-handler style in the same way. Your app must:

1. Set a **delegate** on the session and implement `urlSession(_:task:didCompleteWithError:)` (and related) to handle completion.
2. In **AppDelegate** (or scene delegate), implement `application(_:handleEventsForBackgroundURLSession:completionHandler:)` and call the completion handler when the session finishes.

DaVinci’s `HTTPClient` uses `session.dataTask(with:completionHandler:)`. For a **background** configuration, the system may not call that completion handler while the app is in the background; the delegate is used instead. So full background support may require a custom HTTP client that uses the delegate. The `session` parameter to `makeDefault` allows you to pass a custom session; for simple background use (e.g. app still in foreground but you want a dedicated session), this is sufficient. For true “download in background and complete when app is suspended,” consider using `URLSessionDownloadTask` and a custom pipeline, or document that DaVinci is recommended for the default session with foreground loads.

---

## Summary

| Feature | API / note |
|--------|------------|
| **tvOS / visionOS** | Same Package.swift platforms; same APIs. |
| **AsyncImage-style** | `DaVinciAsyncImage(url:options:content:)` and `DaVinciPhase`. |
| **Progressive preview** | `loadImage(url:scale:options:onPreview:)`; preview delivered on main for network loads. |
| **Background session** | `DaVinciClient.makeDefault(configuration:session:)` with a custom `URLSession`; app handles delegate and background completion. |
