# DaVinci — Accessibility

DaVinci does not draw text or controls; it only loads and displays images. **You are responsible** for making those images accessible (e.g. VoiceOver, Dynamic Type, Reduce Motion).

---

## VoiceOver

Image views must have an **accessibility label** so VoiceOver can announce what the image represents.

**Option 1: Set the label in options (recommended)**

When loading an image, pass a label so it is set automatically after a successful load:

```swift
var options = DaVinciOptions.default
options.accessibilityLabel = "Product photo: blue running shoes"
imageView.dv.setImage(with: url, options: options)
```

The image view’s `accessibilityTraits` will include `.image` when you set `accessibilityLabel` via options.

**Option 2: Set the label yourself**

```swift
imageView.dv.setImage(with: url) { result, _ in
    if case .success = result {
        imageView.accessibilityLabel = "Avatar for John"
        imageView.accessibilityTraits.insert(.image)
    }
}
```

Use a short, meaningful description (e.g. “Profile photo”, “Product thumbnail: red jacket”), not the URL or technical details.

---

## Dynamic Type

DaVinci does not render text. If you add placeholders or overlays that include text (e.g. in a custom view), use **scalable fonts** so they respect the user’s Dynamic Type setting:

```swift
label.font = .preferredFont(forTextStyle: .body)
label.adjustsFontForContentSizeCategory = true
```

---

## Reduce Motion

DaVinci’s built-in transition is `.fade(duration:)`. If you add custom animations around image appearance, respect **Reduce Motion** so users who prefer less motion are not distracted:

```swift
let options = DaVinciOptions.default
if !UIAccessibility.isReduceMotionEnabled {
    options.transition = .fade(duration: 0.25)
}
imageView.dv.setImage(with: url, options: options)
```

(If you add more transition types later, use `.none` or a very subtle effect when `UIAccessibility.isReduceMotionEnabled` is true.)

---

## Summary

- **VoiceOver:** Set `options.accessibilityLabel` when loading, or set `imageView.accessibilityLabel` (and `.image` trait) after load.
- **Dynamic Type:** Use scalable fonts for any text you add (placeholders, overlays).
- **Reduce Motion:** Prefer `.none` or minimal transition when `UIAccessibility.isReduceMotionEnabled` is true.
