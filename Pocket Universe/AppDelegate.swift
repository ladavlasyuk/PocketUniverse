import UIKit
import UserNotifications
import Network
import AppsFlyerLib
import FirebaseCore
import FirebaseMessaging

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var orientationLock: UIInterfaceOrientationMask = .portrait

    private var conversionData: [String: Any]?
    private var deepLinkData: [String: Any]?
    private var didPrintMergedPayload = false
    private var isWaitingForGCDConversion = false
    private var mergeTimerWorkItem: DispatchWorkItem?
    private var didStartAppsFlyer = false
    private var launchInternetMonitor: NWPathMonitor?
    private var launchStateObservation: NSKeyValueObservation?
    private var mainNavigationController: UINavigationController?
    private weak var rootPortal: ContentPortalController?
    private var isLaunchLoaderActive = true
    private var launchLoaderFinishWorkItem: DispatchWorkItem?
    private var launchLoaderDuration: TimeInterval { AppConstants.launchLoaderDuration }
    private let launchStartTime: CFTimeInterval = CACurrentMediaTime()
    private var didReceiveConfigResponse = false
    private var expectsPortalDestination = false
    private var consumedLaunchPushAddress: String?
    private var foregroundPushEnrichmentIDs = Set<String>()
    private let richPushIdentifierPrefix = "ar-rich-"

    private let lastSentPushTokenKey = "last_sent_push_token_in_config"
    private var lastSentPushTokenInConfig: String? {
        get { UserDefaults.standard.string(forKey: lastSentPushTokenKey) }
        set {
            if let newValue = newValue {
                UserDefaults.standard.set(newValue, forKey: lastSentPushTokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastSentPushTokenKey)
            }
        }
    }

    func persistSystem(_ snapshot: SessionSnapshot) {
        SystemStore.shared.save(snapshot)
    }

    func fetchSystems() -> [SavedSystem] {
        SystemStore.shared.fetchAll()
    }

    private func logTiming(_ event: String) {
        let elapsed = CACurrentMediaTime() - launchStartTime
        print(String(format: "[Timing] %+6.3fs  %@", elapsed, event))
    }

    private var didFinishCoreLaunchSetup = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        logTiming("didFinishLaunchingWithOptions begin")
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, directory: nil)
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        LaunchState.shared.resetPersistentStateOnFreshInstallIfNeeded()
        PortalPageAgent.shared.prewarm()
        NotificationHandler.shared.clearDeliveredNotificationsAndBadge()
        NotificationHandler.shared.refreshPushGrantedFromSystem()
        NotificationHandler.shared.registerForRemoteNotificationsIfAuthorized()
        performLaunchInternetCheck()
        logEmbeddedNotificationExtension()

        observeLaunchState()

        if let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            handleLaunchPushNotification(remoteNotification)
        }

        if LaunchState.shared.isPermanentNativeFlow() {
            print("[AFSDK] Permanent native flow is active.")
            didReceiveConfigResponse = true
            return true
        }

        continueLaunchFlow()
        didFinishCoreLaunchSetup = true
        return true
    }

    func attachWindow(_ newWindow: UIWindow, launchOptions: UIScene.ConnectionOptions?) {
        window = newWindow
        if let remoteNotification = launchOptions?.notificationResponse?.notification.request.content.userInfo {
            handleLaunchPushNotification(remoteNotification)
        }
        setupWindow()
        if LaunchState.shared.isPermanentNativeFlow() {
            didReceiveConfigResponse = true
            DispatchQueue.main.async { [weak self] in
                self?.updateLaunchPresentation()
            }
            return
        }
        if !didFinishCoreLaunchSetup {
            continueLaunchFlow()
            didFinishCoreLaunchSetup = true
        }
    }

    private func setupWindow() {
        guard let window = window else { return }

        let menuVC = MenuViewController()
        let navigationController = UINavigationController(rootViewController: menuVC)
        navigationController.isNavigationBarHidden = true
        mainNavigationController = navigationController

        window.rootViewController = LaunchLoaderViewController()
        window.makeKeyAndVisible()

        scheduleLaunchLoaderFinish()
    }

    private func scheduleLaunchLoaderFinish() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.logTiming("Launch loader SAFETY timeout reached (didReceiveConfigResponse=\(self.didReceiveConfigResponse))")

            if !self.didReceiveConfigResponse
                && LaunchState.shared.portalDestination == nil
                && !self.expectsPortalDestination
                && LaunchState.shared.pendingDestination == nil {
                self.logTiming("No server response within timeout — treating as no internet")
                LaunchState.shared.showNoInternetMessage()
            }

            self.updateLaunchPresentation()
        }
        launchLoaderFinishWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + launchLoaderDuration, execute: workItem)
    }

    private func cancelLoaderSafetyTimeout() {
        launchLoaderFinishWorkItem?.cancel()
        launchLoaderFinishWorkItem = nil
    }

    private func updateLaunchPresentation() {
        guard let window = window, let navigationController = mainNavigationController else { return }
        let state = LaunchState.shared

        if isLaunchLoaderActive {
            if state.noInternetMessage != nil {
                logTiming("Launch decision: no internet — showing plaque only (native stays hidden)")
                isLaunchLoaderActive = false
                cancelLoaderSafetyTimeout()
                showNoInternetScreen()
                return
            }

            if let destination = state.portalDestination {
                logTiming("Launch decision: portal — switching presentation")
                isLaunchLoaderActive = false
                expectsPortalDestination = false
                cancelLoaderSafetyTimeout()
                OrientationController.shared.unlockAllOrientations()
                switchRootToPortal(window: window, destination: destination)
                return
            }

            if state.isPrePermissionVisible {
                cancelLoaderSafetyTimeout()
                showNotificationPermissionScreen()
                return
            }

            if expectsPortalDestination || state.pendingDestination != nil {
                logTiming("Launch: portal decision pending — keeping loader")
                return
            }

            if didReceiveConfigResponse {
                logTiming("Launch decision: native experience")
                isLaunchLoaderActive = false
                cancelLoaderSafetyTimeout()
                switchRootToNative(window: window, navigationController: navigationController)
                return
            }

            return
        }

        if let destination = state.portalDestination {
            OrientationController.shared.unlockAllOrientations()
            presentPortalDestination(destination)
        } else if state.isPrePermissionVisible {
            showNotificationPermissionScreen()
        } else if state.noInternetMessage != nil {
            showNoInternetScreen()
        } else {
            ContentPresenter.shared.dismiss()
            OrientationController.shared.lockToPortrait()
        }
    }

    private func switchRootToPortal(window: UIWindow, destination: String) {
        OrientationController.shared.unlockAllOrientations()

        if let existing = rootPortal {
            if existing.destination != destination, let url = URL(string: destination) {
                existing.destination = destination
                existing.reload(address: url)
            }
            if window.rootViewController !== existing {
                existing.presentingViewController?.dismiss(animated: false)
                UIView.transition(with: window, duration: 0.25, options: .transitionCrossDissolve, animations: {
                    window.rootViewController = existing
                })
            }
            return
        }

        let portal = ContentPortalController()
        portal.destination = destination
        rootPortal = portal

        UIView.transition(with: window, duration: 0.25, options: .transitionCrossDissolve, animations: {
            window.rootViewController = portal
        }, completion: { _ in
            OrientationController.shared.unlockAllOrientations()
            portal.setNeedsUpdateOfSupportedInterfaceOrientations()
            UIViewController.attemptRotationToDeviceOrientation()
        })
    }

    private func switchRootToNative(window: UIWindow, navigationController: UINavigationController) {
        UIView.transition(with: window, duration: 0.25, options: .transitionCrossDissolve, animations: {
            window.rootViewController = navigationController
        })
    }

    private func presentPortalDestination(_ destination: String) {
        guard let window = window else { return }

        if let portal = window.rootViewController as? ContentPortalController {
            rootPortal = portal
            ContentPresenter.shared.present(destination: destination)
            return
        }

        if window.rootViewController?.presentedViewController != nil {
            window.rootViewController?.dismiss(animated: false) { [weak self] in
                guard let self = self, let window = self.window else { return }
                self.switchRootToPortal(window: window, destination: destination)
            }
        } else {
            switchRootToPortal(window: window, destination: destination)
        }
    }

    private func showNoInternetScreen() {
        guard let window = window else { return }
        if window.rootViewController is NoInternetViewController { return }

        if window.rootViewController?.presentedViewController != nil {
            window.rootViewController?.dismiss(animated: false)
        }

        let noInternetVC = NoInternetViewController()
        UIView.transition(with: window, duration: 0.25, options: .transitionCrossDissolve, animations: {
            window.rootViewController = noInternetVC
        })
    }

    private func observeLaunchState() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLaunchStateChange),
            name: LaunchState.didChangeNotification,
            object: nil
        )
    }

    @objc private func handleLaunchStateChange() {
        updateLaunchPresentation()
    }

    private func showNotificationPermissionScreen() {
        guard let topVC = topmostController() else { return }
        guard !topVC.isBeingPresented, !topVC.isBeingDismissed else { return }

        if topVC is NotificationPermissionViewController { return }
        if topVC.presentedViewController is NotificationPermissionViewController { return }

        let permissionVC = NotificationPermissionViewController()
        permissionVC.modalPresentationStyle = .fullScreen
        permissionVC.onAccept = { [weak self, weak permissionVC] in
            NotificationHandler.shared.requestSystemPermission { _ in
                self?.dismissPermissionScreenIfNeeded(permissionVC) {
                    LaunchState.shared.confirmPrePermissionAndOpen()
                }
            }
        }
        permissionVC.onSkip = { [weak self, weak permissionVC] in
            NotificationHandler.shared.registerLastDecline()
            self?.dismissPermissionScreenIfNeeded(permissionVC) {
                LaunchState.shared.confirmPrePermissionAndOpen()
            }
        }

        topVC.present(permissionVC, animated: true)
    }

    private func dismissPermissionScreenIfNeeded(
        _ permissionVC: NotificationPermissionViewController?,
        completion: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            guard let permissionVC, permissionVC.presentingViewController != nil else {
                completion()
                return
            }
            permissionVC.dismiss(animated: true, completion: completion)
        }
    }

    private func topmostController() -> UIViewController? {
        guard var top = window?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    private func performLaunchInternetCheck() {
        let monitor = NWPathMonitor()
        launchInternetMonitor = monitor
        var didDeliverInitialPath = false

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            guard !didDeliverInitialPath else { return }
            didDeliverInitialPath = true

            self.logTiming("Internet check: path.status=\(path.status)")

            self.launchInternetMonitor?.cancel()
            self.launchInternetMonitor = nil

            guard path.status != .satisfied else { return }

            DispatchQueue.main.async {
                LaunchState.shared.showNoInternetMessage()
                self.updateLaunchPresentation()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.packagepanic.launchInternetCheck"))
    }

    private func continueLaunchFlow() {
        logTiming("continueLaunchFlow")
        if LaunchState.shared.portalDestination != nil {
            print("[AFSDK] Portal destination already opened by push. Skipping launch flow.")
            return
        }

        if LaunchState.shared.activateStoredDestinationIfValid() {
            OrientationController.shared.unlockAllOrientations()
            print("[AFSDK] Stored portal destination is valid. Portal flow will open.")
            return
        }

        if let storedPayload = LaunchState.shared.storedConfigPayload() {
            print("[AFSDK] Stored portal destination expired. Reusing saved payload for config request.")
            sendMergedPayload(storedPayload)
            return
        }

        configureAppsFlyerAndStart()
    }

    private func configureAppsFlyerAndStart() {
        AppsFlyerLib.shared().appsFlyerDevKey = AppConstants.appsFlyerDevKey
        AppsFlyerLib.shared().appleAppID = AppConstants.appsFlyerAppleAppID
        AppsFlyerLib.shared().delegate = self
        AppsFlyerLib.shared().deepLinkDelegate = self

        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sendLaunch),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        sendLaunch()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        NotificationHandler.shared.clearDeliveredNotificationsAndBadge()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        NotificationHandler.shared.clearDeliveredNotificationsAndBadge()
    }

    @objc func sendLaunch() {
        guard !didStartAppsFlyer else { return }
        didStartAppsFlyer = true

        logTiming("AppsFlyer.start() called")
        AppsFlyerLib.shared().start { [weak self] dictionary, error in
            if let error = error {
                self?.logTiming("AppsFlyer.start callback ERROR: \(error.localizedDescription)")
                self?.showNoInternetMessageIfNeeded(error)
                return
            }
            if let dictionary = dictionary {
                self?.logTiming("AppsFlyer.start callback success: \(dictionary)")
            }
        }

        let appsFlyerID = AppsFlyerLib.shared().getAppsFlyerUID()
        print("AppsFlyer ID: \(appsFlyerID)")
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if LaunchState.shared.portalDestination != nil || isPortalPresented(in: window) {
            return UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
        }
        if isRotatableLaunchScreenVisible(in: window) {
            return UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
        }
        return orientationLock
    }

    private func isRotatableLaunchScreenVisible(in window: UIWindow?) -> Bool {
        guard var top = window?.rootViewController ?? self.window?.rootViewController else { return false }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top is LaunchLoaderViewController
            || top is NotificationPermissionViewController
            || top is NoInternetViewController
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        AppsFlyerLib.shared().continue(userActivity, restorationHandler: nil)
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        AppsFlyerLib.shared().handleOpen(url, options: options)
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        AppsFlyerLib.shared().registerUninstall(deviceToken)
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        logTiming("APNs token received: \(tokenString.prefix(12))...")
        NotificationHandler.shared.markPushGranted()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logTiming("APNs registration FAILED: \(error.localizedDescription)")
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        logPushPayload(userInfo, source: "didReceiveRemoteNotification")
        completionHandler(.newData)
    }

    private func handleRemoteNotificationUserInfo(_ userInfo: [AnyHashable: Any], fromUserTap: Bool) {
        guard fromUserTap else { return }

        guard let addressString = extractPushAddress(from: userInfo) else {
            print("[Push] Tap ignored — no valid url field in payload")
            return
        }

        if consumedLaunchPushAddress == addressString {
            consumedLaunchPushAddress = nil
            print("[Push] Tap already handled via cold launch slot — skipping duplicate")
            return
        }

        if isLaunchLoaderActive && LaunchState.shared.portalDestination == nil {
            print("[Push] Cold-launch tap fallback — opening URL during launch: \(addressString)")
            DispatchQueue.main.async {
                LaunchState.shared.handleIncomingPushAddress(addressString)
            }
            return
        }

        guard LaunchState.shared.hasStoredDestination() else {
            print("[Push] Tap ignored — app is running with no stored link in memory")
            return
        }
        print("[Push] App already running with stored link — navigating to push URL: \(addressString)")
        DispatchQueue.main.async { [weak self] in
            self?.presentPortalDestination(addressString)
        }
    }

    private func handleLaunchPushNotification(_ userInfo: [AnyHashable: Any]) {
        logPushPayload(userInfo, source: "coldLaunch (launchOptions)")

        guard !LaunchState.shared.isPermanentNativeFlow() else {
            print("[Push] Cold launch push ignored — permanent native flow is active")
            return
        }
        guard let addressString = extractPushAddress(from: userInfo) else {
            print("[Push] Cold launch push ignored — no valid url field in payload")
            return
        }

        print("[Push] Cold launch push url saved to one-time slot: \(addressString)")
        consumedLaunchPushAddress = addressString
        LaunchState.shared.savePushDestination(addressString)
    }

    private func logPushPayload(
        _ userInfo: [AnyHashable: Any],
        source: String,
        content: UNNotificationContent? = nil,
        extraLines: [String] = []
    ) {
        let safe = sanitizedPushPayload(userInfo)
        let aps = userInfo["aps"] as? [AnyHashable: Any]
        let mutableContentValue = aps?["mutable-content"]
        let hasMutableContent = mutableContentValue != nil
        let imageAddress = pushImageAddress(in: userInfo)
        let appAddress = extractPushAddress(from: userInfo)
        let topLevelKeys = userInfo.keys.compactMap { $0 as? String }.sorted().joined(separator: ", ")
        let alert = aps?["alert"]
        let alertTitle = pushAlertField(from: alert, key: "title") ?? content?.title
        let alertBody = pushAlertField(from: alert, key: "body") ?? content?.body

        print("==========================================")
        print("[Push] \(pushLogTimestamp())  source=\(source)")
        print("[Push] appState=\(applicationStateName())")
        print("[Push] top-level keys: \(topLevelKeys.isEmpty ? "<none>" : topLevelKeys)")
        print("[Push] title: \(alertTitle ?? "<none>")")
        print("[Push] body: \(alertBody ?? "<none>")")
        if hasMutableContent {
            print("[Push] mutable-content: \(String(describing: mutableContentValue!)) (present — NSE can run)")
        } else {
            print("[Push] mutable-content: MISSING — rich image will not work")
        }
        print("[Push] image address: \(imageAddress ?? "<none>")")
        print("[Push] app url: \(appAddress ?? "<none>")")

        if let content {
            print("[Push] delivered attachments: \(content.attachments.count)")
            if content.attachments.isEmpty, imageAddress != nil {
                print("[Push] WARNING: image URL is present but no attachment arrived — check [PushExt] logs in Console (filter: PushExt)")
            }
            for (index, attachment) in content.attachments.enumerated() {
                print("[Push] attachment[\(index)]: id=\(attachment.identifier), type=\(attachment.type), url=\(attachment.url.lastPathComponent)")
            }
            if let badge = content.badge {
                print("[Push] badge: \(badge)")
            }
            if !content.categoryIdentifier.isEmpty {
                print("[Push] category: \(content.categoryIdentifier)")
            }
        }

        for line in extraLines {
            print("[Push] \(line)")
        }

        printAsJSON(label: "Push payload JSON", payload: safe)
        print("==========================================")
    }

    private func pushLogTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private func applicationStateName() -> String {
        switch UIApplication.shared.applicationState {
        case .active:
            return "active"
        case .inactive:
            return "inactive"
        case .background:
            return "background"
        @unknown default:
            return "unknown"
        }
    }

    private func pushAlertField(from alert: Any?, key: String) -> String? {
        if let dictionary = alert as? [AnyHashable: Any],
           let value = dictionary[key] as? String,
           !value.isEmpty {
            return value
        }
        if key == "body", let value = alert as? String, !value.isEmpty {
            return value
        }
        return nil
    }

    private func sanitizedPushPayload(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in userInfo {
            guard let stringKey = key as? String else { continue }
            result[stringKey] = jsonSafeValue(value)
        }
        return result
    }

    private func pushImageAddress(in userInfo: [AnyHashable: Any]) -> String? {
        let keys = [
            "image",
            "image_url",
            "imageUrl",
            "picture",
            "thumbnail",
            "attachment-url",
            "attachment_url",
            "gcm.n.image",
            "gcm.notification.image",
            "google.c.a.c_image"
        ]
        for key in keys {
            if let value = userInfo[key] as? String, !value.isEmpty {
                return value
            }
        }
        if let fcmOptions = userInfo["fcm_options"] as? [AnyHashable: Any],
           let value = fcmOptions["image"] as? String, !value.isEmpty {
            return value
        }
        if let fcmOptions = userInfo["fcm_options"] as? [AnyHashable: Any],
           let value = fcmOptions["imageUrl"] as? String, !value.isEmpty {
            return value
        }
        if let data = userInfo["data"] as? [AnyHashable: Any] {
            for key in keys {
                if let value = data[key] as? String, !value.isEmpty {
                    return value
                }
            }
        }
        if let message = userInfo["message"] as? [AnyHashable: Any],
           let data = message["data"] as? [AnyHashable: Any] {
            for key in keys {
                if let value = data[key] as? String, !value.isEmpty {
                    return value
                }
            }
        }
        return recursivePushImageAddress(in: userInfo)
    }

    private func recursivePushImageAddress(in value: Any) -> String? {
        if let dictionary = value as? [AnyHashable: Any] {
            for (key, nestedValue) in dictionary {
                if let key = key as? String,
                   isPushImageKey(key),
                   let address = nestedValue as? String,
                   !address.isEmpty {
                    return address
                }
                if let address = recursivePushImageAddress(in: nestedValue) {
                    return address
                }
            }
        }

        if let array = value as? [Any] {
            for item in array {
                if let address = recursivePushImageAddress(in: item) {
                    return address
                }
            }
        }

        return nil
    }

    private func isPushImageKey(_ key: String) -> Bool {
        let lowercased = key.lowercased()
        return lowercased.contains("image")
            || lowercased.contains("picture")
            || lowercased.contains("thumbnail")
    }

    private func presentForegroundPushNotification(
        _ notification: UNNotification,
        completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content
        let requestID = notification.request.identifier

        if requestID.hasPrefix(richPushIdentifierPrefix) || !content.attachments.isEmpty {
            completionHandler([.banner, .list, .sound, .badge])
            return
        }

        guard let imageURLString = pushImageAddress(in: content.userInfo),
              let imageURL = URL(string: imageURLString) else {
            completionHandler([.banner, .list, .sound, .badge])
            return
        }

        guard !foregroundPushEnrichmentIDs.contains(requestID) else {
            completionHandler([.banner, .list, .sound, .badge])
            return
        }

        foregroundPushEnrichmentIDs.insert(requestID)
        print("[Push] NSE did not attach image — downloading in app for foreground banner: \(imageURLString)")

        completionHandler([.banner, .list, .sound, .badge])

        downloadPushImageAttachment(from: imageURL) { [weak self] attachment in
            guard let self else { return }
            defer { self.foregroundPushEnrichmentIDs.remove(requestID) }

            guard let attachment else {
                print("[Push] Foreground image download failed — text-only banner remains.")
                return
            }

            let mutable = UNMutableNotificationContent()
            mutable.title = content.title
            mutable.body = content.body
            mutable.subtitle = content.subtitle
            mutable.userInfo = content.userInfo
            mutable.sound = content.sound
            mutable.badge = content.badge
            mutable.attachments = [attachment]

            let richID = self.richPushIdentifierPrefix + requestID
            let request = UNNotificationRequest(
                identifier: richID,
                content: mutable,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    print("[Push] Failed to repost rich foreground notification: \(error.localizedDescription)")
                    return
                }
                print("[Push] Foreground rich banner reposted with attachment.")
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [requestID])
            }
        }
    }

    private func logEmbeddedNotificationExtension() {
        guard let pluginsURL = Bundle.main.builtInPlugInsURL else {
            print("[Push] PlugIns directory not found — notification service extension is missing from app bundle.")
            return
        }

        let pluginNames = (try? FileManager.default.contentsOfDirectory(atPath: pluginsURL.path)) ?? []
        print("[Push] Embedded plugins: \(pluginNames.isEmpty ? "<none>" : pluginNames.joined(separator: ", "))")

        let hasNotificationService = pluginNames.contains { $0.hasSuffix(".appex") && $0.contains("NotificationService") }
        if hasNotificationService {
            print("[Push] Notification Service Extension is embedded.")
        } else {
            print("[Push] WARNING: Notification Service Extension is NOT embedded — lock screen/background rich push will not work.")
        }
    }

    private func downloadPushImageAttachment(from address: URL, completion: @escaping (UNNotificationAttachment?) -> Void) {
        var request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.timeoutInterval = 10
        request.setValue(
            PortalPageAgent.shared.cachedValue() ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("image/jpeg,image/png,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                print("[Push] Foreground image download error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[Push] Foreground image download status: \(statusCode), bytes: \(data?.count ?? 0)")

            guard let data,
                  !data.isEmpty,
                  (200...299).contains(statusCode),
                  let image = UIImage(data: data),
                  let jpegData = image.jpegData(compressionQuality: 0.85) else {
                completion(nil)
                return
            }

            let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("PushAttachments", isDirectory: true)
            let fileAddress = directory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")

            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try jpegData.write(to: fileAddress, options: [.atomic])
                let attachment = try UNNotificationAttachment(
                    identifier: "image",
                    url: fileAddress,
                    options: [UNNotificationAttachmentOptionsTypeHintKey: "public.jpeg"]
                )
                completion(attachment)
            } catch {
                print("[Push] Foreground attachment creation failed: \(error.localizedDescription)")
                completion(nil)
            }
        }.resume()
    }

    private func extractPushAddress(from userInfo: [AnyHashable: Any]) -> String? {
        if let address = validPushAddress(from: userInfo[AppConstants.pushDataAddressKey]) {
            return address
        }

        if let data = parsedDictionary(userInfo["data"]),
           let address = validPushAddress(from: data[AppConstants.pushDataAddressKey]) {
            return address
        }

        if let message = parsedDictionary(userInfo["message"]) {
            if let address = validPushAddress(from: message[AppConstants.pushDataAddressKey]) {
                return address
            }
            if let data = parsedDictionary(message["data"]),
               let address = validPushAddress(from: data[AppConstants.pushDataAddressKey]) {
                return address
            }
        }

        return nil
    }

    private func parsedDictionary(_ value: Any?) -> [AnyHashable: Any]? {
        if let dictionary = value as? [AnyHashable: Any] {
            return dictionary
        }
        if let string = value as? String,
           let data = string.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let dictionary = json as? [AnyHashable: Any] {
            return dictionary
        }
        return nil
    }

    private func validPushAddress(from value: Any?) -> String? {
        guard let string = value as? String, isValidWebAddress(string) else { return nil }
        return string
    }

    private func isValidWebAddress(_ value: String) -> Bool {
        guard let address = URL(string: value), let scheme = address.scheme?.lowercased() else { return false }
        return ["http", "https"].contains(scheme)
    }

    private func printMergedPayloadIfNeeded(force: Bool = false) {
        guard !didPrintMergedPayload else { return }
        guard !isWaitingForGCDConversion else { return }

        let hasConversion = conversionData != nil
        let hasDeepLink = deepLinkData != nil

        guard hasConversion else {
            print("[AFSDK] Conversion data is missing. Native flow will remain active.")
            return
        }

        let bothReady = hasConversion && hasDeepLink
        let canPrint = bothReady || (force && (hasConversion || hasDeepLink))

        guard canPrint else {
            if hasConversion || hasDeepLink {
                scheduleMergeTimeout()
            }
            return
        }

        mergeTimerWorkItem?.cancel()
        mergeTimerWorkItem = nil
        didPrintMergedPayload = true

        var merged: [String: Any] = deepLinkData ?? [:]
        if let conversion = conversionData {
            for (key, value) in conversion {
                merged[key] = value
            }
        }

        finalizeAndSendMergedPayload(merged)
    }

    private func handleConversionData(_ data: [String: Any], shouldRetryOrganicWithGCD: Bool) {
        logTiming("handleConversionData (af_status=\(data["af_status"] ?? "nil"))")
        let status = data["af_status"] as? String
        let isOrganic = status?.localizedCaseInsensitiveCompare("Organic") == .orderedSame

        if isOrganic && shouldRetryOrganicWithGCD {
            isWaitingForGCDConversion = true
            cancelMergeTimeout()
            print("This is an Organic install.")
            print("[AFSDK] Organic conversion received. GCD retry will start in \(Int(AppConstants.gcdRetryDelay)) seconds.")
            DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.gcdRetryDelay) { [weak self] in
                self?.logTiming("GCD retry delay finished, fetching GCD")
                self?.fetchGCDConversionData(fallback: data)
            }
            return
        }

        conversionData = data

        if status?.localizedCaseInsensitiveCompare("Non-organic") == .orderedSame {
            if let sourceID = data["media_source"],
               let campaign = data["campaign"] {
                print("This is a Non-organic install. Media source: \(sourceID)  Campaign: \(campaign)")
            }
        } else if isOrganic {
            print("This is an Organic install.")
        }

        printMergedPayloadIfNeeded()
    }

    private func fetchGCDConversionData(fallback: [String: Any]) {
        fetchGCDConversionData(
            fallback: fallback,
            candidates: gcdDeviceIDCandidates(),
            index: 0
        )
    }

    private func gcdDeviceIDCandidates() -> [(label: String, value: String)] {
        var candidates: [(label: String, value: String)] = [
            ("appsFlyerUID", AppsFlyerLib.shared().getAppsFlyerUID())
        ]

        if let idfv = UIDevice.current.identifierForVendor?.uuidString,
           !idfv.isEmpty {
            candidates.append(("idfv", idfv))
        }

        return candidates
    }

    private func fetchGCDConversionData(fallback: [String: Any], candidates: [(label: String, value: String)], index: Int) {
        guard index < candidates.count else {
            finishGCDConversionData(fallback)
            return
        }

        let candidate = candidates[index]
        var components = URLComponents()
        components.scheme = "https"
        components.host = "gcdsdk.appsflyer.com"
        components.path = "/install_data/v4.0/\(AppConstants.storeID)"
        components.queryItems = [
            URLQueryItem(name: "devkey", value: AppConstants.appsFlyerDevKey),
            URLQueryItem(name: "device_id", value: candidate.value)
        ]

        guard let address = components.url else {
            finishGCDConversionData(fallback)
            return
        }

        var request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        print("[AFSDK] GCD request with \(candidate.label): \(address.absoluteString)")
        logTiming("GCD request sent (\(candidate.label))")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            self?.logTiming("GCD response received (\(candidate.label))")
            if let error = error {
                print("[AFSDK] GCD request error: \(error.localizedDescription)")
                self?.showNoInternetMessageIfNeeded(error)
                DispatchQueue.main.async {
                    self?.finishGCDConversionData(fallback)
                }
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[AFSDK] GCD response status: \(statusCode)")
            if statusCode == 404, index + 1 < candidates.count {
                print("[AFSDK] GCD returned 404 for \(candidate.label). Trying next device_id candidate.")
                self?.fetchGCDConversionData(fallback: fallback, candidates: candidates, index: index + 1)
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let payload = json as? [String: Any] else {
                if let data = data, let responseBody = String(data: data, encoding: .utf8), !responseBody.isEmpty {
                    print("[AFSDK] GCD response body: \(responseBody)")
                }
                DispatchQueue.main.async {
                    self?.finishGCDConversionData(fallback)
                }
                return
            }

            var safePayload: [String: Any] = [:]
            for (key, value) in payload {
                safePayload[key] = self?.jsonSafeValue(value) ?? value
            }

            DispatchQueue.main.async {
                self?.printAsJSON(label: "GCD Conversion data JSON", payload: safePayload)
                self?.finishGCDConversionData(safePayload)
            }
        }.resume()
    }

    private func finishGCDConversionData(_ data: [String: Any]) {
        isWaitingForGCDConversion = false
        conversionData = data
        printMergedPayloadIfNeeded()
    }

    private func injectTemplateFields(into merged: inout [String: Any]) {
        let templateKeys: [String: Any] = [
            "af_id": AppsFlyerLib.shared().getAppsFlyerUID(),
            "bundle_id": AppConstants.bundleID,
            "os": AppConstants.osName,
            "store_id": AppConstants.storeID,
            "locale": currentLocaleRFC3066(),
            "push_token": NotificationHandler.shared.currentPushToken(),
            "firebase_project_id": AppConstants.firebaseProjectID
        ]
        for (key, value) in templateKeys {
            merged[key] = value
        }
    }

    private func finalizeAndSendMergedPayload(_ mergedBeforeTemplate: [String: Any]) {
        var merged = mergedBeforeTemplate
        injectTemplateFields(into: &merged)
        
        let flat = flattenedPayload(merged)
                        
        LaunchState.shared.saveConfigPayload(flat)
        printAsJSON(label: "Merged payload", payload: flat)
        sendMergedPayload(flat)
    }

    private func flattenedPayload(_ payload: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (_, value) in payload {
            if let nested = value as? [String: Any] {
                for (nestedKey, nestedValue) in nested {
                    result[nestedKey] = nestedValue
                }
            }
        }
        for (key, value) in payload where !(value is [String: Any]) {
            result[key] = value
        }
        return result
    }

    private func sendMergedPayload(_ payload: [String: Any], applyDestinationToCurrentSession: Bool = true) {
        guard let address = URL(string: AppConstants.configEndpoint) else { return }
        guard JSONSerialization.isValidJSONObject(payload),
              let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            print("[AFSDK] Failed to serialize merged payload for upload")
            return
        }

        if let token = payload["push_token"] as? String,
           !token.isEmpty,
           token != AppConstants.pushTokenPlaceholder {
            lastSentPushTokenInConfig = token
        }

        var request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.httpBody = body
        request.timeoutInterval = 12

        logTiming("Config POST sent to \(AppConstants.configEndpoint)")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            self?.logTiming("Config POST response received")
            if let error = error {
                print("[AFSDK] Merged payload upload error: \(error.localizedDescription)")
                self?.showNoInternetMessageIfNeeded(error)
                print("[AFSDK] Native flow will remain active.")
                DispatchQueue.main.async {
                    self?.didReceiveConfigResponse = true
                    self?.expectsPortalDestination = false
                    self?.updateLaunchPresentation()
                }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[AFSDK] Merged payload upload status: \(status)")
            if !responseBody.isEmpty {
                print("[AFSDK] Merged payload response body: \(responseBody)")
            }
            self?.logTiming("handleMergedPayloadResponse start")
            let expectsPortal = self?.handleMergedPayloadResponse(
                data: data,
                applyDestinationToCurrentSession: applyDestinationToCurrentSession
            ) ?? false
            self?.logTiming("handleMergedPayloadResponse done (decision made)")
            DispatchQueue.main.async {
                self?.didReceiveConfigResponse = true
                self?.expectsPortalDestination = expectsPortal
                self?.updateLaunchPresentation()
            }
        }.resume()
    }

    @discardableResult
    private func handleMergedPayloadResponse(
        data: Data?,
        applyDestinationToCurrentSession: Bool = true
    ) -> Bool {
        guard !LaunchState.shared.isPermanentNativeFlow() else {
            print("[AFSDK] Permanent native flow is active. Ignoring portal destination from server response.")
            return false
        }

        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data),
              let payload = json as? [String: Any] else {
            print("[AFSDK] Server response is empty or invalid. Native flow will remain active.")
            LaunchState.shared.recordFirstServerDecision(hasValidLink: false)
            if LaunchState.shared.isPermanentNativeFlow() {
                print("[AFSDK] First server response had no valid link. Permanent native flow was saved.")
            }
            return false
        }

        let hasOK = (payload["ok"] as? Bool) == true
        let destination = portalDestination(from: payload)
        let expires = portalDestinationExpires(from: payload)
        let hasValidLink = hasOK && destination != nil

        LaunchState.shared.recordFirstServerDecision(hasValidLink: hasValidLink)
        if LaunchState.shared.isPermanentNativeFlow() {
            print("[AFSDK] First server response had no valid link. Permanent native flow was saved.")
            return false
        }

        guard hasOK else {
            print("[AFSDK] Server returned ok=false. Native flow will remain active.")
            return false
        }

        guard let destination = destination else {
            print("[AFSDK] Server returned ok=true without a destination. Native flow will remain active.")
            return false
        }

        let resolvedExpires = expires ?? 0
        if let expires = expires, expires <= Date().timeIntervalSince1970 {
            print("[AFSDK] Server returned expired/equal expires (\(expires)) — saving anyway; will re-request on next launch.")
        }

        DispatchQueue.main.async {
            if applyDestinationToCurrentSession {
                OrientationController.shared.unlockAllOrientations()
                LaunchState.shared.saveDestination(destination, expires: resolvedExpires)
            } else {
                LaunchState.shared.persistDestinationWithoutOpening(destination, expires: resolvedExpires)
            }
        }
        return applyDestinationToCurrentSession
    }

    private func showNoInternetMessageIfNeeded(_ error: Error) {
        guard let networkError = error as? URLError else { return }
        let offlineCodes: [URLError.Code] = [
            .notConnectedToInternet,
            .networkConnectionLost,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .timedOut
        ]
        guard offlineCodes.contains(networkError.code) else { return }
        DispatchQueue.main.async {
            LaunchState.shared.showNoInternetMessage()
        }
    }

    private func portalDestination(from payload: [String: Any]) -> String? {
        let keys = ["url", "link", "destination", "browser_url", "browserUrl"]
        for key in keys {
            if let value = payload[key] as? String,
               let address = URL(string: value),
               let scheme = address.scheme?.lowercased(),
               ["http", "https"].contains(scheme) {
                return value
            }
        }
        if let data = payload["data"] as? [String: Any] {
            return portalDestination(from: data)
        }
        return nil
    }

    private func portalDestinationExpires(from payload: [String: Any]) -> TimeInterval? {
        if let value = payload["expires"] as? TimeInterval {
            return value
        }
        if let value = payload["expires"] as? Int {
            return TimeInterval(value)
        }
        if let value = payload["expires"] as? String,
           let interval = TimeInterval(value) {
            return interval
        }
        if let data = payload["data"] as? [String: Any] {
            return portalDestinationExpires(from: data)
        }
        return nil
    }

    private func scheduleMergeTimeout() {
        guard mergeTimerWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.mergeTimerWorkItem = nil
            self?.printMergedPayloadIfNeeded(force: true)
        }
        mergeTimerWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.mergeWaitInterval, execute: workItem)
    }

    private func cancelMergeTimeout() {
        mergeTimerWorkItem?.cancel()
        mergeTimerWorkItem = nil
    }

    private func currentLocaleRFC3066() -> String {
        if let preferred = Locale.preferredLanguages.first, !preferred.isEmpty {
            return preferred
        }
        return Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    }

    fileprivate func jsonSafeValue(_ value: Any) -> Any {
        if let date = value as? Date {
            let formatter = ISO8601DateFormatter()
            return formatter.string(from: date)
        }
        if let address = value as? URL {
            return address.absoluteString
        }
        if let dict = value as? [AnyHashable: Any] {
            var result: [String: Any] = [:]
            for (key, value) in dict {
                guard let stringKey = key as? String else { continue }
                result[stringKey] = jsonSafeValue(value)
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map { jsonSafeValue($0) }
        }
        if value is NSNull { return NSNull() }
        if JSONSerialization.isValidJSONObject([value]) {
            return value
        }
        if value is NSNumber || value is String || value is Bool || value is Int || value is Double {
            return value
        }
        return "\(value)"
    }

    private func isPortalPresented(in window: UIWindow?) -> Bool {
        if let root = window?.rootViewController {
            return containsPortalController(in: root)
        }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for sceneWindow in scene.windows where containsPortalController(in: sceneWindow.rootViewController) {
                return true
            }
        }
        return false
    }

    private func containsPortalController(in root: UIViewController?) -> Bool {
        guard var top = root else { return false }
        if top is ContentPortalController {
            return true
        }
        while let presented = top.presentedViewController {
            if presented is ContentPortalController {
                return true
            }
            top = presented
        }
        return false
    }

    fileprivate func printAsJSON(label: String, payload: Any) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let jsonString = String(data: data, encoding: .utf8) else {
            print("[AFSDK] \(label) (raw): \(payload)")
            return
        }
        print("[AFSDK] \(label):")
        print(jsonString)
    }
}

