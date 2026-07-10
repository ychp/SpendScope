import SwiftUI

enum SpendScopeTheme {
    static let accent = Color(red: 0.42, green: 0.24, blue: 0.96)
    static let accentBlue = Color(red: 0.18, green: 0.52, blue: 0.96)
    static let output = Color.orange
    static let reasoning = Color.cyan
    static let cardBackground = Color(nsColor: .controlBackgroundColor).opacity(0.82)
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
}
