import Foundation

/// Shared storage between the app and the widget extension.
enum AppGroup {
    static let id = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String
        ?? "RNUS5696SB.ca.perpetualmedia.XWidget"

    static let keychainGroup = Bundle.main.object(forInfoDictionaryKey: "KeychainGroup") as? String
        ?? "RNUS5696SB.ca.perpetualmedia.XWidget.shared"

    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.temporaryDirectory
    }

    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
}

enum SettingsKey {
    static let clientID = "xClientID"
    static let pollInterval = "pollInterval"
    static let overlayEnabled = "overlayEnabled"
    static let overlayEdge = "overlayEdge"
    static let overlayWidth = "overlayWidth"
    static let overlayStyle = "overlayStyle"
    static let overlayFeed = "overlayFeed"
    static let overlayDisplay = "overlayDisplay"
}
