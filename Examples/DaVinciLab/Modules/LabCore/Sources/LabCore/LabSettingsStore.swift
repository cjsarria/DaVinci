import Foundation

public final class LabSettingsStore {
    public static let didChangeNotification = Notification.Name("com.davincilab.settings.changed")

    private let lock = NSLock()
    private var _settings: LabSettings

    public init(initial: LabSettings = LabSettings()) {
        self._settings = initial
    }

    public var settings: LabSettings {
        get { lock.lock(); defer { lock.unlock() }; return _settings }
        set {
            lock.lock()
            _settings = newValue
            lock.unlock()
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    public func update(_ mutate: (inout LabSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
    }
}
