import UIKit
import CoreHaptics

final class HapticsManager {
    static let shared = HapticsManager()

    private let supportsHaptics: Bool
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    private init() {
        if #available(iOS 13.0, *) {
            supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        } else {
            supportsHaptics = false
        }
        prepareGenerators()
    }

    private func prepareGenerators() {
        selectionGenerator.prepare()
        lightImpact.prepare()
        mediumImpact.prepare()
        notificationGenerator.prepare()
    }

    func selectionChanged() {
        guard supportsHaptics else { return }
        selectionGenerator.selectionChanged()
    }

    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard supportsHaptics else { return }
        switch style {
        case .light:
            lightImpact.impactOccurred()
        case .medium:
            mediumImpact.impactOccurred()
        default:
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        }
    }

    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard supportsHaptics else { return }
        notificationGenerator.notificationOccurred(type)
    }
}

