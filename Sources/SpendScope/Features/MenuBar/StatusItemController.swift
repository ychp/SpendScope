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
    static let elementSpacing: CGFloat = 5
    static let leadingContentWidth: CGFloat = iconRect.maxX + elementSpacing
    static let classicQuotaUnitWidth: CGFloat = 25
    static let richValueWidth: CGFloat = 38
    static let richMetricWidth: CGFloat = 58
    static let richResetWidth: CGFloat = 35
    static let richMetricSpacing: CGFloat = 5
    static let emptyImageWidth: CGFloat = 24
}

struct StatusItemMetricPresentation: Equatable, Identifiable {
    let id: String
    let label: String
    let value: String
    let fraction: CGFloat
    let resetText: String?
    let resetDescription: String?
    let paletteRole: StatusItemQuotaPaletteRole
}

struct StatusItemPresentation: Equatable {
    let displayMode: StatusItemDisplayMode
    let metrics: [StatusItemMetricPresentation]
    let imageSize: NSSize
    let itemLength: CGFloat
    let label: String
    let tooltip: String

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
                resetText: configuration.showsResetCountdown
                    ? quota.resetCountdown(now: now)
                    : nil,
                resetDescription: configuration.showsResetCountdown
                    ? quota.resetDescription(now: now)
                    : nil,
                paletteRole: quota.id == "7d" ? .weekly : .fiveHour
            )
        }

        let imageWidth: CGFloat
        switch displayMode {
        case .rich:
            if metrics.isEmpty {
                imageWidth = StatusItemLayoutMetrics.emptyImageWidth
            } else {
                let resetWidth = metrics.reduce(CGFloat.zero) { width, metric in
                    width + (metric.resetText == nil
                        ? 0
                        : StatusItemLayoutMetrics.elementSpacing
                            + StatusItemLayoutMetrics.richResetWidth)
                }
                let metricWidth = metrics.count == 1
                    ? StatusItemLayoutMetrics.richValueWidth
                    : CGFloat(metrics.count) * StatusItemLayoutMetrics.richMetricWidth
                imageWidth = StatusItemLayoutMetrics.leadingContentWidth
                    + metricWidth
                    + CGFloat(max(0, metrics.count - 1)) * StatusItemLayoutMetrics.richMetricSpacing
                    + resetWidth
                    + 2
            }
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
        let quotaTerm = configuration.quotaDisplay == .remaining ? "剩余" : "已用"
        let quotaDescription = metrics.map { metric in
            let quotaName = metric.id == "5h" ? "5 小时额度" : "7 天额度"
            var description = "\(quotaName) \(quotaTerm) \(metric.value)"
            if let resetDescription = metric.resetDescription {
                description += "，\(resetDescription)"
            }
            return description
        }.joined(separator: "；")
        tooltip = metrics.isEmpty
            ? "SpendScope · Codex · 暂无可用额度 · 点击查看用量"
            : "SpendScope · Codex · \(quotaDescription) · 点击查看用量"
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
        var x = StatusItemLayoutMetrics.leadingContentWidth
        let showsPeriodLabels = metrics.count > 1
        for (index, metric) in metrics.enumerated() {
            if index > 0 {
                x += StatusItemLayoutMetrics.richMetricSpacing
            }

            if showsPeriodLabels {
                drawText(
                    metric.label,
                    in: NSRect(x: x, y: 4, width: 17, height: 14),
                    font: .monospacedDigitSystemFont(ofSize: 9.8, weight: .semibold),
                    color: NSColor.labelColor,
                    alignment: .right
                )
            }
            let valueOffset: CGFloat = showsPeriodLabels ? 20 : 0
            drawValuePill(
                metric.value,
                fraction: metric.fraction,
                paletteRole: metric.paletteRole,
                in: NSRect(
                    x: x + valueOffset,
                    y: 3,
                    width: StatusItemLayoutMetrics.richValueWidth,
                    height: 16
                )
            )
            x += showsPeriodLabels
                ? StatusItemLayoutMetrics.richMetricWidth
                : StatusItemLayoutMetrics.richValueWidth

            if let resetText = metric.resetText {
                x += StatusItemLayoutMetrics.elementSpacing
                drawResetCountdown(resetText, x: x)
                x += StatusItemLayoutMetrics.richResetWidth
            }
        }
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
                font: .monospacedDigitSystemFont(ofSize: 6.2, weight: .semibold),
                color: NSColor.secondaryLabelColor,
                alignment: .center
            )
            drawText(
                metric.value,
                in: NSRect(x: x + 2, y: 3.5, width: 20, height: 8),
                font: .monospacedDigitSystemFont(ofSize: 7.8, weight: .bold),
                color: NSColor.labelColor,
                alignment: .center
            )
            x += StatusItemLayoutMetrics.classicQuotaUnitWidth
        }
    }

    private func drawValuePill(
        _ value: String,
        fraction: CGFloat,
        paletteRole: StatusItemQuotaPaletteRole,
        in rect: NSRect
    ) {
        let fillRect = drawLinearProgress(
            in: rect,
            fraction: fraction,
            paletteRole: paletteRole
        )
        drawText(
            value,
            in: NSRect(x: rect.minX, y: rect.minY + 2, width: rect.width, height: 12),
            font: .monospacedDigitSystemFont(ofSize: 9.8, weight: .bold),
            color: NSColor.labelColor,
            alignment: .center
        )

        if let fillRect {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: fillRect).addClip()
            drawText(
                value,
                in: NSRect(x: rect.minX, y: rect.minY + 2, width: rect.width, height: 12),
                font: .monospacedDigitSystemFont(ofSize: 9.8, weight: .bold),
                color: NSColor.white,
                alignment: .center
            )
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    @discardableResult
    private func drawLinearProgress(
        in rect: NSRect,
        fraction: CGFloat,
        paletteRole: StatusItemQuotaPaletteRole
    ) -> NSRect? {
        let palette = palette(for: paletteRole)
        palette.track.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()

        let normalized = min(max(fraction, 0), 1)
        guard normalized > 0 else { return nil }
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
            return fillRect
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
        return fillRect
    }

    private func drawResetCountdown(_ value: String, x: CGFloat) {
        let color = NSColor.systemBlue
        let backgroundRect = NSRect(x: x, y: 3, width: 33, height: 16)
        color.withAlphaComponent(0.14).setFill()
        NSBezierPath(
            roundedRect: backgroundRect,
            xRadius: backgroundRect.height / 2,
            yRadius: backgroundRect.height / 2
        ).fill()

        let iconRect = NSRect(x: x + 3, y: 7, width: 8, height: 8)
        if let symbol = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)) {
            drawTintedImage(symbol, color: color, in: iconRect)
        }
        drawText(
            value,
            in: NSRect(x: x + 12, y: 4, width: 18, height: 13),
            font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
            color: color,
            alignment: .left
        )
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
        drawTintedImage(source, color: NSColor.labelColor, in: rect)
    }

    private func drawTintedImage(_ source: NSImage, color: NSColor, in rect: NSRect) {
        let image = NSImage(size: rect.size)
        image.lockFocus()
        source.draw(
            in: NSRect(origin: .zero, size: rect.size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        color.setFill()
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
    private var popoverNeedsFocus = false
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
        popoverNeedsFocus = false
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: NSApp
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

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        focusPopoverIfReady()
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
        popover.delegate = self

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
        .preferredColorScheme(.light)
        let hostingController = NSHostingController(rootView: content)
        popover.contentViewController = hostingController
        hostingController.view.layoutSubtreeIfNeeded()
        popover.contentSize = hostingController.view.fittingSize
        self.popover = popover
        popoverNeedsFocus = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        focusPopoverIfReady()
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func focusPopoverIfReady() {
        guard popoverNeedsFocus,
              let popover,
              popover.isShown,
              let window = popover.contentViewController?.view.window else {
            return
        }
        window.makeKey()
        popoverNeedsFocus = false
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
        button.toolTip = presentation.tooltip
        button.setAccessibilityValue(presentation.label)
    }

    private var menuBarConfiguration: MenuBarLabelConfiguration {
        MenuBarLabelConfiguration(
            quotaDisplay: QuotaDisplayPreference(
                rawValue: defaults.string(forKey: AppPreferenceKeys.quotaDisplay) ?? ""
            ) ?? .remaining,
            showsFiveHour: defaults.object(forKey: AppPreferenceKeys.showsFiveHour) as? Bool ?? true,
            showsWeekly: defaults.object(forKey: AppPreferenceKeys.showsWeekly) as? Bool ?? true,
            showsResetCountdown: defaults.object(forKey: AppPreferenceKeys.showsResetCountdown) as? Bool ?? true
        )
    }

    private var statusItemDisplayMode: StatusItemDisplayMode {
        StatusItemDisplayMode(
            rawValue: defaults.string(forKey: AppPreferenceKeys.statusItemDisplayMode) ?? ""
        ) ?? .rich
    }

}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidShow(_ notification: Notification) {
        guard let shownPopover = notification.object as? NSPopover,
              shownPopover === popover else {
            return
        }
        focusPopoverIfReady()
    }
}
