import AppKit
import SwiftUI

enum NotchSummaryPalette {
    static let primary = NSColor.white
    static let countdown = NSColor(srgbRed: 0.988, green: 0.827, blue: 0.302, alpha: 1)
    static let quota = StatusItemQuotaPalette(
        start: NSColor(srgbRed: 0.357, green: 0.247, blue: 0.659, alpha: 1),
        end: NSColor(srgbRed: 0.357, green: 0.247, blue: 0.659, alpha: 1),
        background: NSColor(srgbRed: 0.867, green: 0.827, blue: 0.980, alpha: 1),
        progressTrack: NSColor.black.withAlphaComponent(0.18),
        text: NSColor(srgbRed: 0.157, green: 0.102, blue: 0.275, alpha: 1),
        border: .clear
    )
}

enum NotchSummaryLayout {
    static let height: CGFloat = 32

    static func frame(
        screenFrame: NSRect,
        topInset: CGFloat,
        leftArea: NSRect?,
        rightArea: NSRect?
    ) -> NSRect? {
        guard topInset > 0,
              let leftArea, let rightArea,
              rightArea.minX > leftArea.maxX else { return nil }
        let notchWidth = rightArea.minX - leftArea.maxX
        let width = min(max(notchWidth + 16, 224), screenFrame.width)
        let centerX = (leftArea.maxX + rightArea.minX) / 2
        return NSRect(
            x: min(max(centerX - width / 2, screenFrame.minX), screenFrame.maxX - width),
            y: screenFrame.maxY - topInset - height,
            width: width,
            height: height
        )
    }

    @MainActor
    static func frame(on screen: NSScreen) -> NSRect? {
        frame(
            screenFrame: screen.frame,
            topInset: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea,
            rightArea: screen.auxiliaryTopRightArea
        )
    }
}

/// Owns only the display surface; quota values still come from StatusItemPresentation.
@MainActor
final class NotchSummaryController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<NotchSummaryView>?

    isolated deinit {
        panel?.close()
    }

    var anchorView: NSView? { hostingView }

    func hide() {
        panel?.orderOut(nil)
    }

    func update(
        frame: NSRect,
        presentation: StatusItemPresentation,
        quotaDisplay: QuotaDisplayPreference,
        onClick: @escaping () -> Void
    ) {
        let content = NotchSummaryView(
            presentation: presentation,
            quotaDisplay: quotaDisplay,
            onClick: onClick
        )
        if panel == nil {
            let panel = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = "SpendScope 刘海摘要"
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isMovable = false
            panel.isReleasedWhenClosed = false
            panel.becomesKeyOnlyIfNeeded = true
            let hostingView = NSHostingView(rootView: content)
            panel.contentView = hostingView
            self.hostingView = hostingView
            self.panel = panel
        } else {
            hostingView?.rootView = content
        }
        panel?.setFrame(frame, display: true)
        panel?.orderFrontRegardless()
    }
}

struct NotchSummaryView: View {
    let presentation: StatusItemPresentation
    let quotaDisplay: QuotaDisplayPreference
    var onClick: () -> Void = {}

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 10) {
                Text(presentation.metrics.isEmpty
                     ? "暂无额度"
                     : quotaDisplay == .remaining ? "7 天剩余" : "7 天已用")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(nsColor: NotchSummaryPalette.primary))
                Image(nsImage: StatusItemRenderer(style: .notch).render(
                    presentation,
                    appearance: NSAppearance(named: .darkAqua)!
                ))
                .interpolation(.high)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black, in: UnevenRoundedRectangle(
                bottomLeadingRadius: 13,
                bottomTrailingRadius: 13
            ))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: NotchSummaryLayout.height)
        .help(presentation.tooltip)
        .accessibilityLabel("SpendScope 刘海摘要")
        .accessibilityValue(presentation.label)
        .accessibilityHint("打开用量面板")
        .environment(\.colorScheme, .dark)
    }
}