extension AppDelegate: AppsFlyerLibDelegate {
    func onConversionDataSuccess(_ installData: [AnyHashable: Any]) {
        logTiming("onConversionDataSuccess")
        print("==========================================")

        var stringKeyed: [String: Any] = [:]
        for (key, value) in installData {
            guard let stringKey = key as? String else { continue }
            stringKeyed[stringKey] = jsonSafeValue(value)
        }

        printAsJSON(label: "Conversion data JSON", payload: stringKeyed)
        print("==========================================")

        handleConversionData(stringKeyed, shouldRetryOrganicWithGCD: true)
    }

    func onConversionDataFail(_ error: Error) {
        logTiming("onConversionDataFail: \(error.localizedDescription)")
        print("==========================================")
        print("Conversion data error: \(error.localizedDescription)")
        print("==========================================")
        showNoInternetMessageIfNeeded(error)

        printMergedPayloadIfNeeded()
    }
}

extension AppDelegate: DeepLinkDelegate {
    func didResolveDeepLink(_ result: DeepLinkResult) {
        logTiming("didResolveDeepLink (status=\(result.status))")
        print("==========================================")
        print("[AFSDK] didResolveDeepLink called")

        switch result.status {
        case .notFound:
            print("[AFSDK] Deep link not found")
            print("==========================================")
            deepLinkData = [:]
            printMergedPayloadIfNeeded()
            return
        case .failure:
            if let error = result.error {
                print("[AFSDK] Deep link error: \(error.localizedDescription)")
            }
            print("==========================================")
            deepLinkData = [:]
            printMergedPayloadIfNeeded()
            return
        case .found:
            print("[AFSDK] Deep link found")
        @unknown default:
            print("[AFSDK] Deep link unknown status")
            print("==========================================")
            deepLinkData = [:]
            printMergedPayloadIfNeeded()
            return
        }

        guard let deepLinkObj: DeepLink = result.deepLink else {
            print("[AFSDK] Could not extract deep link object")
            print("==========================================")
            printMergedPayloadIfNeeded()
            return
        }

        if deepLinkObj.isDeferred {
            print("[AFSDK] This is a deferred deep link")
        } else {
            print("[AFSDK] This is a direct deep link")
        }

        var jsonPayload: [String: Any] = [:]
        jsonPayload["isDeferred"] = deepLinkObj.isDeferred
        for (key, value) in deepLinkObj.clickEvent {
            jsonPayload[key] = jsonSafeValue(value)
        }
        if let deepLinkValue = deepLinkObj.deeplinkValue {
            jsonPayload["deep_link_value"] = deepLinkValue
        }
        if let matchType = deepLinkObj.matchType {
            jsonPayload["match_type"] = matchType
        }
        if let mediaSource = deepLinkObj.mediaSource {
            jsonPayload["media_source"] = mediaSource
        }
        if let campaign = deepLinkObj.campaign {
            jsonPayload["campaign"] = campaign
        }
        if let campaignId = deepLinkObj.campaignId {
            jsonPayload["campaign_id"] = campaignId
        }

        deepLinkData = jsonPayload

        printAsJSON(label: "DeepLink JSON", payload: jsonPayload)

        print("==========================================")

        printMergedPayloadIfNeeded()
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken = fcmToken else {
            logTiming("FCM token callback with nil token")
            return
        }
        logTiming("FCM token received: \(fcmToken.prefix(20))...")
        NotificationHandler.shared.storeFcmToken(fcmToken)
        resendConfigWithUpdatedPushTokenIfNeeded(fcmToken)
    }

