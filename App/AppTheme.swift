import SwiftUI

enum AppThemeID: String, CaseIterable, Identifiable {
    case lime
    case amber
    case cyan
    case magenta
    case random

    var id: String { rawValue }

    /// Themes that 「ランダム」 may pick on launch.
    static let randomPool: [AppThemeID] = [.lime, .amber, .cyan, .magenta]

    var title: String {
        switch self {
        case .lime: return "ライム"
        case .amber: return "アンバー"
        case .cyan: return "シアン"
        case .magenta: return "マゼンタ"
        case .random: return "ランダム"
        }
    }

    /// Accepts legacy stored IDs (`system`, `crt`).
    static func resolveStored(_ raw: String?) -> AppThemeID {
        switch raw {
        case lime.rawValue: return .lime
        case amber.rawValue: return .amber
        case cyan.rawValue: return .cyan
        case magenta.rawValue: return .magenta
        case random.rawValue: return .random
        case "crt": return .lime
        default: return .lime
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
    var colorScheme: ColorScheme

    /// - Parameter randomPickRaw: When `id` is `.random`, the concrete theme
    ///   chosen for this session (`lime` / `amber` / `cyan` / `magenta`).
    static func resolved(_ id: AppThemeID, randomPickRaw: String = AppThemeID.lime.rawValue) -> AppTheme {
        let paletteID: AppThemeID
        if id == .random {
            let pick = AppThemeID.resolveStored(randomPickRaw)
            paletteID = AppThemeID.randomPool.contains(pick) ? pick : .lime
        } else {
            paletteID = id
        }

        let palette = makePalette(paletteID)
        return AppTheme(
            id: id,
            accent: palette.accent,
            background: palette.background,
            panel: palette.panel,
            primaryText: palette.primaryText,
            secondaryText: palette.secondaryText,
            colorScheme: .dark
        )
    }

    private struct Palette {
        var accent: Color
        var background: Color
        var panel: Color
        var primaryText: Color
        var secondaryText: Color
    }

    private static func makePalette(_ id: AppThemeID) -> Palette {
        switch id {
        case .lime, .random:
            // Former CRT green — phosphor / console green.
            return Palette(
                accent: Color(red: 0.24, green: 0.86, blue: 0.52),
                background: Color(red: 0.04, green: 0.07, blue: 0.05),
                panel: Color(red: 0.08, green: 0.13, blue: 0.10),
                primaryText: Color(red: 0.86, green: 0.96, blue: 0.90),
                secondaryText: Color(red: 0.50, green: 0.68, blue: 0.58)
            )
        case .amber:
            return Palette(
                accent: Color(red: 0.91, green: 0.66, blue: 0.22),
                background: Color(red: 0.06, green: 0.05, blue: 0.05),
                panel: Color(red: 0.11, green: 0.10, blue: 0.08),
                primaryText: Color(red: 0.96, green: 0.93, blue: 0.86),
                secondaryText: Color(red: 0.70, green: 0.64, blue: 0.52)
            )
        case .cyan:
            return Palette(
                accent: Color(red: 0.24, green: 0.72, blue: 0.91),
                background: Color(red: 0.04, green: 0.06, blue: 0.09),
                panel: Color(red: 0.08, green: 0.12, blue: 0.17),
                primaryText: Color(red: 0.88, green: 0.93, blue: 0.98),
                secondaryText: Color(red: 0.52, green: 0.62, blue: 0.74)
            )
        case .magenta:
            return Palette(
                accent: Color(red: 0.92, green: 0.28, blue: 0.72),
                background: Color(red: 0.07, green: 0.04, blue: 0.08),
                panel: Color(red: 0.14, green: 0.08, blue: 0.16),
                primaryText: Color(red: 0.98, green: 0.90, blue: 0.96),
                secondaryText: Color(red: 0.72, green: 0.55, blue: 0.70)
            )
        }
    }

    static func rollRandomPick() -> AppThemeID {
        AppThemeID.randomPool.randomElement() ?? .lime
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.resolved(.lime)
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

extension View {
    /// Applies branded list chrome for custom theme colors.
    /// Avoid `@ViewBuilder` if/else branching here — it can break
    /// `navigationDestination` resolution in surrounding `NavigationStack`s.
    func themedListBackground(_ theme: AppTheme) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(theme.background)
    }

    func themedListRowBackground(_ theme: AppTheme) -> some View {
        self.listRowBackground(theme.panel)
    }
}
