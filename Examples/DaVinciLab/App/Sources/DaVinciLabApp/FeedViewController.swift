#if canImport(UIKit)
import UIKit
import LabCore

private enum FeedSection: Hashable {
    case main
}

final class FeedViewController: UIViewController {
    private let engine: ImageLoadingEngine
    private let aggregator: MetricsAggregator
    private let settingsStore: LabSettingsStore
    private let clearAllCaches: () -> Void

    private var dataset: DatasetProvider?
    private var items: [DatasetItem] = []
    private var offset: Int = 0
    private let pageSize: Int = 40

    private var isLoadingPage: Bool = false
    private var isReloadingCollection: Bool = false
    private var lastReloadAt: Date = .distantPast
    private var loadMoreScheduled: Bool = false

    private lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: Self.makeLayout())
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .systemBackground
        cv.alwaysBounceVertical = true
        cv.contentInsetAdjustmentBehavior = .always
        cv.register(FeedCell.self, forCellWithReuseIdentifier: FeedCell.reuseID)
        cv.delegate = self
        return cv
    }()

    private lazy var dataSource: UICollectionViewDiffableDataSource<FeedSection, DatasetItem> = {
        UICollectionViewDiffableDataSource<FeedSection, DatasetItem>(collectionView: collectionView) { [weak self] cv, indexPath, item in
            guard let self else { return UICollectionViewCell() }
            let cell = cv.dequeueReusableCell(withReuseIdentifier: FeedCell.reuseID, for: indexPath) as! FeedCell
            self.configure(cell: cell, at: indexPath, item: item)
            return cell
        }
    }()

    private let refresh = UIRefreshControl()
    private let controls = ControlsHeaderView()
    private var benchmarkRunner: BenchmarkRunner?
    private var activeRunMode: BenchmarkMode?

    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        label.isHidden = true
        label.text = "No items loaded — dataset missing or parsing failed."
        return label
    }()

    private var settings: LabSettings {
        settingsStore.settings
    }

    private func updateEmptyState() {
        let isEmpty = items.isEmpty
        emptyStateLabel.isHidden = !isEmpty
    }

    init(
        engine: ImageLoadingEngine,
        aggregator: MetricsAggregator,
        settingsStore: LabSettingsStore,
        clearAllCaches: @escaping () -> Void
    ) {
        self.engine = engine
        self.aggregator = aggregator
        self.settingsStore = settingsStore
        self.clearAllCaches = clearAllCaches
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        if let provider = try? DatasetProvider() {
            dataset = provider
            #if DEBUG
            print("[DaVinciLab] Dataset loaded: \(provider.totalCount()) items")
            #endif
        } else {
            let fallback = DatasetProvider(items: DatasetProvider.fallbackItems())
            dataset = fallback
            #if DEBUG
            print("[DaVinciLab] Dataset load failed. Using fallback: \(fallback.totalCount()) items")
            #endif
        }

        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.configure(with: settings)

        controls.onTogglePrefetch = { [weak self] enabled in self?.settingsStore.update { $0.prefetchEnabled = enabled } }
        controls.onToggleDownsample = { [weak self] enabled in self?.settingsStore.update { $0.downsamplingEnabled = enabled } }
        controls.onToggleFade = { [weak self] enabled in self?.settingsStore.update { $0.fadeEnabled = enabled } }

        controls.onSnapshot = { [weak self] in self?.presentSnapshot() }
        controls.onRunBenchmark = { [weak self] mode in self?.runAutoBenchmark(mode: mode) }
        controls.onClearCache = { [weak self] in self?.engine.clearCaches() }

        view.addSubview(controls)
        view.addSubview(collectionView)
        view.addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controls.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),

            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: controls.bottomAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor)
        ])

        refresh.addTarget(self, action: #selector(onRefresh), for: .valueChanged)
        collectionView.refreshControl = refresh

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: LabSettingsStore.didChangeNotification,
            object: settingsStore
        )

        loadInitial(triggerPrefetch: true)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func applySnapshot(animatingDifferences: Bool = true) {
        var snapshot = NSDiffableDataSourceSnapshot<FeedSection, DatasetItem>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    }

    private func configure(cell: FeedCell, at indexPath: IndexPath, item: DatasetItem) {
        cell.configure(title: item.title)

        let requestOptions = settings.requestOptions
        let targetSize = requestOptions.downsampleEnabled ? cell.targetImageSize : nil

        #if DEBUG
        print("[DaVinciLab][Feed] engine=\(engine.name) index=\(indexPath.item) url=\(item.url.absoluteString)")
        #endif

        engine.setImage(on: cell.imageView, url: item.url, targetSize: targetSize, options: requestOptions) { [weak self] metric in
            guard let self else { return }
            let tagged = LabMetrics(
                cacheSource: metric.cacheSource,
                loadTimeMs: metric.loadTimeMs,
                decodeTimeMs: metric.decodeTimeMs,
                bytes: metric.bytes,
                runMode: self.activeRunMode
            )
            let update = {
                self.aggregator.record(engineName: self.engine.name, metric: tagged)
                cell.updateBadge(source: tagged.cacheSource)
            }
            if Thread.isMainThread {
                update()
            } else {
                DispatchQueue.main.async(execute: update)
            }

            #if DEBUG
            let applied = requestOptions.downsampleEnabled && (targetSize != nil)
            let decodeText = tagged.decodeTimeMs.map { String(format: "%.1f", $0) } ?? "—"
            let bytesText = tagged.bytes.map { String($0) } ?? "—"
            print("[DaVinciLab][Fairness] engine=\(self.engine.name) mode=\(self.activeRunMode?.rawValue ?? "-") cache=\(tagged.cacheSource.rawValue) load=\(String(format: "%.1f", tagged.loadTimeMs))ms decode=\(decodeText)ms bytes=\(bytesText) downsampleApplied=\(applied)")
            #endif
        }

        if indexPath.item >= items.count - 12, !loadMoreScheduled {
            loadMoreScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.loadMoreScheduled = false
                self?.loadMore(triggerPrefetch: true)
            }
        }
    }

    @objc private func settingsChanged() {
        controls.configure(with: settings)
        applySnapshot(animatingDifferences: false)
    }

    @objc private func onRefresh() {
        HapticsManager.shared.impact(style: .light)
        loadInitial(triggerPrefetch: true)
        refresh.endRefreshing()
    }

    private func loadInitial(triggerPrefetch: Bool) {
        isLoadingPage = false
        loadMoreScheduled = false
        offset = 0
        items = []
        aggregator.reset(engineName: engine.name)
        collectionView.setContentOffset(.zero, animated: false)
        isReloadingCollection = true
        lastReloadAt = Date()
        applySnapshot(animatingDifferences: false)
        DispatchQueue.main.async { [weak self] in
            self?.isReloadingCollection = false
        }
        updateEmptyState()
        loadMore(triggerPrefetch: triggerPrefetch)
    }

    private func loadMore(triggerPrefetch: Bool) {
        if Thread.isMainThread == false {
            DispatchQueue.main.async { [weak self] in
                self?.loadMore(triggerPrefetch: triggerPrefetch)
            }
            return
        }

        guard isLoadingPage == false else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }

        guard let dataset else { return }
        let next = dataset.page(offset: offset, limit: pageSize)
        guard next.isEmpty == false else { return }

        let startIndex = items.count
        offset += next.count
        items.append(contentsOf: next)
        let endIndex = items.count

        let recentReload = Date().timeIntervalSince(lastReloadAt) < 0.25
        if startIndex == 0 || isReloadingCollection || recentReload {
            isReloadingCollection = true
            lastReloadAt = Date()
            applySnapshot(animatingDifferences: (startIndex == 0 ? false : true))
            DispatchQueue.main.async { [weak self] in
                self?.isReloadingCollection = false
            }
            updateEmptyState()
            return
        }

        guard startIndex < endIndex else {
            updateEmptyState()
            return
        }

        // Append via diffable snapshot so only new items are inserted; no full reload (avoids freeze and DaVinci cancellations).
        isReloadingCollection = true
        lastReloadAt = Date()
        applySnapshot(animatingDifferences: true)
        DispatchQueue.main.async { [weak self] in
            self?.isReloadingCollection = false
        }

        updateEmptyState()

        #if DEBUG
        print("[DaVinciLab] \(engine.name) items=\(items.count) contentSize=\(collectionView.contentSize)")
        #endif

        if triggerPrefetch, settings.prefetchEnabled {
            engine.prefetch(urls: next.map { $0.url })
        }
    }

    private func presentSnapshot() {
        let snap = aggregator.snapshot(engineName: engine.name)

        let decodeText = snap.avgDecodeMs.map { String(format: "%.1f ms", $0) } ?? "—"
        let hitText: String
        if let hit = snap.cacheHitRate {
            let suffix = snap.cacheHitRateIsEstimated ? " ~" : ""
            hitText = String(format: "%.0f%%%@", hit * 100, suffix)
        } else {
            hitText = "—"
        }
        let bytesText: String
        if let bytes = snap.totalBytes {
            let suffix = snap.totalBytesIsEstimated ? " ~" : ""
            bytesText = "\(bytes)\(suffix)"
        } else {
            bytesText = "—"
        }

        let alert = UIAlertController(
            title: "Snapshot",
            message: "Samples: \(snap.count)\nAvg load: \(String(format: "%.1f ms", snap.avgLoadMs))\nAvg decode: \(decodeText)\nCache hit: \(hitText)\nTotal bytes: \(bytesText)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func runAutoBenchmark(mode: BenchmarkMode) {
        HapticsManager.shared.impact(style: .medium)

        if mode == .cold {
            clearAllCaches()
        }

        activeRunMode = mode
        loadInitial(triggerPrefetch: true)

        let runner = BenchmarkRunner(scrollView: collectionView, engineName: engine.name, aggregator: aggregator)
        benchmarkRunner = runner

        let requestOptions = settings.requestOptions

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            runner.run(mode: mode, settings: requestOptions) { report in
                DispatchQueue.main.async {
                    self.activeRunMode = nil
                    HapticsManager.shared.notification(.success)
                    let vc = BenchmarkResultsViewController(report: report)
                    let nav = UINavigationController(rootViewController: vc)
                    self.present(nav, animated: true)
                }
            }
        }
    }

    private static func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, env in
            let isWide = env.container.effectiveContentSize.width > 500

            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1.0))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)

            let height: NSCollectionLayoutDimension = isWide ? .absolute(240) : .absolute(220)
            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: height)
            let columns = isWide ? 3 : 2
            let subitems = (0..<columns).map { _ in item }
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: subitems)
            return NSCollectionLayoutSection(group: group)
        }
    }
}

