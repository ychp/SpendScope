import AppKit
import SwiftUI

enum SpendScopeTheme {
    static let accent = Color(red: 0.42, green: 0.24, blue: 0.96)
    static let accentBlue = Color(red: 0.18, green: 0.52, blue: 0.96)
    static let popoverPrimary = Color(red: 0.12, green: 0.45, blue: 0.94)
    static let popoverSecondary = Color(red: 0.31, green: 0.64, blue: 1.00)
    static let output = Color.orange
    static let reasoning = Color.cyan
    static let glassTint = Color.white.opacity(0.30)
    static let glassTintStrong = Color.white.opacity(0.46)

    // Dashboard-only light palette. System materials provide the blur while
    // translucent tints preserve hierarchy and chart contrast.
    static let dashboardBackground = Color.clear
    static let dashboardSurface = Color.white.opacity(0.42)
    static let dashboardSurfaceStrong = Color(red: 0.972, green: 0.982, blue: 0.998).opacity(0.56)
    static let dashboardTile = Color.white.opacity(0.52)
    static let dashboardControlBackground = Color(red: 0.90, green: 0.94, blue: 0.99).opacity(0.70)
    static let dashboardBorder = Color(red: 0.08, green: 0.25, blue: 0.48).opacity(0.10)
    static let dashboardPrimaryText = Color(red: 0.045, green: 0.065, blue: 0.13)
    static let dashboardMutedText = Color(red: 0.38, green: 0.42, blue: 0.52)
    static let dashboardGrid = Color(red: 0.08, green: 0.25, blue: 0.48).opacity(0.08)
    static let dashboardAccent = Color(red: 0.12, green: 0.43, blue: 0.92)
    static let dashboardAccentSecondary = Color(red: 0.16, green: 0.65, blue: 0.94)

    // Token categories keep their own colors so charts and detail rows remain scannable.
    static let dashboardInput = Color(red: 0.43, green: 0.25, blue: 0.94)
    static let dashboardCachedInput = Color(red: 0.16, green: 0.48, blue: 0.94)
    static let dashboardShadow = Color(red: 0.09, green: 0.12, blue: 0.22).opacity(0.08)
}

struct SpendScopeVisualEffect: NSViewRepresentable {
    enum Style {
        case window
        case popover
    }

    let style: Style

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = style == .window ? .underWindowBackground : .popover
        view.blendingMode = style == .window ? .behindWindow : .withinWindow
        view.state = .active
        view.isEmphasized = true
    }
}

struct DashboardCard: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        content
            .padding(padding)
            .background {
                shape
                    .fill(.thinMaterial)
                    .overlay { shape.fill(SpendScopeTheme.glassTint) }
            }
            .overlay {
                shape.stroke(Color.white.opacity(0.52), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 14, y: 5)
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
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return self
            .padding(padding)
            .background {
                shape
                    .fill(.thinMaterial)
                    .overlay {
                        shape.fill(
                            strong
                                ? SpendScopeTheme.glassTintStrong
                                : SpendScopeTheme.glassTint
                        )
                    }
            }
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.72), SpendScopeTheme.dashboardBorder],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: SpendScopeTheme.dashboardShadow, radius: 12, y: 5)
    }
}
