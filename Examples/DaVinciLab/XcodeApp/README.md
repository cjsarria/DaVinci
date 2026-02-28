# Xcode app project (run on device/simulator)

This folder contains **DaVinciLabApp.xcodeproj**, a minimal iOS app target that uses the DaVinciLab Swift package so you can build and run the demo on a **simulator or physical device** (the package’s executable target does not install correctly on device).

## If Xcode crashes when opening this project

Xcode 15/16 sometimes crashes (`EXC_BAD_INSTRUCTION`, `IDESwiftPackageCore`, or `mach_vm_allocate_kernel failed`) when opening projects that use a **local Swift package** (this one references `..` for DaVinciLab). This is a known Xcode bug, not an issue with this repo.

**Workarounds:**

1. **Quit other apps** to free memory, then open the project again.
2. **Open the package instead for simulator:**  
   Open **`Examples/DaVinciLab/Package.swift`** in Xcode, select the **DaVinciLabApp** scheme, choose an **iOS Simulator** (e.g. iPhone 16), and run (⌘R). This works for simulator only; it will not install on a physical device.
3. **Create a new iOS App in Xcode** and add the package manually:  
   File → Add Package Dependencies → Add Local → select **`Examples/DaVinciLab`**. Add the **DaVinciLabApp** target’s source files from `App/Sources/DaVinciLabApp/` and link the package products (LabCore, EngineDaVinci, EngineKingfisher, EnginePINRemoteImage). Set the app’s Info.plist to `App/Sources/DaVinciLabApp/Resources/Info.plist`.
4. **Update Xcode** to the latest version; newer builds sometimes fix these crashes.

## How to run (when the project opens successfully)

1. Open **DaVinciLabApp.xcodeproj** in Xcode.
2. Select the **DaVinciLabApp** scheme.
3. Choose **iPhone 13 Pro Max** (or any simulator/device).
4. Press **Run** (⌘R).  
   For a physical device, set your **Team** in Signing & Capabilities if prompted.
