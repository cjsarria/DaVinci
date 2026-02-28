# Changelog

All notable changes to DaVinci are documented here. The project follows [Semantic Versioning](https://semver.org/): **MAJOR.MINOR.PATCH** (e.g. `1.2.3`). Pre-1.0 versions may introduce breaking changes in MINOR versions.

---

## [Unreleased]

### Added
- (Changes in development.)

---

## [0.3.0] — Phase C (Ecosystem)

### Added
- **tvOS 15+** and **visionOS 1+** platform support (Package.swift).
- **AsyncImage-style SwiftUI:** `DaVinciAsyncImage(url:options:content:)` and `DaVinciPhase` (`.empty`, `.loading`, `.success`, `.failure`) for custom loading/success/failure layouts.
- **Progressive preview:** `loadImage(url:scale:options:onPreview:)`; when `onPreview` is set and the image is loaded from network, a small preview (~240pt) is decoded and delivered on main before the full image.
- **Background URLSession:** `DaVinciClient.makeDefault(configuration:session:)` accepts an optional custom `URLSession` (e.g. background configuration); app must handle delegate and `application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
- [ECOSYSTEM_AND_PLATFORMS.md](docs/ECOSYSTEM_AND_PLATFORMS.md): platforms, AsyncImage-style API, progressive preview, background session.

### Changed
- None (additive only).

### Fixed
- None.

---

## [0.2.0] — Phase A & B (Flagship foundation and polish)

### Added
- **Phase A**
  - `DaVinciClient.lowDataModeEnabled`: when `true`, prefetch does not start network requests (respect Low Data Mode or user preference).
  - `DaVinciClient.clearAllCaches()` and `DaVinciClient.clearSharedCaches()` for privacy and logout flows.
  - `DaVinciOptions.accessibilityLabel`: set the image view’s VoiceOver label after a successful load.
  - [PRIVACY_AND_DATA.md](docs/PRIVACY_AND_DATA.md): data location, clearing caches, Low Data Mode, memory pressure.
  - [ACCESSIBILITY.md](docs/ACCESSIBILITY.md): VoiceOver, Dynamic Type, Reduce Motion.
  - GitHub Actions CI: build, test, and iOS destination.
- **Phase B**
  - [APP_EXTENSIONS_AND_WIDGETS.md](docs/APP_EXTENSIONS_AND_WIDGETS.md): using DaVinci in extensions and widgets; smaller cache config; optional App Groups.
  - **Reduce Motion:** Fade transition is skipped when `UIAccessibility.isReduceMotionEnabled` is true.
  - **DocC:** `DaVinci.docc` catalog and swift-docc-plugin dependency; run `swift package generate-documentation` to build docs.
  - **App-wide defaults:** `DaVinciClient.defaultOptions`; overload `setImage(with: url, completion:)` uses it when you omit options.
  - This CHANGELOG and semantic versioning.

### Changed
- None (additive only).

### Fixed
- None.

---

## [0.1.0] — Initial and refactor (Stages 1–4)

### Added
- Idempotent `setImage` (same URL → no-op); `imageView.dv.currentImageURL`.
- Completion always on main thread; HTTP task priority; decode concurrency cap; metrics callback.
- Two-tier cache (memory + disk), ETag/304, downsampling, processors, prefetch.
- UIKit and SwiftUI APIs; DaVinciLab benchmark app.
- [DaVINCI_AT_A_GLANCE.md](docs/DaVINCI_AT_A_GLANCE.md).

---

[Unreleased]: https://github.com/cjsarria/DaVinci/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/cjsarria/DaVinci/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/cjsarria/DaVinci/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/cjsarria/DaVinci/releases/tag/v0.1.0
