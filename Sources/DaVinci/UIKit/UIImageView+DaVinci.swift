#if canImport(UIKit)
import Foundation
import UIKit

extension UIImageView: DaVinciCompatible {}

public enum DaVinciImageViewError: Error {
    case invalidURL
}

extension DaVinciWrapper where Base: UIImageView {
    /// URL of the image currently displayed (or last successfully loaded). Nil if none or after cancel.
    /// Use this to avoid redundant `setImage` when reconfiguring with the same URL (e.g. in collection view cells).
    @MainActor
    public var currentImageURL: URL? { base.dv_currentURL }

    /// Loads and displays the image at `url`. Completion is always called on the main thread for UI safety.
    /// If `url` equals `currentImageURL`, this is a no-op (idempotent) and completion is not called.
    @MainActor
    public func setImage(
        with url: URL?,
        options: DaVinciOptions = .default,
        completion: ((Result<UIImage, Error>, ImageLoadMetrics?) -> Void)? = nil
    ) {
        if let placeholder = options.placeholder {
            base.image = placeholder
        }

        guard let url else {
            base.dv_cancelCurrentImageTask()
            completion?(.failure(DaVinciError.invalidURL), nil)
            return
        }

        // Idempotent: same URL already loaded or in progress — skip to avoid flicker and redundant work.
        if base.dv_currentURL == url {
            if let existing = base.image {
                completion?(.success(existing), nil)
            } else {
                completion?(.failure(DaVinciImageViewError.invalidURL), nil)
            }
            return
        }

        base.dv_cancelCurrentImageTask()

        let token = UUID()
        base.dv_imageLoadToken = token

        let task = Task { [weak base] in
            do {
                let scale = UIScreen.main.scale
                #if DEBUG
                print("[DaVinci][UIImageView] start url=\(url.absoluteString) token=\(token)")
                #endif
                let (platformImage, metrics) = try await DaVinciClient.shared.loadImage(url: url, scale: scale, options: options)
                guard let image = platformImage as? UIImage else { throw ImageDecodingError.invalidData }

                await MainActor.run {
                    guard let base, base.dv_imageLoadToken == token else { return }

                    let shouldAnimate: Bool
                    if case .fade = options.transition, !UIAccessibility.isReduceMotionEnabled {
                        shouldAnimate = (metrics.cacheSource != .memory)
                    } else {
                        shouldAnimate = false
                    }

                    switch options.transition {
                    case .none:
                        base.image = image
                    case .fade(let duration):
                        if shouldAnimate {
                            UIView.transition(
                                with: base,
                                duration: duration,
                                options: [.transitionCrossDissolve, .allowUserInteraction]
                            ) {
                                base.image = image
                            }
                        } else {
                            base.image = image
                        }
                    }

                    base.dv_currentURL = url
                    if let a11y = options.accessibilityLabel {
                        base.accessibilityLabel = a11y
                        base.accessibilityTraits = base.accessibilityTraits.union(.image)
                    }
                    completion?(.success(image), metrics)
                    base.dv_updateDebugBadge(cacheSource: metrics.cacheSource)
                    #if DEBUG
                    print("[DaVinci][UIImageView] success url=\(url.absoluteString) token=\(token) source=\(metrics.cacheSource)")
                    #endif
                }
            } catch {
                if error is CancellationError {
                    #if DEBUG
                    print("[DaVinci][UIImageView] cancelled url=\(url.absoluteString) token=\(token)")
                    #endif
                    await MainActor.run {
                        guard let b = base, b.dv_imageLoadToken == token else { return }
                        completion?(.failure(error), nil)
                    }
                    return
                }
                await MainActor.run {
                    guard let base, base.dv_imageLoadToken == token else { return }
                    completion?(.failure(error), nil)
                    base.dv_updateDebugBadge(cacheSource: nil)
                    #if DEBUG
                    print("[DaVinci][UIImageView] failure url=\(url.absoluteString) token=\(token) error=\(error)")
                    #endif
                }
            }
        }

        base.dv_imageLoadTask = task
    }

    /// Loads the image at `url` using app-wide default options (`DaVinciClient.defaultOptions`). Set defaults at launch.
    @MainActor
    public func setImage(
        with url: URL?,
        completion: ((Result<UIImage, Error>, ImageLoadMetrics?) -> Void)? = nil
    ) {
        setImage(with: url, options: DaVinciClient.defaultOptions, completion: completion)
    }

