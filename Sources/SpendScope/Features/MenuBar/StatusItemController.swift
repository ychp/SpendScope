import AppKit
import Observation
import SwiftUI

enum StatusItemLayoutMetrics {
    static let imageHeight: CGFloat = 22
    static let iconRect = NSRect(x: 2, y: 2, width: 18, height: 18)
    static let textOriginX: CGFloat = 24
    static let trailingPadding: CGFloat = 2
    static let itemOuterPadding: CGFloat = 8
    static let metricSpacing: CGFloat = 7
    static let labelValueSpacing: CGFloat = 4
    static let valueHorizontalPadding: CGFloat = 6
    static let valueMinimumWidth: CGFloat = 36
    static let valueHeight: CGFloat = 16
}

struct StatusItemPresentation: Equatable {
    struct Metric: Equatable {
        let label: String
        let value: String?
        let fraction: CGFloat?
    }

    let label: String
    let metrics: [Metric]
    let imageSize: NSSize
    let itemLength: CGFloat

    init(label: String) {
        self.label = label
        metrics = Self.metrics(from: label)
        let textWidth = Self.contentWidth(for: metrics)
        let imageWidth = StatusItemLayoutMetrics.textOriginX
            + textWidth
            + StatusItemLayoutMetrics.trailingPadding
        imageSize = NSSize(width: imageWidth, height: StatusItemLayoutMetrics.imageHeight)
        itemLength = imageWidth + StatusItemLayoutMetrics.itemOuterPadding
    }

    private static var labelFont: NSFont { NSFont.systemFont(ofSize: 10, weight: .semibold) }
    private static var valueFont: NSFont { NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold) }
    private static var fallbackFont: NSFont {
        NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    }

    private static func metrics(from label: String) -> [Metric] {
        label.split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { component in
                guard let separator = component.lastIndex(of: " ") else {
                    return Metric(label: component, value: nil, fraction: nil)
                }

                let metricLabel = String(component[..<separator])
                    .trimmingCharacters(in: .whitespaces)
                let value = String(component[component.index(after: separator)...])
                    .trimmingCharacters(in: .whitespaces)
                guard !metricLabel.isEmpty, !value.isEmpty else {
                    return Metric(label: component, value: nil, fraction: nil)
                }

                return Metric(
                    label: metricLabel,
                    value: value,
                    fraction: percentageFraction(from: value)
                )
            }
    }

    private static func percentageFraction(from value: String) -> CGFloat? {
        guard value.hasSuffix("%"),
              let percentage = Double(value.dropLast())
        else { return nil }
        return CGFloat(min(max(percentage / 100, 0), 1))
    }

    private static func contentWidth(for metrics: [Metric]) -> CGFloat {
        metrics.enumerated().reduce(0) { width, entry in
            let metricWidth: CGFloat
            if let value = entry.element.value {
                let labelWidth = ceil((entry.element.label as NSString).size(withAttributes: [.font: labelFont]).width)
                let valueWidth = max(
                    ceil((value as NSString).size(withAttributes: [.font: valueFont]).width)
                        + StatusItemLayoutMetrics.valueHorizontalPadding * 2,
                    StatusItemLayoutMetrics.valueMinimumWidth
                )
                metricWidth = labelWidth + StatusItemLayoutMetrics.labelValueSpacing + valueWidth
            } else {
                metricWidth = ceil((entry.element.label as NSString).size(withAttributes: [.font: fallbackFont]).width)
            }
            return width
                + (entry.offset == 0 ? 0 : StatusItemLayoutMetrics.metricSpacing)
                + metricWidth
        }
    }
}