extension FeedViewController: UICollectionViewDelegate {}

final class ControlsHeaderView: UIView {
    var onTogglePrefetch: ((Bool) -> Void)?
    var onToggleDownsample: ((Bool) -> Void)?
    var onToggleFade: ((Bool) -> Void)?
    var onClearCache: (() -> Void)?
    var onSnapshot: (() -> Void)?
    var onRunBenchmark: ((BenchmarkMode) -> Void)?

    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let stack = UIStackView()

    private let prefetch = UISwitch()
    private let downsample = UISwitch()
    private let fade = UISwitch()

    private let mode = UISegmentedControl(items: ["Cold", "Warm"])

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(stack)

        let pre = makeRow(title: "Prefetch", control: prefetch)
        let down = makeRow(title: "Downsample", control: downsample)
        let fa = makeRow(title: "Fade", control: fade)

        mode.selectedSegmentIndex = 1
        mode.selectedSegmentTintColor = .systemBlue
        mode.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        let run = UIButton(type: .system)
        run.setTitle("Run", for: .normal)
        run.addTarget(self, action: #selector(runTapped), for: .touchUpInside)
        stylePill(run, emphasized: true)

        let snapshot = UIButton(type: .system)
        snapshot.setTitle("Snapshot", for: .normal)
        snapshot.addTarget(self, action: #selector(snapshotTapped), for: .touchUpInside)
        stylePill(snapshot)

        let clear = UIButton(type: .system)
        clear.setTitle("Clear", for: .normal)
        clear.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        stylePill(clear)

        stack.addArrangedSubview(pre)
        stack.addArrangedSubview(down)
        stack.addArrangedSubview(fa)
        stack.addArrangedSubview(mode)
        stack.addArrangedSubview(clear)
        stack.addArrangedSubview(run)
        stack.addArrangedSubview(snapshot)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        prefetch.addTarget(self, action: #selector(prefetchChanged), for: .valueChanged)
        downsample.addTarget(self, action: #selector(downsampleChanged), for: .valueChanged)
        fade.addTarget(self, action: #selector(fadeChanged), for: .valueChanged)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with settings: LabSettings) {
        prefetch.isOn = settings.prefetchEnabled
        downsample.isOn = settings.downsamplingEnabled
        fade.isOn = settings.fadeEnabled
    }

    private func makeRow(title: String, control: UIControl) -> UIView {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.text = title

        let row = UIStackView(arrangedSubviews: [label, control])
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .center
        return row
    }

    @objc private func prefetchChanged() {
        HapticsManager.shared.selectionChanged()
        onTogglePrefetch?(prefetch.isOn)
    }

    @objc private func downsampleChanged() {
        HapticsManager.shared.selectionChanged()
        onToggleDownsample?(downsample.isOn)
    }

    @objc private func fadeChanged() {
        HapticsManager.shared.selectionChanged()
        onToggleFade?(fade.isOn)
    }

    @objc private func clearTapped() {
        HapticsManager.shared.impact(style: .light)
        onClearCache?()
    }

    @objc private func snapshotTapped() {
        HapticsManager.shared.impact(style: .light)
        onSnapshot?()
    }

    @objc private func runTapped() {
        HapticsManager.shared.impact(style: .medium)
        onRunBenchmark?(selectedMode)
    }

    private var selectedMode: BenchmarkMode {
        mode.selectedSegmentIndex == 0 ? .cold : .warm
    }

    @objc private func modeChanged() {
        HapticsManager.shared.selectionChanged()
    }

    private func stylePill(_ button: UIButton, emphasized: Bool = false) {
        button.configuration = .filled()
        button.configuration?.cornerStyle = .capsule
        button.configuration?.baseBackgroundColor = emphasized ? .systemBlue : .secondarySystemFill
        button.configuration?.baseForegroundColor = emphasized ? .white : .label
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
    }
}

final class FeedCell: UICollectionViewCell {
    static let reuseID = "FeedCell"

    let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let gradient = CAGradientLayer()
    private let badge = UILabel()
    private let shimmer = ShimmerView()

    #if DEBUG
    private let debugLabel = UILabel()
    private var debugTimeoutWorkItem: DispatchWorkItem?
    #endif

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 16
        contentView.layer.masksToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        shimmer.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        badge.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        badge.textColor = .white
        badge.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        badge.layer.cornerRadius = 8
        badge.layer.masksToBounds = true
        badge.textAlignment = .center
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isHidden = true

        contentView.addSubview(shimmer)
        contentView.addSubview(imageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(badge)
        #if DEBUG
        contentView.addSubview(debugLabel)
        #endif

        var constraints: [NSLayoutConstraint] = [
            shimmer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            shimmer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            shimmer.topAnchor.constraint(equalTo: contentView.topAnchor),
            shimmer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            badge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            badge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            badge.widthAnchor.constraint(equalToConstant: 24),
            badge.heightAnchor.constraint(equalToConstant: 20)
        ]
        #if DEBUG
        constraints += [
            debugLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            debugLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ]
        #endif
        NSLayoutConstraint.activate(constraints)

        gradient.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.75).cgColor]
        gradient.locations = [0.5, 1.0]
        contentView.layer.insertSublayer(gradient, above: imageView.layer)

        shimmer.start()

        #if DEBUG
        debugLabel.font = .preferredFont(forTextStyle: .caption2)
        debugLabel.textColor = .systemRed
        debugLabel.numberOfLines = 2
        debugLabel.isHidden = true
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = contentView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        badge.isHidden = true
        shimmer.isHidden = false
        shimmer.start()
        #if DEBUG
        debugLabel.isHidden = true
        debugTimeoutWorkItem?.cancel()
        debugTimeoutWorkItem = nil
        #endif
    }

    var targetImageSize: CGSize {
        contentView.bounds.size
    }

    func configure(title: String) {
        titleLabel.text = title
        #if DEBUG
        debugTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.badge.isHidden {
                self.debugLabel.text = "No callback from engine"
                self.debugLabel.isHidden = false
            }
        }
        debugTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
        #endif
    }

    func updateBadge(source: LabCacheSource) {
        shimmer.isHidden = true
        shimmer.stop()
        let t: String
        switch source {
        case .memory: t = "M"
        case .disk: t = "D"
        case .network: t = "N"
        case .unknown: t = "~"
        }
        badge.text = t
        badge.isHidden = false
        #if DEBUG
        debugLabel.isHidden = true
        debugTimeoutWorkItem?.cancel()
        debugTimeoutWorkItem = nil
        #endif
    }
}

final class ShimmerView: UIView {
    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor.tertiarySystemFill

        gradient.colors = [
            UIColor.tertiarySystemFill.cgColor,
            UIColor.secondarySystemFill.cgColor,
            UIColor.tertiarySystemFill.cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.locations = [0, 0.5, 1]
        layer.addSublayer(gradient)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }

    func start() {
        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = [-1, -0.5, 0]
        anim.toValue = [1, 1.5, 2]
        anim.duration = 1.1
        anim.repeatCount = .infinity
        gradient.add(anim, forKey: "shimmer")
    }

    func stop() {
        gradient.removeAnimation(forKey: "shimmer")
    }
}
#endif
