import AppKit
import SwiftUI

struct CodexVistaPalette {
    let background: UInt32
    let surface: UInt32
    let raised: UInt32
    let control: UInt32
    let border: UInt32
    let primary: UInt32
    let muted: UInt32
    let accent: UInt32
    let secondary: UInt32
    let cached: UInt32
    let output: UInt32
    let reasoning: UInt32
    let grid: UInt32
    let selected: UInt32
    let selectedText: UInt32
    let heatText: UInt32
    let action: UInt32

    static func resolve(skin: AppSkinPreference, dark: Bool) -> Self {
        switch (skin, dark) {
        case (.standard, false): standardLight
        case (.standard, true): standardDark
        case (.ink, _): inkLight
        }
    }

    private static let standardLight = Self(
        background: 0xE9EDF0,
        surface: 0xF2F5F7,
        raised: 0xFFFFFF,
        control: 0xE2E8ED,
        border: 0xCAD3DB,
        primary: 0x263440,
        muted: 0x566876,
        accent: 0x2147A7,
        secondary: 0x2A657E,
        cached: 0x6A7297,
        output: 0xA85E26,
        reasoning: 0x2D756A,
        grid: 0xD8E0E7,
        selected: 0xFFFFFF,
        selectedText: 0x2147A7,
        heatText: 0xFFFFFF,
        action: 0x2147A7
    )

    private static let standardDark = Self(
        background: 0x19212A,
        surface: 0x202B36,
        raised: 0x283542,
        control: 0x303E4C,
        border: 0x425264,
        primary: 0xEDF3F8,
        muted: 0xACBDCC,
        accent: 0x9BBCFF,
        secondary: 0x8AC6DA,
        cached: 0xBBBDDF,
        output: 0xE7B084,
        reasoning: 0x96CCBE,
        grid: 0x354454,
        selected: 0x405268,
        selectedText: 0xF0F5FF,
        heatText: 0x182430,
        action: 0x274FAE
    )

    private static let inkLight = Self(
        background: 0xECEDE8,
        surface: 0xF2F3EE,
        raised: 0xFAFAF5,
        control: 0xE4E7E1,
        border: 0xD2D7D1,
        primary: 0x303B40,
        muted: 0x5B686A,
        accent: 0x3B4850,
        secondary: 0x587777,
        cached: 0x768C8A,
        output: 0xA33F3B,
        reasoning: 0x7C714C,
        grid: 0xD8DDD7,
        selected: 0xFAFAF5,
        selectedText: 0xA33F3B,
        heatText: 0xFFFFFF,
        action: 0x3B4850
    )
}

