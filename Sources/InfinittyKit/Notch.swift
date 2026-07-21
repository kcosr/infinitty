import AppKit

/// Live-activity widget: a slim always-on-top strip at the top of chosen
/// displays showing the focused terminal's command state (running / exit
/// code), driven by OSC 133 markers. On a MacBook it sits beside the notch.
final class NotchActivityController {
    private struct Widget {
        let panel: NSPanel
        let label: NSTextField
        let dot: NSView
    }

    private var widgets: [Widget] = []
    private var hideTimer: Timer?

    /// display: builtin | external | primary | all
    func show(display: String) {
        hide()
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let builtin = screens.filter { $0.safeAreaInsets.top > 0 }
        let external = screens.filter { $0.safeAreaInsets.top <= 0 }

        let targets: [NSScreen]
        switch display {
        case "external":
            targets = external.isEmpty ? screens : external
        case "primary", "focused":
            targets = [NSScreen.main ?? screens[0]]
        case "all", "both":
            targets = screens
        default: // builtin
            targets = builtin.isEmpty ? [NSScreen.main ?? screens[0]] : builtin
        }

        for screen in targets {
            widgets.append(makeWidget(on: screen))
        }
        set(text: "infinitty", color: .systemGray)
    }

    private func makeWidget(on screen: NSScreen) -> Widget {
        let w: CGFloat = 300
        let hasNotch = screen.safeAreaInsets.top > 0
        let h: CGFloat = hasNotch ? max(screen.safeAreaInsets.top, 30) : 26
        // Beside the notch housing on built-ins; top-center on externals.
        let x = hasNotch ? screen.frame.midX + 110 : screen.frame.midX - w / 2
        let frame = NSRect(x: x, y: screen.frame.maxY - h, width: w, height: h)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        content.layer?.cornerRadius = 10
        content.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemGray.cgColor
        dot.layer?.cornerRadius = 4
        dot.frame = NSRect(x: 12, y: (h - 8) / 2, width: 8, height: 8)
        content.addSubview(dot)

        let label = NSTextField(labelWithString: "infinitty")
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingHead
        label.frame = NSRect(x: 28, y: (h - 16) / 2, width: w - 40, height: 16)
        label.autoresizingMask = [.width]
        content.addSubview(label)

        panel.contentView = content
        panel.orderFrontRegardless()
        return Widget(panel: panel, label: label, dot: dot)
    }

    func hide() {
        for widget in widgets { widget.panel.orderOut(nil) }
        widgets.removeAll()
        hideTimer?.invalidate()
        hideTimer = nil
    }

    private func set(text: String, color: NSColor) {
        for widget in widgets {
            widget.label.stringValue = text
            widget.dot.layer?.backgroundColor = color.cgColor
        }
    }

    /// External apps can post a transient message (app socket `activity`).
    func showCustom(text: String) {
        guard !widgets.isEmpty else { return }
        hideTimer?.invalidate()
        set(text: String(text.prefix(38)), color: .systemPurple)
        hideTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            self?.set(text: "infinitty", color: .systemGray)
        }
    }

    /// OSC 133 event from a session. kind: A prompt, C output start, D done.
    func handleMarker(kind: UInt8, exitCode: Int, commandLine: String?) {
        guard !widgets.isEmpty else { return }
        hideTimer?.invalidate()
        switch kind {
        case UInt8(ascii: "C"):
            let cmd = (commandLine ?? "command").suffix(34)
            set(text: "▶ \(cmd)", color: .systemBlue)
        case UInt8(ascii: "D"):
            if exitCode == 0 {
                set(text: "✓ done", color: .systemGreen)
            } else {
                set(text: "✗ exit \(exitCode)", color: .systemRed)
            }
            hideTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
                self?.set(text: "infinitty", color: .systemGray)
            }
        default:
            break
        }
    }
}

struct NotchTerminalMenuLayout {
    static let width: CGFloat = 34
    static let activityWidth: CGFloat = 300
    static let activityGap: CGFloat = 6

    static func frame(
        in screenFrame: NSRect,
        safeAreaTop: CGFloat,
        avoidingActivity: Bool = false
    ) -> NSRect {
        let hasNotch = safeAreaTop > 0
        let height = hasNotch ? max(safeAreaTop, 30) : 26
        let x: CGFloat
        if hasNotch {
            x = screenFrame.midX - 110 - width
        } else if avoidingActivity {
            x = screenFrame.midX - activityWidth / 2 - activityGap - width
        } else {
            x = screenFrame.midX - width / 2
        }
        return NSRect(
            x: x,
            y: screenFrame.maxY - height,
            width: width,
            height: height)
    }
}

/// Compact, interactive terminal launcher placed to the left of the MacBook
/// notch. This is deliberately independent from the right-side live-activity
/// widget so either feature can be enabled without the other.
final class NotchTerminalMenuController: NSObject {
    private struct Widget {
        let panel: NSPanel
        let button: NSButton
    }

    var makeMenu: (() -> NSMenu)?
    private var widgets: [Widget] = []
    private var requestedDisplay: String?
    private var avoidsActivity = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show(display: String, avoidingActivity: Bool = false) {
        requestedDisplay = display
        avoidsActivity = avoidingActivity
        rebuildWidgets()
    }

    func hide() {
        requestedDisplay = nil
        removeWidgets()
    }

    private func rebuildWidgets() {
        removeWidgets()
        guard let display = requestedDisplay else { return }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let builtin = screens.filter { $0.safeAreaInsets.top > 0 }
        let external = screens.filter { $0.safeAreaInsets.top <= 0 }

        let targets: [NSScreen]
        switch display {
        case "external":
            targets = external.isEmpty ? screens : external
        case "primary", "focused":
            targets = [NSScreen.main ?? screens[0]]
        case "all", "both":
            targets = screens
        default:
            targets = builtin.isEmpty ? [NSScreen.main ?? screens[0]] : builtin
        }

        widgets = targets.map { makeWidget(on: $0, avoidingActivity: avoidsActivity) }
    }

    private func removeWidgets() {
        for widget in widgets { widget.panel.orderOut(nil) }
        widgets.removeAll()
    }

    private func makeWidget(on screen: NSScreen, avoidingActivity: Bool) -> Widget {
        let frame = NotchTerminalMenuLayout.frame(
            in: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            avoidingActivity: avoidingActivity)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let button = NSButton(frame: NSRect(origin: .zero, size: frame.size))
        button.target = self
        button.action = #selector(showTerminalMenu(_:))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .white
        button.toolTip = "Infinitty Terminals"
        button.image = NSImage(
            systemSymbolName: "terminal",
            accessibilityDescription: "Infinitty Terminals")
        if button.image == nil {
            button.title = ">_"
            button.imagePosition = .noImage
            button.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        }

        let content = NSView(frame: button.frame)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        content.layer?.cornerRadius = 8
        content.addSubview(button)
        panel.contentView = content
        panel.orderFrontRegardless()
        return Widget(panel: panel, button: button)
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        rebuildWidgets()
    }

    @objc private func showTerminalMenu(_ sender: NSButton) {
        guard let menu = makeMenu?(), !menu.items.isEmpty else { return }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: sender.bounds.minY),
            in: sender)
    }
}
