import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case spanish = "es"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"

    var id: String { rawValue }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var menuTitle: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .chineseSimplified: return "简体中文"
        case .chineseTraditional: return "繁體中文"
        }
    }

    static func fromSystem() -> AppLanguage {
        for identifier in Locale.preferredLanguages {
            let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            if normalized.hasPrefix("es") {
                return .spanish
            }
            if normalized.hasPrefix("en") {
                return .english
            }
            if normalized.hasPrefix("zh-hant") || normalized.hasPrefix("zh-tw") || normalized.hasPrefix("zh-hk") || normalized.hasPrefix("zh-mo") {
                return .chineseTraditional
            }
            if normalized.hasPrefix("zh") {
                return .chineseSimplified
            }
        }
        return .english
    }
}

@MainActor
@Observable
final class LanguageController {
    static let shared = LanguageController()
    private static let storageKey = "pubmerge.appLanguage"

    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    var locale: Locale { language.locale }

    init() {
        if let stored = UserDefaults.standard.string(forKey: Self.storageKey),
           let language = AppLanguage(rawValue: stored) {
            self.language = language
        } else {
            self.language = .fromSystem()
        }
    }

    func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), locale: locale)
    }
}
