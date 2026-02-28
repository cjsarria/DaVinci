#if canImport(SwiftUI)
import SwiftUI
import CoreGraphics

/// Loading phase for AsyncImage-style APIs (e.g. ``DaVinciAsyncImage``).
public enum DaVinciPhase {
    case empty
    case loading
    case success(DVImage, ImageLoadMetrics?)
    case failure(Error)

    public var image: DVImage? {
        if case .success(let img, _) = self { return img }
        return nil
    }

    public var error: Error? {
        if case .failure(let e) = self { return e }
        return nil
    }
}

/// AsyncImage-style view: content receives ``DaVinciPhase`` (empty, loading, success, failure) for custom layouts.
public struct DaVinciAsyncImage<Content: View>: View {
    private let url: URL?
    private let options: DaVinciOptions
    @ViewBuilder private let content: (DaVinciPhase) -> Content
    @StateObject private var loader = DaVinciAsyncImageLoader()

    public init(
        url: URL?,
        options: DaVinciOptions = .default,
        @ViewBuilder content: @escaping (DaVinciPhase) -> Content
    ) {
        self.url = url
        self.options = options
        self.content = content
    }

    public var body: some View {
        content(loader.phase)
            .onAppear { loader.load(url: url, options: options) }
            .onChange(of: url) { newURL in loader.load(url: newURL, options: options) }
            .onDisappear { loader.cancel() }
    }
}

public struct DaVinciImage: View {
    private let url: URL?
    private let options: DaVinciOptions
    private let placeholder: AnyView
    private let onCompletion: ((Result<DVImage, Error>, ImageLoadMetrics?) -> Void)?

    @StateObject private var loader = DaVinciImageLoader()

    public init(
        url: URL,
        options: DaVinciOptions = .default,
        onCompletion: ((Result<DVImage, Error>, ImageLoadMetrics?) -> Void)? = nil,
        @ViewBuilder placeholder: () -> some View
    ) {
        self.url = url
        self.options = options
        self.onCompletion = onCompletion
        self.placeholder = AnyView(placeholder())
    }

    public init(
        url: URL,
        options: DaVinciOptions = .default,
        onCompletion: ((Result<DVImage, Error>, ImageLoadMetrics?) -> Void)? = nil
    ) {
        self.url = url
        self.options = options
        self.onCompletion = onCompletion
        self.placeholder = AnyView(Rectangle().fill(Color.gray.opacity(0.2)))
    }

    public init(
        url: URL?,
        options: DaVinciOptions = .default,
        onCompletion: ((Result<DVImage, Error>, ImageLoadMetrics?) -> Void)? = nil,
        @ViewBuilder placeholder: () -> some View
    ) {
        self.url = url
        self.options = options
        self.onCompletion = onCompletion
        self.placeholder = AnyView(placeholder())
    }

    public init(
        url: URL?,
        options: DaVinciOptions = .default,
        onCompletion: ((Result<DVImage, Error>, ImageLoadMetrics?) -> Void)? = nil
    ) {
        self.url = url
        self.options = options
        self.onCompletion = onCompletion
        self.placeholder = AnyView(Rectangle().fill(Color.gray.opacity(0.2)))
    }

    // Backward-compatible initializers
    public init(
        url: URL?,
        targetSize: CGSize? = nil,
        cachePolicy: CachePolicy = .memoryAndDisk,
        priority: RequestPriority = .normal,
        onCompletion: ((Result<DVImage, Error>, ImageLoadMetrics?) -> Void)? = nil,
        @ViewBuilder placeholder: () -> some View
    ) {
        let opts = DaVinciOptions(cachePolicy: cachePolicy, priority: priority, targetSize: targetSize)
        self.init(url: url, options: opts, onCompletion: onCompletion, placeholder: placeholder)
    }

    public init(
        url: URL?,
        targetSize: CGSize? = nil,
        cachePolicy: CachePolicy = .memoryAndDisk,
        priority: RequestPriority = .normal,
        onCompletion: ((Result<DVImage, Error>, ImageLoadMetrics?) -> Void)? = nil
    ) {
        let opts = DaVinciOptions(cachePolicy: cachePolicy, priority: priority, targetSize: targetSize)
        self.init(url: url, options: opts, onCompletion: onCompletion)
    }

    public var body: some View {
        Group {
            if let image = loader.image {
                platformImageView(image)
                    .resizable()
            } else {
                placeholder
            }
        }
        .onAppear {
            loader.load(url: url, options: options, onCompletion: onCompletion)
        }
        .onChange(of: url) { newValue in
            loader.load(url: newValue, options: options, onCompletion: onCompletion)
        }
        .onDisappear {
            loader.cancel()
        }
    }
}

@MainActor
private final class DaVinciImageLoader: ObservableObject {
    @Published var image: DVImage?
    private var task: Task<Void, Never>?

    func load(
        url: URL?,
        options: DaVinciOptions,
        onCompletion: ((Result<DVImage, Error>, ImageLoadMetrics?) -> Void)?
    ) {
        cancel()
        image = nil

        guard let url else {
            onCompletion?(.failure(DaVinciError.invalidURL), nil)
            return
        }

        let scale: CGFloat
        #if canImport(UIKit)
        scale = UIScreen.main.scale
        #else
        scale = 1
        #endif

        task = Task { [weak self] in
            do {
                let (img, metrics) = try await DaVinciClient.shared.loadImage(url: url, scale: scale, options: options)

                guard Task.isCancelled == false else { return }
                await MainActor.run {
                    self?.image = img
                    onCompletion?(.success(img), metrics)
                }
            } catch {
                if error is CancellationError {
                    return
                }
                guard Task.isCancelled == false else { return }
                await MainActor.run {
                    onCompletion?(.failure(error), nil)
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

private func platformImageView(_ image: DVImage) -> Image {
    #if canImport(UIKit)
    return Image(uiImage: image)
    #elseif canImport(AppKit)
    return Image(nsImage: image)
    #else
    return Image(systemName: "photo")
    #endif
}

@MainActor
private final class DaVinciAsyncImageLoader: ObservableObject {
    @Published var phase: DaVinciPhase = .empty
    private var task: Task<Void, Never>?

    func load(url: URL?, options: DaVinciOptions) {
        cancel()
        phase = .empty

        guard let url else {
            phase = .failure(DaVinciError.invalidURL)
            return
        }

        phase = .loading

        let scale: CGFloat
        #if canImport(UIKit)
        scale = UIScreen.main.scale
        #else
        scale = 1
        #endif

        task = Task { [weak self] in
            do {
                let (img, metrics) = try await DaVinciClient.shared.loadImage(url: url, scale: scale, options: options)
                guard Task.isCancelled == false else { return }
                await MainActor.run {
                    self?.phase = .success(img, metrics)
                }
            } catch {
                if error is CancellationError { return }
                guard Task.isCancelled == false else { return }
                await MainActor.run {
                    self?.phase = .failure(error)
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
#endif
