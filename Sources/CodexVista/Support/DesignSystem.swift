import AppKit
import SwiftUI

enum CodexVistaTheme {
    // Paper / Graphite: neutral surfaces carry structure; color carries meaning.
    static let accent = adaptiveColor(light: 0x345AC6, dark: 0x91ACFF)
    static let accentBlue = adaptiveColor(light: 0x336C86, dark: 0x86B6CB)
    static let popoverPrimary = accent
    static let popoverSecondary = accentBlue
    static let output = adaptiveColor(light: 0xAC5726, dark: 0xE7AB7C)
    static let reasoning = adaptiveColor(light: 0x287866, dark: 0x7CC4AC)

    static let dashboardBackground = adaptiveColor(light: 0xF3F2EF, dark: 0x191A1D)
    static let dashboardSurface = adaptiveColor(light: 0xFAFAF8, dark: 0x222327)
    static let dashboardSurfaceOpaque = dashboardSurface
    static let dashboardSurfaceStrong = adaptiveColor(light: 0xFFFFFF, dark: 0x292A2F)
    static let dashboardTile = dashboardSurfaceStrong
    static let dashboardControlBackground = adaptiveColor(light: 0xECEDEB, dark: 0x303136)
    static let dashboardBorder = adaptiveColor(light: 0xDFE0DC, dark: 0x3B3D43)
    static let dashboardPrimaryText = adaptiveColor(light: 0x24262B, dark: 0xEEEFF2)
    static let dashboardMutedText = adaptiveColor(light: 0x62666F, dark: 0xABAEB8)
    static let dashboardGrid = adaptiveColor(light: 0xE3E5E2, dark: 0x36383E)
    static let dashboardAccent = accent
    static let dashboardAccentSecondary = accentBlue
    static let dashboardInput = accent
    static let dashboardCachedInput = adaptiveColor(light: 0x6873A6, dark: 0xADAEDB)
    static let dashboardShadow = adaptiveColor(light: 0x252A35, dark: 0x000000)
        .opacity(0.07)
    static let selectionSurface = adaptiveColor(light: 0xFFFFFF, dark: 0x44464F)
    static let selectionText = dashboardPrimaryText
    static let heatmapText = adaptiveColor(light: 0xFFFFFF, dark: 0x191A1D)

    // Filled primary actions need white text in both appearances.
    static let brandGradient = LinearGradient(
        colors: [Color(nsColor: nsColor(0x345AC6)), Color(nsColor: nsColor(0x3E65CE))],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static func adaptiveColor(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            nsColor(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
    }

    private static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct CodexVistaBackdrop: View {
    var body: some View {
        CodexVistaTheme.dashboardBackground.ignoresSafeArea()
    }
}

/// Immediate press feedback for frequently used controls, including keyboard input.
/// No implicit animation delays selection or ignores the reduced-motion preference.
struct CodexVistaControlStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
    }
}

struct CodexVistaAppearanceContainer<Content: View>: View {
    @AppStorage(AppPreferenceKeys.colorScheme)
    private var colorSchemeRaw = AppColorSchemePreference.system.rawValue
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .preferredColorScheme(
                AppColorSchemePreference.resolved(from: colorSchemeRaw).colorScheme
            )
            .tint(CodexVistaTheme.accent)
    }
}

struct CodexVistaVisualEffect: NSViewRepresentable {
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

enum CodexVistaGlassEmphasis {
    case standard
    case strong
}

struct CodexVistaGlassGroup<Content: View>: View {
    let spacing: CGFloat?
    private let content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

// Keep the shared surface API so popovers, settings, and details use the same palette.
// Data surfaces are opaque: desktop wallpaper must not alter chart/text contrast.
struct CodexVistaGlassSurface: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat
    let emphasis: CodexVistaGlassEmphasis
    let shadowOpacity: Double

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .background(
                emphasis == .strong
                    ? CodexVistaTheme.dashboardSurfaceStrong
                    : CodexVistaTheme.dashboardSurface,
                in: shape
            )
            .overlay {
                shape.strokeBorder(CodexVistaTheme.dashboardBorder, lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: CodexVistaTheme.dashboardShadow.opacity(shadowOpacity),
                radius: 8,
                y: 2
            )
    }
}

extension View {
    func dashboardCard(padding: CGFloat = 18) -> some View {
        modifier(CodexVistaGlassSurface(
            padding: padding,
            cornerRadius: 16,
            emphasis: .standard,
            shadowOpacity: 0.62
        ))
    }

    func dashboardPanel(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 16,
        strong: Bool = false
    ) -> some View {
        modifier(CodexVistaGlassSurface(
            padding: padding,
            cornerRadius: cornerRadius,
            emphasis: strong ? .strong : .standard,
            shadowOpacity: 0.72
        ))
    }

    func codexVistaGlassSurface(
        padding: CGFloat = 0,
        cornerRadius: CGFloat = 12,
        strong: Bool = false,
        shadowOpacity: Double = 0.58
    ) -> some View {
        modifier(CodexVistaGlassSurface(
            padding: padding,
            cornerRadius: cornerRadius,
            emphasis: strong ? .strong : .standard,
            shadowOpacity: shadowOpacity
        ))
    }
}
