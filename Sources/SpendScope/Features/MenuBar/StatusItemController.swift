import AppKit
import Observation
import SwiftUI

enum StatusItemQuotaPaletteRole: Equatable {
    case fiveHour
    case weekly
}

enum StatusItemLayoutMetrics {
    static let imageHeight: CGFloat = 22
    static let itemOuterPadding: CGFloat = 8
    static let iconRect = NSRect(x: 2, y: 2, width: 18, height: 18)
    static let leadingContentWidth: CGFloat = 22
    static let classicQuotaUnitWidth: CGFloat = 25
    static let richImageWidth: CGFloat = 126
    static let emptyImageWidth: CGFloat = 24
}

struct StatusItemMetricPresentation: Equatable, Identifiable {
    let id: String
    let label: String
    let value: String
    let fraction: CGFloat
    let resetText: String?
    let paletteRole: StatusItemQuotaPaletteRole
}

struct StatusItemPresentation: Equatable {
    let displayMode: StatusItemDisplayMode
    let metrics: [StatusItemMetricPresentation]
    let imageSize: NSSize
    let itemLength: CGFloat
    let label: String

    init(
        snapshot: DashboardSnapshot?,
        configuration: MenuBarLabelConfiguration,
        displayMode: StatusItemDisplayMode,
        now: Date = Date()
    ) {
        self.displayMode = displayMode

        let availableQuotas = snapshot?.visibleQuotas ?? []
        var selectedQuotas = availableQuotas.filter { quota in
            switch quota.id {
            case "5h": configuration.showsFiveHour
            case "7d": configuration.showsWeekly
            default: false
            }
        }
        if selectedQuotas.isEmpty, let fallback = availableQuotas.first {
            selectedQuotas = [fallback]
        }

        metrics = selectedQuotas.map { quota in
            let fraction: Double
            switch configuration.quotaDisplay {
            case .used: fraction = 1 - quota.remaining
            case .remaining: fraction = quota.remaining
            }
            let normalized = min(max(fraction, 0), 1)
            return StatusItemMetricPresentation(
                id: quota.id,
                label: quota.compactTitle,
                value: "\(Int((normalized * 100).rounded()))%",
                fraction: CGFloat(normalized),
                resetText: quota.resetCountdown(now: now),
                paletteRole: quota.id == "7d" ? .weekly : .fiveHour
            )
        }

        let imageWidth: CGFloat
        switch displayMode {
        case .rich:
            imageWidth = metrics.isEmpty
                ? StatusItemLayoutMetrics.emptyImageWidth
                : StatusItemLayoutMetrics.richImageWidth
        case .classic:
            imageWidth = StatusItemLayoutMetrics.leadingContentWidth
                + CGFloat(metrics.count) * StatusItemLayoutMetrics.classicQuotaUnitWidth
                + 2
        }
        imageSize = NSSize(width: imageWidth, height: StatusItemLayoutMetrics.imageHeight)
        itemLength = imageWidth + StatusItemLayoutMetrics.itemOuterPadding
        label = metrics.isEmpty
            ? "SpendScope"
            : metrics.map { metric in
                [metric.label, metric.value, metric.resetText]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }.joined(separator: " · ")
    }
}

struct StatusItemRenderer {
    private struct Palette {
        let start: NSColor
        let end: NSColor
        let track: NSColor
    }

    func render(_ presentation: StatusItemPresentation, appearance: NSAppearance) -> NSImage {
        var renderedImage: NSImage?
        appearance.performAsCurrentDrawingAppearance {
            renderedImage = draw(presentation)
        }
        return renderedImage ?? draw(presentation)
    }

    private func draw(_ presentation: StatusItemPresentation) -> NSImage {
        let image = NSImage(size: presentation.imageSize)
        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = false
        }

        NSGraphicsContext.current?.imageInterpolation = .high
        drawIcon(in: StatusItemLayoutMetrics.iconRect)

