import SwiftUI

/// In-app language override. `.system` means "use the device's language" (restricted to the
/// languages this app ships: zh-Hans / ja / en).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, zhHans = "zh-Hans", ja, en

    static let storageKey = "appLanguage"
    static let supportedCodes = ["zh-Hans", "ja", "en"]

    var id: String { rawValue }

    /// Concrete language code, resolving `.system` against the device's preferred languages.
    var resolvedCode: String {
        switch self {
        case .system:
            Bundle.preferredLocalizations(from: Self.supportedCodes, forPreferences: Locale.preferredLanguages).first ?? "en"
        case .zhHans, .ja, .en:
            rawValue
        }
    }

    /// Locale to inject into the SwiftUI environment so `Text`/`LocalizedStringKey` pick it up live.
    var locale: Locale { Locale(identifier: resolvedCode) }

    /// Bundle for resolving strings outside SwiftUI's environment (e.g. CameraManager callbacks),
    /// where `.environment(\.locale, ...)` has no effect since there's no view hierarchy involved.
    var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: resolvedCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    var displayName: LocalizedStringKey {
        switch self {
        case .system: "跟随系统"
        case .zhHans: "简体中文"
        case .ja: "日本語"
        case .en: "English"
        }
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }
}

/// Resolves a user-facing string for the currently selected app language from non-View code.
/// `String(localized:)` / `NSLocalizedString` would use the system language instead, since they
/// don't see the `.environment(\.locale, ...)` override applied at the view root.
enum L10n {
    static func t(_ key: String) -> String {
        AppLanguage.current.bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }
}
