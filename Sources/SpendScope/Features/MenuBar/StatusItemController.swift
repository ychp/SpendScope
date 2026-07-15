import AppKit
import Observation
import SwiftUI

enum StatusItemLayoutMetrics {
    static let imageHeight: CGFloat = 22
    static let iconRect = NSRect(x: 2, y: 2, width: 18, height: 18)
    static let textOriginX: CGFloat = 24
    static let trailingPadding: CGFloat = 2
    static let itemOuterPadding: CGFloat = 8
}

struct StatusItemPresentation: Equatable {
    let label: String
    let imageSize: NSSize
    let itemLength: CGFloat

    init(label: String, font: NSFont = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)) {
        self.label = label
        let textWidth = ceil((label as NSString).size(withAttributes: [.font: font]).width)
        let imageWidth = StatusItemLayoutMetrics.textOriginX
            + textWidth
            + StatusItemLayoutMetrics.trailingPadding
        imageSize = NSSize(width: imageWidth, height: StatusItemLayoutMetrics.imageHeight)
        itemLength = imageWidth + StatusItemLayoutMetrics.itemOuterPadding
    }
}

struct StatusItemRenderer {
    private let font = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.systemFontSize,
        weight: .regular
    )

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
        let color = NSColor.labelColor
        drawIcon(in: StatusItemLayoutMetrics.iconRect, color: color)

        let text = NSAttributedString(
            string: presentation.label,
            attributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
        let textSize = text.size()
        text.draw(at: NSPoint(
            x: StatusItemLayoutMetrics.textOriginX,
            y: floor((StatusItemLayoutMetrics.imageHeight - textSize.height) / 2)
        ))
        return image
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