enum CodexVistaTheme {
    static var accent: Color { color(\.accent) }
    static var accentBlue: Color { color(\.secondary) }
    static var popoverPrimary: Color { color(\.accent) }
    static var popoverSecondary: Color { color(\.secondary) }
    static var output: Color { color(\.output) }
    static var reasoning: Color { color(\.reasoning) }
    static var dashboardBackground: Color { color(\.background) }
    static var dashboardSurface: Color { color(\.surface) }
    static var dashboardSurfaceOpaque: Color { color(\.surface) }
    static var dashboardSurfaceStrong: Color { color(\.raised) }
    static var dashboardTile: Color { color(\.raised) }
    static var dashboardControlBackground: Color { color(\.control) }
    static var dashboardBorder: Color { color(\.border) }
    static var dashboardPrimaryText: Color { color(\.primary) }
    static var dashboardMutedText: Color { color(\.muted) }
    static var dashboardGrid: Color { color(\.grid) }
    static var dashboardAccent: Color { color(\.accent) }
    static var dashboardAccentSecondary: Color { color(\.secondary) }
    static var dashboardInput: Color { color(\.accent) }
    static var dashboardCachedInput: Color { color(\.cached) }
    static var selectionSurface: Color { color(\.selected) }
    static var selectionText: Color { color(\.selectedText) }
    static var heatmapText: Color { color(\.heatText) }
    static var cinnabar: Color { color(\.selectedText) }
    static var dashboardShadow: Color { Color.black.opacity(isInk ? 0.025 : 0.06) }
    static var isInk: Bool { AppSkinPreference.load() == .ink }

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [color(\.action), color(\.action)], startPoint: .top, endPoint: .bottom)
    }

    static func headingFont(size: CGFloat) -> Font {
        isInk ? .custom("Songti SC", size: size).weight(.semibold) : .system(size: size, weight: .semibold)
    }

    static func metricFont(size: CGFloat) -> Font {
        isInk ? .system(size: size, weight: .semibold, design: .serif)
            : .custom("DINAlternate-Bold", size: size)
    }

    static func cornerRadius(_ radius: CGFloat) -> CGFloat {
        radius * (isInk ? 0.5 : 0.72)
    }

    static func swatch(_ hex: UInt32) -> Color { Color(nsColor: nsColor(hex)) }

    private static func color(_ key: KeyPath<CodexVistaPalette, UInt32>) -> Color {
        let skin = AppSkinPreference.load()
        let light = CodexVistaPalette.resolve(skin: skin, dark: false)[keyPath: key]
        let dark = CodexVistaPalette.resolve(skin: skin, dark: true)[keyPath: key]
        return Color(nsColor: NSColor(name: nil) { appearance in
            nsColor(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
    }

    private static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

struct CodexVistaBackdrop: View {
    var body: some View {
        CodexVistaTheme.dashboardBackground
            .overlay {
                if CodexVistaTheme.isInk { CodexVistaPaperGrain() }
            }
            .ignoresSafeArea()
    }
}

/// Deterministic fibers, drawn once per update; no images, timers, or random flicker.
struct CodexVistaPaperGrain: View {
    var body: some View {
        Canvas { context, size in
            var fibers = Path()
            let count = min(1_200, Int(size.width * size.height / 650))
            for index in 0..<max(0, count) {
                let x = CGFloat((index * 137 + 29) % 1009) / 1009 * size.width
                let y = CGFloat((index * 193 + 71) % 1013) / 1013 * size.height
                fibers.move(to: CGPoint(x: x, y: y))
                fibers.addLine(to: CGPoint(x: x + CGFloat(index % 4 + 1), y: y + 0.6))
            }
            context.stroke(fibers, with: .color(CodexVistaTheme.dashboardAccent.opacity(0.032)), lineWidth: 0.45)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}


/// A quiet landscape in the quota panel's lower margin, independent of usage data.
struct CodexVistaInkPainting: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let ink = CodexVistaTheme.dashboardAccent
            let strength = colorScheme == .dark ? 0.78 : 1.0
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: x * size.width, y: y * size.height)
            }
            // Unequal ridges and translucent washes leave a misty river between banks.
            let ridges: [[CGPoint]] = [
                [point(0, 0.45), point(0.08, 0.34), point(0.13, 0.43), point(0.24, 0.12), point(0.29, 0.23), point(0.34, 0.38), point(0.4, 0.34), point(0.52, 0.68)],
                [point(0.43, 0.76), point(0.57, 0.54), point(0.63, 0.57), point(0.72, 0.3), point(0.77, 0.4), point(0.83, 0.23), point(0.89, 0.42), point(1, 0.47)],
                [point(0, 0.52), point(0.06, 0.43), point(0.12, 0.54), point(0.18, 0.3), point(0.24, 0.48), point(0.29, 0.53), point(0.38, 0.82)]
            ]
            for (layer, ridge) in ridges.enumerated() {
                guard let first = ridge.first, let last = ridge.last else { continue }
                var mountain = Path()
                mountain.move(to: first)
                for index in 1..<ridge.count {
                    let previous = ridge[index - 1]
                    let current = ridge[index]
                    let middle = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
                    mountain.addQuadCurve(to: middle, control: previous)
                }
                mountain.addLine(to: last)
                mountain.addLine(to: CGPoint(x: last.x, y: size.height * 0.94))
                mountain.addLine(to: CGPoint(x: first.x, y: size.height * 0.94))
                mountain.closeSubpath()
                context.fill(mountain, with: .linearGradient(
                    Gradient(colors: [ink.opacity((layer == 2 ? 0.23 : 0.13) * strength), ink.opacity(0.005)]),
                    startPoint: point(0, 0.2), endPoint: point(0, 0.96)
                ))
                var textured = context
                textured.clip(to: mountain)
                for stroke in 0..<24 {
                    let x = Double((stroke * 37 + layer * 19) % 101) / 100
                    let y = Double((stroke * 23) % 67) / 100 + 0.2
                    var fiber = Path()
                    fiber.move(to: point(x, y))
                    fiber.addQuadCurve(to: point(x - 0.025, y + 0.15), control: point(x + 0.012, y + 0.05))
                    textured.stroke(fiber, with: .color(ink.opacity(0.035 * strength)), lineWidth: 0.6)
                }
            }

            // A small skiff and a single oar give the river a human scale.
            var boat = Path()
            boat.move(to: point(0.51, 0.8))
            boat.addQuadCurve(to: point(0.65, 0.78), control: point(0.59, 0.91))
            boat.addQuadCurve(to: point(0.51, 0.8), control: point(0.58, 0.83))
            context.fill(boat, with: .color(ink.opacity(0.52 * strength)))
            var figure = Path()
            figure.move(to: point(0.58, 0.79))
            figure.addQuadCurve(to: point(0.572, 0.67), control: point(0.56, 0.73))
            figure.move(to: point(0.57, 0.73))
            figure.addLine(to: point(0.6, 0.76))
            figure.move(to: point(0.596, 0.72))
            figure.addLine(to: point(0.66, 0.89))
            context.stroke(figure, with: .color(ink.opacity(0.55 * strength)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: size.width * 0.567, y: size.height * 0.64, width: 2.7, height: 2.7)), with: .color(ink.opacity(0.5 * strength)))

            var ripples = Path()
            for (x, y, width) in [(0.46, 0.91, 0.16), (0.56, 0.95, 0.14), (0.74, 0.86, 0.12)] {
                ripples.move(to: point(x, y))
                ripples.addQuadCurve(to: point(x + width, y), control: point(x + width / 2, y + 0.012))
            }
            context.stroke(ripples, with: .color(ink.opacity(0.16 * strength)), lineWidth: 0.5)

            // Dry-brush reeds anchor the near shore without touching the metrics.
            for index in 0..<6 {
                let root = 0.91 + Double(index % 3) * 0.02
                let tip = root - 0.045 + Double(index) * 0.009
                let height = 0.17 + Double(index % 4) * 0.055
                var reed = Path()
                reed.move(to: point(root, 1))
                reed.addQuadCurve(to: point(tip, 1 - height), control: point(root + 0.01, 0.84))
                context.stroke(reed, with: .color(ink.opacity(0.32 * strength)), lineWidth: 0.65)
                var seed = Path()
                seed.move(to: point(tip, 1 - height))
                seed.addLine(to: point(tip - 0.005, 0.95 - height))
                context.stroke(seed, with: .color(ink.opacity(0.28 * strength)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct CodexVistaDialTicks: View {
    let remaining: Double

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let fraction = remaining.isFinite ? min(1, max(0, remaining)) : 0
            for index in 0..<20 {
                let angle = Double(index) / 20 * .pi * 2 - .pi / 2
                let length: CGFloat = index.isMultiple(of: 5) ? 6 : 3
                var tick = Path()
                tick.move(to: CGPoint(x: radius + cos(angle) * (radius - length), y: radius + sin(angle) * (radius - length)))
                tick.addLine(to: CGPoint(x: radius + cos(angle) * radius, y: radius + sin(angle) * radius))
                context.stroke(tick, with: .color(Double(index) / 20 < fraction
                    ? CodexVistaTheme.dashboardAccent.opacity(0.7)
                    : CodexVistaTheme.dashboardMutedText.opacity(0.3)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct CodexVistaInkQuota: View {
    let quota: QuotaSnapshot
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(quota.compactTitle)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                Spacer(minLength: 4)
                Text("\(quota.remainingPercent)%")
                    .font(CodexVistaTheme.metricFont(size: compact ? 25 : 40))
                    .monospacedDigit()
                Text("剩余")
                    .font(CodexVistaTheme.headingFont(size: 12))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }

            Canvas { context, size in
                let fraction = quota.remaining.isFinite ? min(1, max(0, quota.remaining)) : 0
                context.fill(Path(CGRect(x: 0, y: 5, width: size.width, height: 5)), with: .color(CodexVistaTheme.dashboardControlBackground))
                let width = size.width * fraction
                if width > 0 {
                    var brush = Path()
                    brush.move(to: CGPoint(x: 0, y: 2))
                    for step in 0...30 {
                        brush.addLine(to: CGPoint(x: width * Double(step) / 30, y: 2 + sin(Double(step) * 2) * 0.6))
                    }
                    for step in (0...30).reversed() {
                        brush.addLine(to: CGPoint(x: width * Double(step) / 30, y: 12 + sin(Double(step) * 3) * 0.8))
                    }
                    brush.closeSubpath()
                    context.fill(brush, with: .color(CodexVistaTheme.dashboardAccent))
                }
                for index in 0...4 {
                    let x = 0.5 + (size.width - 1) * Double(index) / 4
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: 18))
                    tick.addLine(to: CGPoint(x: x, y: 21))
                    context.stroke(tick, with: .color(CodexVistaTheme.dashboardMutedText.opacity(0.55)), lineWidth: 0.75)
                }
            }
            .frame(height: 22)
            HStack {
                Text("0%")
                Spacer()
                Text("100%")
            }
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(CodexVistaTheme.dashboardMutedText)
        }
        .frame(width: 210)
        .padding(.vertical, compact ? 2 : 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quota.remainingLabel)
    }
}

struct CodexVistaSkinPreview: View {
    let skin: AppSkinPreference
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    var body: some View {
        let palette = CodexVistaPalette.resolve(skin: skin, dark: colorScheme == .dark)
        let radius: CGFloat = skin == .ink ? 6 : 9
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 12) {
                    ZStack {
                        if skin == .ink {
                            Text("墨")
                                .font(.custom("Songti SC", size: 25))
                                .foregroundStyle(CodexVistaTheme.swatch(palette.selectedText))
                        } else {
                            Circle().stroke(CodexVistaTheme.swatch(palette.control), lineWidth: 4)
                            Circle().trim(from: 0, to: 0.7)
                                .stroke(CodexVistaTheme.swatch(palette.accent), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                    }
                    .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(CodexVistaTheme.swatch(palette.accent).opacity(0.65))
                            .frame(width: 72, height: 5)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(CodexVistaTheme.swatch(palette.border))
                            .frame(width: 100, height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(CodexVistaTheme.swatch(palette.border))
                            .frame(width: 86, height: 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(CodexVistaTheme.swatch(palette.raised), in: RoundedRectangle(cornerRadius: radius))

                HStack {
                    Text(skin.title)
                        .font(skin == .ink ? .custom("Songti SC", size: 14).weight(.semibold) : .system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(CodexVistaTheme.swatch(isSelected ? palette.selectedText : palette.muted))
                }
                Text(skin == .ink ? "雾白纸面 · 石墨与朱砂" : "精密刻度 · 铝灰与钴蓝")
                    .font(.system(size: 10))
                    .foregroundStyle(CodexVistaTheme.swatch(palette.muted))
            }
            .padding(10)
            .foregroundStyle(CodexVistaTheme.swatch(palette.primary))
            .background(CodexVistaTheme.swatch(palette.background), in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(CodexVistaTheme.swatch(isFocused || isSelected ? palette.selectedText : palette.border), lineWidth: isFocused ? 2 : 1)
            }
        }
        .buttonStyle(CodexVistaControlStyle())
        .focused($isFocused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(skin.title)皮肤")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct CodexVistaInkSeal: View {
    var body: some View {
        Text("墨")
            .font(.custom("Songti SC", size: 15).weight(.bold))
            .foregroundStyle(CodexVistaTheme.cinnabar)
            .frame(width: 23, height: 26)
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(CodexVistaTheme.cinnabar.opacity(0.8), lineWidth: 1)
                    .padding(1)
            }
            .rotationEffect(.degrees(-3))
            .accessibilityHidden(true)
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
    @AppStorage(AppPreferenceKeys.skin)
    private var skinRaw = AppSkinPreference.standard.rawValue
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            // Recreate local presentation on a skin change so all static palette users,
            // including native popovers, pick up the new palette together.
            .id(AppSkinPreference.resolved(from: skinRaw))
            .preferredColorScheme(
                AppSkinPreference.resolved(from: skinRaw).effectiveColorScheme(
                    for: AppColorSchemePreference.resolved(from: colorSchemeRaw)
                )
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
        let shape = RoundedRectangle(cornerRadius: CodexVistaTheme.cornerRadius(cornerRadius), style: .continuous)
        content
            .padding(padding)
            .background {
                shape.fill(
                    emphasis == .strong
                        ? CodexVistaTheme.dashboardSurfaceStrong
                        : CodexVistaTheme.dashboardSurface
                )
                .overlay {
                    if CodexVistaTheme.isInk {
                        CodexVistaPaperGrain().clipShape(shape)
                    }
                }
            }
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
