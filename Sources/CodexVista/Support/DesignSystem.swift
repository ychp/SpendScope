import AppKit
import SwiftUI

enum CodexVistaTheme {
    // Light mode is crisp and cool; dark mode shifts to brighter spectral
    // accents on deep navy surfaces for a restrained technology aesthetic.
    static let accent = adaptiveColor(
        light: nsColor(0.31, 0.27, 0.90),
        dark: nsColor(0.51, 0.55, 0.98)
    )
    static let accentBlue = adaptiveColor(
        light: nsColor(0.03, 0.57, 0.70),
        dark: nsColor(0.13, 0.83, 0.93)
    )
    static let popoverPrimary = accent
    static let popoverSecondary = accentBlue
    static let output = adaptiveColor(
        light: nsColor(0.92, 0.35, 0.08),
        dark: nsColor(0.98, 0.57, 0.24)
    )
    static let reasoning = adaptiveColor(
        light: nsColor(0.03, 0.53, 0.52),
        dark: nsColor(0.18, 0.83, 0.75)
    )

    static let glassTint = adaptiveColor(
        light: nsColor(1.00, 1.00, 1.00, alpha: 0.34),
        dark: nsColor(0.04, 0.08, 0.16, alpha: 0.26)
    )
    static let glassTintStrong = adaptiveColor(
        light: nsColor(1.00, 1.00, 1.00, alpha: 0.54),
        dark: nsColor(0.05, 0.10, 0.20, alpha: 0.46)
    )
    static let glassHighlight = adaptiveColor(
        light: nsColor(1.00, 1.00, 1.00, alpha: 0.82),
        dark: nsColor(0.72, 0.91, 1.00, alpha: 0.44)
    )
    static let glassEdge = adaptiveColor(
        light: nsColor(0.53, 0.64, 0.82, alpha: 0.22),
        dark: nsColor(0.18, 0.76, 0.92, alpha: 0.34)
    )
    static let dashboardBackground = adaptiveColor(
        light: nsColor(0.96, 0.98, 1.00, alpha: 0.78),
        dark: nsColor(0.015, 0.028, 0.075, alpha: 0.94)
    )
    static let dashboardSurface = adaptiveColor(
        light: nsColor(1.00, 1.00, 1.00, alpha: 0.66),
        dark: nsColor(0.035, 0.065, 0.14, alpha: 0.70)
    )
    static let dashboardSurfaceOpaque = adaptiveColor(
        light: nsColor(0.975, 0.988, 1.00),
        dark: nsColor(0.025, 0.045, 0.095)
    )
    static let dashboardSurfaceStrong = adaptiveColor(
        light: nsColor(1.00, 1.00, 1.00, alpha: 0.84),
        dark: nsColor(0.045, 0.085, 0.17, alpha: 0.84)
    )
    static let dashboardTile = adaptiveColor(
        light: nsColor(1.00, 1.00, 1.00, alpha: 0.82),
        dark: nsColor(0.055, 0.095, 0.18, alpha: 0.78)
    )
    static let dashboardControlBackground = adaptiveColor(
        light: nsColor(0.88, 0.92, 0.98, alpha: 0.72),
        dark: nsColor(0.09, 0.14, 0.24, alpha: 0.82)
    )
    static let dashboardBorder = adaptiveColor(
        light: nsColor(0.55, 0.63, 0.74, alpha: 0.28),
        dark: nsColor(0.40, 0.53, 0.72, alpha: 0.42)
    )
    static let dashboardPrimaryText = adaptiveColor(
        light: nsColor(0.055, 0.075, 0.13),
        dark: nsColor(0.93, 0.96, 1.00)
    )
    static let dashboardMutedText = adaptiveColor(
        light: nsColor(0.34, 0.39, 0.48),
        dark: nsColor(0.59, 0.68, 0.80)
    )
    static let dashboardGrid = adaptiveColor(
        light: nsColor(0.31, 0.40, 0.53, alpha: 0.14),
        dark: nsColor(0.31, 0.72, 0.86, alpha: 0.16)
    )
    static let dashboardAccent = accent
    static let dashboardAccentSecondary = accentBlue

