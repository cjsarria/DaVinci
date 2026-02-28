#if canImport(UIKit)
import UIKit
import LabCore
import EngineDaVinci
import EngineKingfisher
import EnginePINRemoteImage

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.tintColor = UIColor.systemBlue

        let aggregator = MetricsAggregator()
        let settingsStore = LabSettingsStore()

        let engines: [ImageLoadingEngine] = [
            DaVinciEngine(aggregator: aggregator),
            KingfisherEngine(aggregator: aggregator),
            PINRemoteImageEngine(aggregator: aggregator)
        ]

        window.rootViewController = TabBarController(engines: engines, aggregator: aggregator, settingsStore: settingsStore)
        window.makeKeyAndVisible()

        self.window = window
    }
}
#endif
