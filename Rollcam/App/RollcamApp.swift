import SwiftUI
import UserNotifications

@main
struct RollcamApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = RollStore()

    var body: some Scene {
        WindowGroup {
            CameraBodyView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UserDefaults.standard.register(defaults: [
            SettingsKey.developSeconds: DevelopDuration.oneDay.rawValue,
            SettingsKey.dateStampDefault: true,
        ])
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
