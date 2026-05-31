import AppKit
import SwiftUI

/// The user's chosen interface appearance. `system` follows macOS; `light`
/// and `dark` force the respective palette regardless of the OS setting.
///
/// Dark is the original Gargantua "void" theme and remains the default so
/// existing users see no change until they opt into something else.
public enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public static let userDefaultsKey = "appAppearance"
    public static let defaultValue: AppAppearance = .dark

    /// Resolve from a raw stored value, falling back to the default.
    public init(storedValue: String?) {
        self = storedValue.flatMap(AppAppearance.init(rawValue:)) ?? AppAppearance.defaultValue
    }

    public var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    public var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon.stars"
        }
    }

    /// SwiftUI color scheme to force; `nil` lets the view hierarchy follow the
    /// system appearance.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// AppKit appearance to force on `NSApp` / windows; `nil` follows system.
    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

public enum AppAppearancePreference {
    public static var current: AppAppearance {
        AppAppearance(storedValue: UserDefaults.standard.string(forKey: AppAppearance.userDefaultsKey))
    }

    /// Apply the appearance to the running application and all open windows.
    /// Setting `NSApp.appearance = nil` makes the app follow the system.
    @MainActor
    public static func apply(_ appearance: AppAppearance = current) {
        NSApp?.appearance = appearance.nsAppearance
        for window in NSApplication.shared.windows {
            window.appearance = appearance.nsAppearance
        }
    }
}
