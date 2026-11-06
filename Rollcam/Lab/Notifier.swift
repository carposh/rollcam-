import Foundation
import UserNotifications

/// Local notifications only — no push entitlement needed, so free-Apple-ID sideloading works.
enum Notifier {
    static func requestAuthorization(then action: @escaping () -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            action()
        }
    }

    static func scheduleDeveloped(rollID: UUID, frames: Int, after seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Your roll is back from the lab"
        content.body = "\(frames) photo\(frames == 1 ? "" : "s") developed. Open Rollcam to see them."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: rollID.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel(rollID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [rollID.uuidString])
    }
}
