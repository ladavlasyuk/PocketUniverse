import UIKit
import UserNotifications

final class NotificationHandler {
    static let shared = NotificationHandler()

    private let lastDeclineKey = "push_permission_last_decline"
    private let pushTokenKey = "stored_fcm_token"

    private init() {}

    func storeFcmToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: pushTokenKey)
    }

    func storedFcmToken() -> String? {
        UserDefaults.standard.string(forKey: pushTokenKey)
    }

    func currentPushToken() -> String {
        guard isPushGranted() else {
            return AppConstants.pushTokenPlaceholder
        }
        return storedFcmToken() ?? AppConstants.pushTokenPlaceholder
    }

    private let pushGrantedKey = "push_permission_granted"

    func isPushGranted() -> Bool {
        UserDefaults.standard.bool(forKey: pushGrantedKey)
    }

    func markPushGranted() {
        UserDefaults.standard.set(true, forKey: pushGrantedKey)
    }

    func refreshPushGrantedFromSystem(completion: (() -> Void)? = nil) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let granted = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            UserDefaults.standard.set(granted, forKey: self.pushGrantedKey)
            completion?()
        }
    }

    func clearDeliveredNotificationsAndBadge() {
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.setBadgeCount(0) { error in
            if let error {
                print("[Push] Failed to clear badge count: \(error.localizedDescription)")
            } else {
                print("[Push] Delivered notifications and badge count were cleared.")
            }
        }
    }

    func registerLastDecline() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastDeclineKey)
    }

    func shouldShowPrePermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .notDetermined:
                    let lastDecline = UserDefaults.standard.double(forKey: self.lastDeclineKey)
                    if lastDecline == 0 {
                        completion(true)
                    } else {
                        let now = Date().timeIntervalSince1970
                        completion(now - lastDecline > AppConstants.pushPermissionRetryDelay)
                    }
                case .denied:
                    completion(false)
                case .authorized, .provisional, .ephemeral:
                    completion(false)
                @unknown default:
                    completion(false)
                }
            }
        }
    }

    func requestSystemPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                } else {
                    self.registerLastDecline()
                }
                completion(granted)
            }
        }
    }

    func registerForRemoteNotificationsIfAuthorized() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
}