    @MainActor
    public func setImage(
        with url: URL?,
        placeholder: UIImage? = nil,
        targetSize: CGSize? = nil,
        cachePolicy: CachePolicy = .memoryAndDisk,
        priority: RequestPriority = .normal,
        completion: ((Result<UIImage, Error>) -> Void)? = nil
    ) {
        var options = DaVinciOptions(cachePolicy: cachePolicy, priority: priority, targetSize: targetSize)
        options.placeholder = placeholder
        setImage(with: url, options: options) { result, _ in
            completion?(result)
        }
    }

    @MainActor
    public func setImage(
        with url: URL?,
        placeholder: UIImage? = nil,
        targetSize: CGSize? = nil,
        cachePolicy: CachePolicy = .memoryAndDisk,
        priority: RequestPriority = .normal,
        completion: ((Result<UIImage, Error>) -> Void)? = nil,
        metricsCompletion: ((Result<UIImage, Error>, ImageLoadMetrics?) -> Void)?
    ) {
        var options = DaVinciOptions(cachePolicy: cachePolicy, priority: priority, targetSize: targetSize)
        options.placeholder = placeholder
        setImage(with: url, options: options) { result, metrics in
            completion?(result)
            metricsCompletion?(result, metrics)
        }
    }
}

private func dv_costBytes(for image: UIImage) -> Int {
    if let cg = image.cgImage {
        return cg.bytesPerRow * cg.height
    }
    return 0
}

private var dvTaskKey: UInt8 = 0
private var dvTokenKey: UInt8 = 0
private var dvCurrentURLKey: UInt8 = 0

private extension UIImageView {
    var dv_imageLoadTask: Task<Void, Never>? {
        get { objc_getAssociatedObject(self, &dvTaskKey) as? Task<Void, Never> }
        set { objc_setAssociatedObject(self, &dvTaskKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var dv_imageLoadToken: UUID? {
        get { objc_getAssociatedObject(self, &dvTokenKey) as? UUID }
        set { objc_setAssociatedObject(self, &dvTokenKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// URL of the image currently displayed (set on success; not cleared on cancel so same-URL reconfigure is no-op).
    var dv_currentURL: URL? {
        get { objc_getAssociatedObject(self, &dvCurrentURLKey) as? URL }
        set { objc_setAssociatedObject(self, &dvCurrentURLKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    func dv_cancelCurrentImageTask() {
        dv_imageLoadTask?.cancel()
        dv_imageLoadTask = nil
        dv_imageLoadToken = nil
    }
}

// MARK: - Debug overlay

private var dvDebugEnabledKey: UInt8 = 0
private var dvDebugBadgeKey: UInt8 = 0

extension DaVinciWrapper where Base: UIImageView {
    public func enableDebugOverlay() {
        base.dv_setDebugOverlayEnabled(true)
    }

    public func disableDebugOverlay() {
        base.dv_setDebugOverlayEnabled(false)
    }
}

private extension UIImageView {
    func dv_setDebugOverlayEnabled(_ enabled: Bool) {
        #if DEBUG
        objc_setAssociatedObject(self, &dvDebugEnabledKey, enabled, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        if enabled {
            _ = dv_debugBadgeLabel()
        } else {
            if let label = objc_getAssociatedObject(self, &dvDebugBadgeKey) as? UILabel {
                label.removeFromSuperview()
            }
            objc_setAssociatedObject(self, &dvDebugBadgeKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        #else
        _ = enabled
        #endif
    }

    func dv_updateDebugBadge(cacheSource: ImageCacheSource?) {
        #if DEBUG
        guard (objc_getAssociatedObject(self, &dvDebugEnabledKey) as? Bool) == true else { return }
        let label = dv_debugBadgeLabel()
        let text: String
        switch cacheSource {
        case .memory?: text = "M"
        case .disk?: text = "D"
        case .network?: text = "N"
        default: text = ""
        }
        label.text = text
        label.isHidden = text.isEmpty
        #else
        _ = cacheSource
        #endif
    }

    func dv_debugBadgeLabel() -> UILabel {
        if let label = objc_getAssociatedObject(self, &dvDebugBadgeKey) as? UILabel {
            return label
        }

        let label = UILabel()
        label.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.textAlignment = .center
        label.layer.cornerRadius = 6
        label.layer.masksToBounds = true
        label.isUserInteractionEnabled = false
        label.isHidden = true

        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.widthAnchor.constraint(equalToConstant: 16),
            label.heightAnchor.constraint(equalToConstant: 16)
        ])

        objc_setAssociatedObject(self, &dvDebugBadgeKey, label, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return label
    }
}
#endif
