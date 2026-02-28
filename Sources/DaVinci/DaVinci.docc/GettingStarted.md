# Getting Started with DaVinci

DaVinci is an async image loading library for iOS and macOS with a two-tier cache and scroll-safe behavior.

## Overview

- **One pipeline:** Memory → disk → network, with ETag/304 and Cache-Control support.
- **Scroll-safe:** Token-based cancellation and idempotent same-URL handling for lists.
- **Tunable:** Cache policy, priority, downsampling, processors, and observability.

## Quick start

### UIKit

```swift
import DaVinci

imageView.dv.setImage(with: url)
```

### SwiftUI

```swift
import DaVinci

DaVinciImage(url: url, options: .default) {
    Image(systemName: "photo")
}
```

## Learn more

- **README** — Installation, options, caching, prefetch, and documentation links.
- **DaVinci at a glance** — Flow, cancellation, threading, and options (in the `docs/` folder).
- **Privacy and data** — Where data lives, clearing caches, Low Data Mode (`docs/PRIVACY_AND_DATA.md`).
- **Accessibility** — VoiceOver, Reduce Motion (`docs/ACCESSIBILITY.md`).
