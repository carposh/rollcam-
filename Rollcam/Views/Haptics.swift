import UIKit

enum Haptics {
    private static let wheel = UIImpactFeedbackGenerator(style: .rigid)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notify = UINotificationFeedbackGenerator()

    static func prepare() {
        wheel.prepare()
        heavy.prepare()
    }

    static func click() { wheel.impactOccurred(intensity: 0.75) }
    static func clunk() { heavy.impactOccurred(intensity: 1.0) }
    static func shutter() { heavy.impactOccurred(intensity: 0.9) }
    static func warn() { notify.notificationOccurred(.warning) }
    static func success() { notify.notificationOccurred(.success) }
}
