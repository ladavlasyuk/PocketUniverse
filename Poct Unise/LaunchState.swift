import Foundation
import Combine

final class LaunchState: ObservableObject {
    static let shared = LaunchState()

    static let didChangeNotification = NSNotification.Name("LaunchStateDidChange")

    @Published var portalDestination: String? {
        didSet { notifyChange() }
    }
    @Published var isPrePermissionVisible: Bool = false {
        didSet { notifyChange() }
    }
    @Published var noInternetMessage: String? {
        didSet { notifyChange() }
    }

    private func notifyChange() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: LaunchState.didChangeNotification, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: LaunchState.didChangeNotification, object: nil)
            }
        }
    }

    private let destinationKey = "saved_portal_destination"
    private let expiresKey = "saved_portal_destination_expires"
    private let payloadKey = "saved_config_payload"
    private let permanentNativeKey = "permanent_native_flow"
    private let pushDestinationKey = "saved_push_destination"
    private let installMarkerKey = "app_install_initialized"
    private let firstServerDecisionRecordedKey = "first_server_decision_recorded"
    private let firstServerDecisionHasLinkKey = "first_server_decision_has_link"

    private(set) var pendingDestination: String?
    private(set) var didOpenPushDestination = false

    private init() {}

    func resetPersistentStateOnFreshInstallIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: installMarkerKey) else { return }

        defaults.set(true, forKey: installMarkerKey)

        defaults.removeObject(forKey: destinationKey)
        defaults.removeObject(forKey: expiresKey)
        defaults.removeObject(forKey: payloadKey)
        defaults.removeObject(forKey: permanentNativeKey)
        defaults.removeObject(forKey: pushDestinationKey)
        defaults.removeObject(forKey: firstServerDecisionRecordedKey)
        defaults.removeObject(forKey: firstServerDecisionHasLinkKey)
        defaults.removeObject(forKey: "push_permission_last_decline")
        defaults.removeObject(forKey: "stored_fcm_token")
        defaults.removeObject(forKey: "last_sent_push_token_in_config")
        defaults.removeObject(forKey: "push_permission_granted")

        pendingDestination = nil
        portalDestination = nil
        didOpenPushDestination = false
        isPrePermissionVisible = false
        noInternetMessage = nil
        UserDefaults.standard.removeObject(forKey: pushDestinationKey)
    }

    func activateStoredDestinationIfValid(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        if isPermanentNativeFlow() {
            clearStoredDestination()
            portalDestination = nil
            return false
        }

        UserDefaults.standard.removeObject(forKey: pushDestinationKey)

        guard let destination = lastSuccessfulDestination() else {
            portalDestination = nil
            return false
        }

        let expires = UserDefaults.standard.double(forKey: expiresKey)
        if expires > now {
            portalDestination = destination
            return true
        }

        portalDestination = nil
        return false
    }

    func lastSuccessfulDestination() -> String? {
        guard !isPermanentNativeFlow() else { return nil }
        guard let destination = UserDefaults.standard.string(forKey: destinationKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !destination.isEmpty else {
            return nil
        }
        return destination
    }

    func isStoredDestinationExpired(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard lastSuccessfulDestination() != nil else { return true }
        return UserDefaults.standard.double(forKey: expiresKey) <= now
    }

    func openLastSuccessfulDestinationIfAvailable() -> Bool {
        guard let destination = lastSuccessfulDestination() else { return false }
        print("[AFSDK] Opening last successful portal destination.")
        noInternetMessage = nil
        prepareToOpenPortal(destination)
        return true
    }

    func saveDestination(_ destination: String, expires: TimeInterval) {
        guard !isPermanentNativeFlow() else { return }
        UserDefaults.standard.set(destination, forKey: destinationKey)
        UserDefaults.standard.set(expires, forKey: expiresKey)
        if portalDestination != nil || didOpenPushDestination || pendingDestination != nil {
            print("[AFSDK] Portal already open — saved config destination without replacing current session URL.")
            return
        }
        prepareToOpenPortal(destination)
    }

    func persistDestinationWithoutOpening(_ destination: String, expires: TimeInterval) {
        guard !isPermanentNativeFlow() else { return }
        UserDefaults.standard.set(destination, forKey: destinationKey)
        UserDefaults.standard.set(expires, forKey: expiresKey)
    }

    func hasStoredDestination() -> Bool {
        guard !isPermanentNativeFlow() else { return false }
        guard let destination = UserDefaults.standard.string(forKey: destinationKey) else {
            return false
        }
        return !destination.isEmpty
    }

    func clearStoredDestination() {
        UserDefaults.standard.removeObject(forKey: destinationKey)
        UserDefaults.standard.removeObject(forKey: expiresKey)
    }

    func saveConfigPayload(_ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        UserDefaults.standard.set(data, forKey: payloadKey)
    }

    func storedConfigPayload() -> [String: Any]? {
        guard let data = UserDefaults.standard.data(forKey: payloadKey),
              let json = try? JSONSerialization.jsonObject(with: data),
              let payload = json as? [String: Any] else { return nil }
        return payload
    }

    func isPermanentNativeFlow() -> Bool {
        UserDefaults.standard.bool(forKey: permanentNativeKey)
    }

    func lockPermanentNativeFlow() {
        UserDefaults.standard.set(true, forKey: permanentNativeKey)
        clearStoredDestination()
        portalDestination = nil
    }

    func recordFirstServerDecision(hasValidLink: Bool) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: firstServerDecisionRecordedKey) else { return }

        defaults.set(true, forKey: firstServerDecisionRecordedKey)
        defaults.set(hasValidLink, forKey: firstServerDecisionHasLinkKey)

        if !hasValidLink {
            lockPermanentNativeFlow()
        }
    }

    func showNoInternetMessage() {
        noInternetMessage = "No internet connection. Please turn on the internet and open the app again."
    }

    func clearNoInternetMessage() {
        noInternetMessage = nil
    }

    func openSessionPushDestination(_ address: String) -> Bool {
        guard !isPermanentNativeFlow() else {
            print("[Push] Ignored — permanent native flow is active")
            return false
        }
        didOpenPushDestination = true
        UserDefaults.standard.removeObject(forKey: pushDestinationKey)
        print("[Push] Opening push destination: \(address)")
        prepareToOpenPortal(address)
        return true
    }

    func openStoredConfigDestination() -> Bool {
        guard !isPermanentNativeFlow() else { return false }
        guard !didOpenPushDestination else {
            print("[Push] Session already shows a push destination — keeping current page")
            return false
        }
        guard let destination = lastSuccessfulDestination() else {
            print("[Push] No stored config destination")
            return false
        }
        print("[Push] Opening stored config destination")
        prepareToOpenPortal(destination)
        return true
    }

    func prepareToOpenPortal(_ destination: String) {
        guard !isPermanentNativeFlow() else { return }
        NotificationHandler.shared.shouldShowPrePermission { [weak self] shouldShow in
            guard let self = self else { return }
            guard !self.isPermanentNativeFlow() else { return }
            if shouldShow {
                self.pendingDestination = destination
                self.portalDestination = nil
                self.isPrePermissionVisible = true
            } else {
                self.pendingDestination = nil
                self.isPrePermissionVisible = false
                if self.portalDestination == destination {
                    self.notifyChange()
                } else {
                    self.portalDestination = destination
                }
            }
        }
    }

    func confirmPrePermissionAndOpen() {
        let target = pendingDestination
        pendingDestination = nil
        isPrePermissionVisible = false
        if let target = target {
            portalDestination = target
        }
    }
}
