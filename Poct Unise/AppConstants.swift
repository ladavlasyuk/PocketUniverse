import Foundation

enum AppConstants {
    static let appsFlyerDevKey = "75pgdgD466n96QULmUkDBG"
    static let appsFlyerAppleAppID = "6806325130"

    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.PocketUniverseCosmicSandbox"
    }
    static var storeID: String {
        "id\(appsFlyerAppleAppID)"
    }

    static let configEndpoint = "https://pocketunivercosmicsandbox.online/config.php"
    static let privacyPolicyAddress = "https://pocketunivercosmicsandbox.online/privacy-policy.html"

    static let osName = "IOS"
    static let pushTokenPlaceholder = "00000000000000000000"
    static let firebaseProjectID = "469611218154"

    static let gcdRetryDelay: TimeInterval = 1.0
    static let mergeWaitInterval: TimeInterval = 3.0
    static let launchLoaderDuration: TimeInterval = 15.0

    static let pushPermissionRetryDelay: TimeInterval = 60 * 60 * 24 * 3

    static let pushDataAddressKey = "url"
}