    private func resendConfigWithUpdatedPushTokenIfNeeded(_ token: String) {
        logTiming("resendConfigWithUpdatedPushTokenIfNeeded called (token=\(token.prefix(12))...)")

        guard !token.isEmpty,
              token != AppConstants.pushTokenPlaceholder else {
            print("[Push] Token is empty or placeholder, skip resend.")
            return
        }

        guard NotificationHandler.shared.isPushGranted() else {
            print("[Push] Push permission not granted yet, skip resend (isPushGranted=false).")
            return
        }

        if token == lastSentPushTokenInConfig {
            print("[Push] Token unchanged since last config send, skip resend.")
            return
        }

        guard var storedPayload = LaunchState.shared.storedConfigPayload() else {
            print("[Push] No stored config payload yet. Will be sent normally on next config request.")
            return
        }

        storedPayload["push_token"] = token
        LaunchState.shared.saveConfigPayload(storedPayload)
        lastSentPushTokenInConfig = token

        logTiming("Resending config POST with updated push_token")
        printAsJSON(label: "Updated payload (push_token refresh)", payload: storedPayload)
        sendMergedPayload(storedPayload, applyDestinationToCurrentSession: false)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let content = notification.request.content
        logPushPayload(
            content.userInfo,
            source: "willPresent (foreground banner)",
            content: content
        )
        presentForegroundPushNotification(notification, completionHandler: completionHandler)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        logPushPayload(
            content.userInfo,
            source: "didReceive (tap)",
            content: content,
            extraLines: [
                "actionIdentifier=\(response.actionIdentifier)",
                "notificationId=\(response.notification.request.identifier)"
            ]
        )
        handleRemoteNotificationUserInfo(content.userInfo, fromUserTap: true)
        completionHandler()
    }
}