struct StatusItemRenderer {
    private let labelFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
    private let fallbackFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    private let blue = NSColor(srgbRed: 0.12, green: 0.47, blue: 0.96, alpha: 1)

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
        drawIcon(in: StatusItemLayoutMetrics.iconRect, color: NSColor.labelColor)
        drawMetrics(presentation.metrics)
        return image
    }

    private func drawMetrics(_ metrics: [StatusItemPresentation.Metric]) {
        var x = StatusItemLayoutMetrics.textOriginX

        for (index, metric) in metrics.enumerated() {
            if index > 0 {
                x += StatusItemLayoutMetrics.metricSpacing
            }

            guard let value = metric.value else {
                let width = textWidth(metric.label, font: fallbackFont)
                drawText(metric.label, at: x, width: width, font: fallbackFont, color: NSColor.labelColor)
                x += width
                continue
            }

            let labelWidth = textWidth(metric.label, font: labelFont)
            drawText(metric.label, at: x, width: labelWidth, font: labelFont, color: NSColor.labelColor)
            x += labelWidth + StatusItemLayoutMetrics.labelValueSpacing

            let valueWidth = max(
                textWidth(value, font: valueFont) + StatusItemLayoutMetrics.valueHorizontalPadding * 2,
                StatusItemLayoutMetrics.valueMinimumWidth
            )
            let valueRect = NSRect(
                x: x,
                y: floor((StatusItemLayoutMetrics.imageHeight - StatusItemLayoutMetrics.valueHeight) / 2),
                width: valueWidth,
                height: StatusItemLayoutMetrics.valueHeight
            )
            drawValuePill(value, fraction: metric.fraction, in: valueRect)
            x += valueWidth
        }
    }

    private func drawValuePill(_ value: String, fraction: CGFloat?, in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        blue.withAlphaComponent(0.20).setFill()
        path.fill()

        var fillRect: NSRect?
        if let fraction, fraction > 0 {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let fillWidth = max(2, rect.width * min(max(fraction, 0), 1))
            let progressRect = NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
            let gradient = NSGradient(
                starting: NSColor(srgbRed: 0.22, green: 0.60, blue: 1.0, alpha: 0.88),
                ending: blue
            )
            gradient?.draw(in: progressRect, angle: 0)
            NSGraphicsContext.restoreGraphicsState()
            fillRect = progressRect
        }

        let text = NSAttributedString(
            string: value,
            attributes: [
                .font: valueFont,
                .foregroundColor: NSColor.labelColor
            ]
        )
        drawCentered(text, in: rect)

        if let fillRect {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: fillRect).addClip()
            let highlightedText = NSAttributedString(
                string: value,
                attributes: [
                    .font: valueFont,
                    .foregroundColor: NSColor.white
                ]
            )
            drawCentered(highlightedText, in: rect)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawText(_ value: String, at x: CGFloat, width: CGFloat, font: NSFont, color: NSColor) {
        let text = NSAttributedString(
            string: value,
            attributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
        let textSize = text.size()
        text.draw(at: NSPoint(
            x: x + floor((width - textSize.width) / 2),
            y: floor((StatusItemLayoutMetrics.imageHeight - textSize.height) / 2)
        ))
    }

    private func textWidth(_ value: String, font: NSFont) -> CGFloat {
        ceil((value as NSString).size(withAttributes: [.font: font]).width)
    }

    private func drawCentered(_ text: NSAttributedString, in rect: NSRect) {
        let textSize = text.size()
        text.draw(at: NSPoint(
            x: floor(rect.midX - textSize.width / 2),
            y: floor(rect.midY - textSize.height / 2)
        ))
    }

    private func drawIcon(in rect: NSRect, color: NSColor) {
        guard let source = NSImage(named: "MenuBarIcon") else { return }
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
            label: store.menuBarLabel(configuration: menuBarConfiguration)
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
            showsWeekly: defaults.object(forKey: AppPreferenceKeys.showsWeekly) as? Bool ?? true,
            showsToday: defaults.object(forKey: AppPreferenceKeys.showsToday) as? Bool ?? false
        )
    }

    private var preferredColorScheme: ColorScheme? {
        AppearancePreference(
            rawValue: defaults.string(forKey: AppPreferenceKeys.appearance) ?? ""
        )?.colorScheme
    }
}