    // Token categories keep their own colors so charts and detail rows remain scannable.
    static let dashboardInput = accent
    static let dashboardCachedInput = adaptiveColor(
        light: nsColor(0.15, 0.48, 0.92),
        dark: nsColor(0.23, 0.65, 1.00)
    )
    static let dashboardShadow = adaptiveColor(
        light: nsColor(0.03, 0.07, 0.15, alpha: 0.11),
        dark: nsColor(0.00, 0.00, 0.02, alpha: 0.46)
    )
    static let dashboardGlow = adaptiveColor(
        light: nsColor(0.31, 0.27, 0.90, alpha: 0.02),
        dark: nsColor(0.13, 0.83, 0.93, alpha: 0.12)
    )

    static let brandGradient = LinearGradient(
        colors: [accent, accentBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? dark
                : light
        })
    }

    private static func nsColor(
        _ red: CGFloat,
        _ green: CGFloat,
        _ blue: CGFloat,
        alpha: CGFloat = 1
    ) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
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

struct CodexVistaGlassSurface: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat
    let emphasis: CodexVistaGlassEmphasis
    let shadowOpacity: Double
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *) {
            content
                .padding(padding)
                .background {
                    shape
                        .fill(nativeFrostTint)
                        .overlay { glassReflection(shape: shape) }
                }
                .glassEffect(
                    .regular.tint(nativeGlassTint),
                    in: shape
                )
                .overlay { glassEdgeOverlay(shape: shape) }
                .shadow(color: CodexVistaTheme.dashboardGlow, radius: 20)
                .shadow(
                    color: CodexVistaTheme.dashboardShadow.opacity(shadowOpacity),
                    radius: 12,
                    y: 4
                )
        } else {
            content
                .padding(padding)
                .background {
                    shape
                        .fill(emphasis == .strong ? Material.thick : Material.regular)
                        .overlay {
                            shape.fill(
                                emphasis == .strong
                                    ? CodexVistaTheme.glassTintStrong
                                    : CodexVistaTheme.glassTint
                            )
                        }
                        .overlay { glassReflection(shape: shape) }
                }
                .overlay { glassEdgeOverlay(shape: shape) }
                .shadow(color: CodexVistaTheme.dashboardGlow, radius: 20)
                .shadow(
                    color: CodexVistaTheme.dashboardShadow.opacity(shadowOpacity),
                    radius: 12,
                    y: 4
                )
        }
    }

    private var nativeGlassTint: Color? {
        if emphasis == .strong {
            return CodexVistaTheme.accent.opacity(colorScheme == .dark ? 0.075 : 0.04)
        }
        return Color.white.opacity(colorScheme == .dark ? 0.025 : 0.07)
    }

    private var nativeFrostTint: Color {
        if emphasis == .strong {
            return CodexVistaTheme.glassTintStrong.opacity(colorScheme == .dark ? 0.34 : 0.28)
        }
        return CodexVistaTheme.glassTint.opacity(colorScheme == .dark ? 0.26 : 0.22)
    }

    private func glassReflection(shape: RoundedRectangle) -> some View {
        shape
            .fill(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(
                            color: CodexVistaTheme.glassHighlight.opacity(
                                colorScheme == .dark ? 0.22 : 0.36
                            ),
                            location: 0
                        ),
                        .init(
                            color: CodexVistaTheme.glassTint.opacity(
                                colorScheme == .dark ? 0.12 : 0.18
                            ),
                            location: 0.34
                        ),
                        .init(color: Color.clear, location: 0.68),
                        .init(
                            color: CodexVistaTheme.glassEdge.opacity(0.12),
                            location: 1
                        )
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .allowsHitTesting(false)
    }

    private func glassEdgeOverlay(shape: RoundedRectangle) -> some View {
        ZStack {
            shape.stroke(CodexVistaTheme.dashboardBorder, lineWidth: 1)
            shape.stroke(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: CodexVistaTheme.glassHighlight, location: 0),
                        .init(color: Color.clear, location: 0.46),
                        .init(color: CodexVistaTheme.glassEdge, location: 1)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
        }
        .allowsHitTesting(false)
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
