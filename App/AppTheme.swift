import SwiftUI

enum AppThemeID: String, CaseIterable, Identifiable {
    case system
    case amber
    case crt
    case cyan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "標準"
        case .amber: return "アンバー（A）"
        case .crt: return "CRT緑（B）"
        case .cyan: return "シアン（C）"
        }
    }

    var subtitle: String {
        switch self {
        case .system: return "システムの見た目"
        case .amber: return "温かいカセット／アーケード"
        case .crt: return "クールな端末コンソール"
        case .cyan: return "16ビットRPG寄り"
        }
    }
}

struct AppTheme: Equatable {
    var id: AppThemeID
    var accent: Color
    var background: Color
    var panel: Color
    var primaryText: Color
    var secondaryText: Color
    /// `nil` = follow system light/dark.
    var colorScheme: ColorScheme?

    static func resolved(_ id: AppThemeID) -> AppTheme {
        switch id {
        case .system:
            return AppTheme(
                id: .system,
                accent: Color.accentColor,
                background: Color(.systemGroupedBackground),
                panel: Color(.secondarySystemGroupedBackground),
                primaryText: Color.primary,
                secondaryText: Color.secondary,
                colorScheme: nil
            )
        case .amber:
            return AppTheme(
                id: .amber,
                accent: Color(red: 0.91, green: 0.66, blue: 0.22),
                background: Color(red: 0.06, green: 0.05, blue: 0.05),
                panel: Color(red: 0.11, green: 0.10, blue: 0.08),
                primaryText: Color(red: 0.96, green: 0.93, blue: 0.86),
                secondaryText: Color(red: 0.70, green: 0.64, blue: 0.52),
                colorScheme: .dark
            )
        case .crt:
            return AppTheme(
                id: .crt,
                accent: Color(red: 0.24, green: 0.86, blue: 0.52),
                background: Color(red: 0.04, green: 0.07, blue: 0.05),
                panel: Color(red: 0.08, green: 0.13, blue: 0.10),
                primaryText: Color(red: 0.86, green: 0.96, blue: 0.90),
                secondaryText: Color(red: 0.50, green: 0.68, blue: 0.58),
                colorScheme: .dark
            )
        case .cyan:
            return AppTheme(
                id: .cyan,
                accent: Color(red: 0.24, green: 0.72, blue: 0.91),
                background: Color(red: 0.04, green: 0.06, blue: 0.09),
                panel: Color(red: 0.08, green: 0.12, blue: 0.17),
                primaryText: Color(red: 0.88, green: 0.93, blue: 0.98),
                secondaryText: Color(red: 0.52, green: 0.62, blue: 0.74),
                colorScheme: .dark
            )
        }
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.resolved(.system)
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

extension View {
    /// Applies branded list chrome when a custom theme is selected.
    /// Avoid `@ViewBuilder` if/else branching here — it can break
    /// `navigationDestination` resolution in surrounding `NavigationStack`s.
    func themedListBackground(_ theme: AppTheme) -> some View {
        let hideScroll = theme.id != .system
        return self
            .scrollContentBackground(hideScroll ? .hidden : .automatic)
            .background(hideScroll ? theme.background : Color.clear)
    }

    func themedListRowBackground(_ theme: AppTheme) -> some View {
        self.listRowBackground(theme.id == .system ? Color(.secondarySystemGroupedBackground) : theme.panel)
    }
}