        switch presentation.displayMode {
        case .rich:
            drawRich(presentation.metrics)
        case .classic:
            drawClassic(presentation.metrics)
        }
        return image
    }

    private func drawRich(_ metrics: [StatusItemMetricPresentation]) {
        guard !metrics.isEmpty else { return }

        if metrics.count >= 2 {
            drawRichRow(metrics[0], y: 11.2)
            drawRichRow(metrics[1], y: 1.1)
        } else if let metric = metrics.first {
            drawRichRow(metric, y: 6.2)
        }
    }

    private func drawRichRow(_ metric: StatusItemMetricPresentation, y: CGFloat) {
        drawText(
            metric.label,
            in: NSRect(x: 23, y: y - 1, width: 18, height: 10),
            font: .monospacedDigitSystemFont(ofSize: 8.2, weight: .semibold),
            color: NSColor.labelColor,
            alignment: .right
        )
        drawLinearProgress(
            in: NSRect(x: 45, y: y + 2.1, width: 23, height: 4),
            fraction: metric.fraction,
            paletteRole: metric.paletteRole
        )
        drawText(
            metric.value,
            in: NSRect(x: 70, y: y - 1, width: 25, height: 10),
            font: .monospacedDigitSystemFont(ofSize: 8.4, weight: .bold),
            color: NSColor.labelColor,
            alignment: .right
        )
        drawText(
            metric.resetText ?? "--",
            in: NSRect(x: 98, y: y - 1, width: 26, height: 10),
            font: .monospacedDigitSystemFont(ofSize: 8.0, weight: .medium),
            color: NSColor.secondaryLabelColor,
            alignment: .center
        )
    }

    private func drawClassic(_ metrics: [StatusItemMetricPresentation]) {
        var x = StatusItemLayoutMetrics.leadingContentWidth
        for metric in metrics {
            let ringRect = NSRect(x: x + 2, y: 1, width: 20, height: 20)
            drawCircularProgress(
                in: ringRect,
                fraction: metric.fraction,
                paletteRole: metric.paletteRole,
                lineWidth: 1.6
            )
            drawText(
                metric.label,
                in: NSRect(x: x + 3, y: 11.1, width: 18, height: 7),
                font: .monospacedDigitSystemFont(ofSize: 5.7, weight: .semibold),
                color: NSColor.secondaryLabelColor,
                alignment: .center
            )
            drawText(
                metric.value,
                in: NSRect(x: x + 2, y: 3.5, width: 20, height: 8),
                font: .monospacedDigitSystemFont(ofSize: 7.1, weight: .bold),
                color: NSColor.labelColor,
                alignment: .center
            )
            x += StatusItemLayoutMetrics.classicQuotaUnitWidth
        }
    }

    private func drawLinearProgress(
        in rect: NSRect,
        fraction: CGFloat,
        paletteRole: StatusItemQuotaPaletteRole
    ) {
        let palette = palette(for: paletteRole)
        palette.track.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()

        let normalized = min(max(fraction, 0), 1)
        guard normalized > 0 else { return }
        let fillWidth = max(0.8, rect.width * normalized)
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
        let fillPath = NSBezierPath(
            roundedRect: fillRect,
            xRadius: min(rect.height / 2, fillWidth / 2),
            yRadius: min(rect.height / 2, fillWidth / 2)
        )
        guard let context = NSGraphicsContext.current?.cgContext,
              let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [palette.start.cgColor, palette.end.cgColor] as CFArray,
                locations: [0, 1]
              )
        else {
            palette.end.setFill()
            fillPath.fill()
            return
        }
        context.saveGState()
        fillPath.addClip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: fillRect.minX, y: fillRect.midY),
            end: CGPoint(x: fillRect.maxX, y: fillRect.midY),
            options: []
        )
        context.restoreGState()
    }

    private func drawCircularProgress(
        in rect: NSRect,
        fraction: CGFloat,
        paletteRole: StatusItemQuotaPaletteRole,
        lineWidth: CGFloat
    ) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - lineWidth / 2
        let palette = palette(for: paletteRole)

        let track = NSBezierPath()
        track.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: -270,
            clockwise: true
        )
        track.lineWidth = lineWidth
        track.lineCapStyle = .round
        palette.track.setStroke()
        track.stroke()

        let normalized = min(max(fraction, 0), 1)
        guard normalized > 0 else { return }
        let progress = NSBezierPath()
        progress.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - normalized * 360,
            clockwise: true
        )
        progress.lineWidth = lineWidth
        progress.lineCapStyle = .round
        palette.end.setStroke()
        progress.stroke()
    }

    private func palette(for role: StatusItemQuotaPaletteRole) -> Palette {
        switch role {
        case .fiveHour:
            Palette(
                start: NSColor(srgbRed: 0.09, green: 0.41, blue: 0.88, alpha: 1),
                end: NSColor(srgbRed: 0.18, green: 0.50, blue: 0.93, alpha: 1),
                track: NSColor(srgbRed: 0.87, green: 0.93, blue: 1, alpha: 1)
            )
        case .weekly:
            Palette(
                start: NSColor(srgbRed: 0.22, green: 0.56, blue: 0.96, alpha: 1),
                end: NSColor(srgbRed: 0.45, green: 0.71, blue: 1, alpha: 1),
                track: NSColor(srgbRed: 0.89, green: 0.95, blue: 1, alpha: 1)
            )
        }
    }

    private func drawText(
        _ value: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let text = NSAttributedString(
            string: value,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
        text.draw(in: rect)
    }

    private func drawIcon(in rect: NSRect) {
        guard let source = NSImage(named: "MenuBarIcon") else { return }
        let image = NSImage(size: rect.size)
        image.lockFocus()
        source.draw(
            in: NSRect(origin: .zero, size: rect.size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSColor.labelColor.setFill()
        NSRect(origin: .zero, size: rect.size).fill(using: .sourceIn)
        image.unlockFocus()
        image.isTemplate = false
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let store: DashboardStore
    private let defaults: UserDefaults
    private let renderer = StatusItemRenderer()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private var popover: NSPopover?
    private var appearanceObservation: NSKeyValueObservation?
    private var lastPresentation: StatusItemPresentation?
    private var lastAppearanceName: NSAppearance.Name?
    private var onOpenDashboard: () -> Void
    private var onOpenSettings: () -> Void

    init(
        store: DashboardStore,
        defaults: UserDefaults = .standard,
        onOpenDashboard: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.store = store
        self.defaults = defaults
        self.onOpenDashboard = onOpenDashboard
        self.onOpenSettings = onOpenSettings
        super.init()
        install()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func updateActions(
        onOpenDashboard: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.onOpenDashboard = onOpenDashboard
        self.onOpenSettings = onOpenSettings
    }

    func closePopover() {
        popover?.performClose(nil)
        popover = nil
    }

    private func install() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.target = self
        button.action = #selector(statusItemClicked)
        button.setAccessibilityLabel("SpendScope")

        appearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateStatusItem()
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: defaults
        )
        observeStore()
        updateStatusItem()
    }

    private func observeStore() {
        withObservationTracking {
            _ = store.state
            _ = store.isRefreshing
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.observeStore()
                self?.updateStatusItem()
            }
        }
    }

    @objc nonisolated private func defaultsDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusItem()
        }
    }

    @objc private func statusItemClicked() {
        if popover?.isShown == true {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let content = MenuBarPopoverView(
            store: store,
            onOpenDashboard: { [weak self] in
                self?.closePopover()
                self?.onOpenDashboard()
            },
            onOpenSettings: { [weak self] in
                self?.closePopover()
                self?.onOpenSettings()
            }
        )
        .preferredColorScheme(preferredColorScheme)
        let hostingController = NSHostingController(rootView: content)
        popover.contentViewController = hostingController
        hostingController.view.layoutSubtreeIfNeeded()
        popover.contentSize = hostingController.view.fittingSize
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let presentation = StatusItemPresentation(
            snapshot: store.snapshot,
            configuration: menuBarConfiguration,
            displayMode: statusItemDisplayMode
        )
        let appearance = button.effectiveAppearance
        guard presentation != lastPresentation || appearance.name != lastAppearanceName else { return }

        lastPresentation = presentation
        lastAppearanceName = appearance.name
        statusItem.length = presentation.itemLength
        button.image = renderer.render(presentation, appearance: appearance)
        button.toolTip = "SpendScope · \(presentation.label)"
        button.setAccessibilityValue(presentation.label)
    }

    private var menuBarConfiguration: MenuBarLabelConfiguration {
        MenuBarLabelConfiguration(
            quotaDisplay: QuotaDisplayPreference(
                rawValue: defaults.string(forKey: AppPreferenceKeys.quotaDisplay) ?? ""
            ) ?? .remaining,
            showsFiveHour: defaults.object(forKey: AppPreferenceKeys.showsFiveHour) as? Bool ?? true,
            showsWeekly: defaults.object(forKey: AppPreferenceKeys.showsWeekly) as? Bool ?? true
        )
    }

    private var statusItemDisplayMode: StatusItemDisplayMode {
        StatusItemDisplayMode(
            rawValue: defaults.string(forKey: AppPreferenceKeys.statusItemDisplayMode) ?? ""
        ) ?? .rich
    }

    private var preferredColorScheme: ColorScheme? {
        AppearancePreference(
            rawValue: defaults.string(forKey: AppPreferenceKeys.appearance) ?? ""
        )?.colorScheme
    }
}
