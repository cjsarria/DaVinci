# DaVinciLab

A working demo app that shows how to use **DaVinci** and compare it with **Kingfisher** and **PINRemoteImage** in the same UI (tabs, feed, dashboard).

## How to run the demo

**To run on an iOS simulator or device**, use the Xcode app project (Swift Package executable targets do not install correctly on simulator/device):

1. Open **`Examples/DaVinciLab/XcodeApp/DaVinciLabApp.xcodeproj`** in Xcode.
2. Select the **DaVinciLabApp** scheme.
3. Choose an iOS 15+ simulator or your connected device.
4. Press Run (⌘R).  
   If you use a physical device, set your **Team** in Signing & Capabilities.

If **Xcode crashes** when opening the project (known issue with local Swift packages in Xcode 15/16), see **`XcodeApp/README.md`** for workarounds. You can still run on **simulator only** by opening **`Package.swift`** and running the DaVinciLabApp scheme there.

The Xcode project uses the same app source (`App/Sources/DaVinciLabApp/`) and the DaVinciLab package, so you get one codebase and a proper .app bundle that installs.

**From the command line** (macOS runner only; iOS app must use the Xcode project above):

```bash
cd Examples/DaVinciLab && swift run DaVinciLabApp
```

The app uses the **same** DaVinci package as your own project (via `path: "../../"`), so you see real behavior: feed with prefetch/downsample/fade toggles, three engine tabs (DaVinci, Kingfisher, PINRemoteImage), and a dashboard with load/decode/cache metrics.

## What’s in the demo

- **Feed** – Paginated image grid; switch engines by tab to compare load behavior and metrics.
- **Dashboard** – Samples, average load time, decode time, cache hit rate, total bytes per engine.
- **Settings** – Prefetch, downsampling, fade; Cold/Warm benchmark run.

All app code lives under `App/Sources/DaVinciLabApp/` and the shared `Modules/` (LabCore, EngineDaVinci, EngineKingfisher, EnginePINRemoteImage). There is a single feed implementation so the demo stays consistent and easy to maintain.
