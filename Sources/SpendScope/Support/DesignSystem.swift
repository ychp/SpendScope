import SwiftUI

enum SpendScopeTheme {
    static let accent = Color(red: 0.42, green: 0.24, blue: 0.96)
    static let accentBlue = Color(red: 0.18, green: 0.52, blue: 0.96)
    static let popoverPrimary = Color(red: 0.12, green: 0.45, blue: 0.94)
    static let popoverSecondary = Color(red: 0.31, green: 0.64, blue: 1.00)
    static let output = Color.orange
    static let reasoning = Color.cyan
    static let cardBackground = Color(nsColor: .controlBackgroundColor).opacity(0.82)

    // Dashboard-only light palette. The main canvas is true white; cool
    // surfaces and restrained violet-blue accents provide the visual depth.
    static let dashboardBackground = Color.white
    static let dashboardSurface = Color.white
    static let dashboardSurfaceStrong = Color(red: 0.975, green: 0.98, blue: 0.995)
    static let dashboardTile = Color.white
    static let dashboardControlBackground = Color(red: 0.95, green: 0.955, blue: 0.975)
    static let dashboardBorder = Color(red: 0.14, green: 0.18, blue: 0.3).opacity(0.11)
    static let dashboardPrimaryText = Color(red: 0.045, green: 0.065, blue: 0.13)
    static let dashboardMutedText = Color(red: 0.38, green: 0.42, blue: 0.52)
    static let dashboardRingTrack = Color(red: 0.9, green: 0.915, blue: 0.95)
    static let dashboardGrid = Color(red: 0.14, green: 0.18, blue: 0.3).opacity(0.09)
    static let dashboardViolet = Color(red: 0.43, green: 0.25, blue: 0.94)
    static let dashboardBlue = Color(red: 0.16, green: 0.48, blue: 0.94)
    static let dashboardShadow = Color(red: 0.09, green: 0.12, blue: 0.22).opacity(0.08)
}

struct DashboardCard: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(SpendScopeTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.08))
            }
    }
}

extension View {
    func dashboardCard(padding: CGFloat = 18) -> some View {
        modifier(DashboardCard(padding: padding))
    }

    func dashboardPanel(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 16,
        strong: Bool = false
    ) -> some View {
        self
            .padding(padding)
            .background(
                strong ? SpendScopeTheme.dashboardSurfaceStrong : SpendScopeTheme.dashboardSurface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SpendScopeTheme.dashboardBorder, lineWidth: 1)
            }
            .shadow(color: SpendScopeTheme.dashboardShadow, radius: 12, y: 5)
    }
}
