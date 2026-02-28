#if canImport(UIKit)
import UIKit
import LabCore

final class TabBarController: UITabBarController {
    private let engines: [ImageLoadingEngine]
    private let aggregator: MetricsAggregator
    private let settingsStore: LabSettingsStore

    init(engines: [ImageLoadingEngine], aggregator: MetricsAggregator, settingsStore: LabSettingsStore) {
        self.engines = engines
        self.aggregator = aggregator
        self.settingsStore = settingsStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabBar.isTranslucent = true

        let clearAllCaches: () -> Void = { [engines] in
            engines.forEach { $0.clearCaches() }
        }

        let controllers: [UIViewController] = engines.map { engine in
            let vc = FeedViewController(engine: engine, aggregator: aggregator, settingsStore: settingsStore, clearAllCaches: clearAllCaches)
            let nav = UINavigationController(rootViewController: vc)
            nav.navigationBar.prefersLargeTitles = true
            vc.title = engine.name
            nav.tabBarItem = UITabBarItem(title: engine.name, image: UIImage(systemName: "photo.on.rectangle"), tag: 0)
            return nav
        }

        let dashboard = DashboardViewController(aggregator: aggregator)
        let dashNav = UINavigationController(rootViewController: dashboard)
        dashNav.navigationBar.prefersLargeTitles = true
        dashboard.title = "Dashboard"
        dashNav.tabBarItem = UITabBarItem(title: "Dashboard", image: UIImage(systemName: "gauge"), tag: 1)

        viewControllers = controllers + [dashNav]
    }

    override func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        HapticsManager.shared.impact(style: .light)
    }
}
#endif
