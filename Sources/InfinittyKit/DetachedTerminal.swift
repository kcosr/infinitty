import AppKit

/// A live terminal tab that is temporarily hosted by neither a standard
/// window nor the quick-terminal panel. The terminal view tree (including any
/// nested splits and blur wrapper) remains intact, so its sessions, scrollback,
/// and child processes continue running while it is listed in the Window menu.
final class DetachedTerminal {
    let id = UUID()
    var rootView: NSView
    var customTitle: String?
    weak var preferredFocus: TerminalView?

    init(rootView: NSView, customTitle: String?, preferredFocus: TerminalView?) {
        self.rootView = rootView
        self.customTitle = customTitle
        self.preferredFocus = preferredFocus
    }

    func contains(_ view: NSView) -> Bool {
        view === rootView || view.isDescendant(of: rootView)
    }

    func displayTitle(sessions: [TerminalSession]) -> String {
        let focused = preferredFocus.flatMap { view in
            sessions.first { $0.view === view }
        }
        let base = customTitle ?? focused?.title ?? sessions.first?.title ?? "Terminal"
        return sessions.count > 1 ? "\(base) (\(sessions.count))" : base
    }

    /// Remove an exited pane from the retained split tree. The caller removes
    /// the entire DetachedTerminal instead when this was its final session.
    func removePane(_ view: TerminalView) {
        guard contains(view), let split = view.superview as? NSSplitView else { return }
        view.removeFromSuperview()
        collapse(split)
    }

    private func collapse(_ split: NSSplitView) {
        guard split.arrangedSubviews.count == 1 else { return }
        let sibling = split.arrangedSubviews[0]
        sibling.removeFromSuperview()

        if split === rootView {
            split.removeFromSuperview()
            sibling.frame = rootView.frame
            sibling.autoresizingMask = [.width, .height]
            rootView = sibling
        } else if let parent = split.superview as? NSSplitView {
            let index = parent.arrangedSubviews.firstIndex(of: split) ?? 0
            split.removeFromSuperview()
            parent.insertArrangedSubview(sibling, at: index)
            collapse(parent)
        } else if let parent = split.superview {
            sibling.frame = split.frame
            sibling.autoresizingMask = [.width, .height]
            parent.replaceSubview(split, with: sibling)
        }
    }
}

final class DetachedTerminalPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Temporarily hosts one DetachedTerminal in a floating panel. Dismissal only
/// removes the window shell; the live terminal tree stays owned by the same
/// DetachedTerminal and returns to its menu entry unchanged.
final class DetachedTerminalPreviewController: NSObject, NSWindowDelegate {
    private(set) var detached: DetachedTerminal?
    private(set) var window: DetachedTerminalPreviewPanel?
    var onDismiss: (() -> Void)?

    private var presentationGeneration: UInt64 = 0
    private var ignoreResignUntil = Date.distantPast
    private var dismissing = false

    @discardableResult
    func present(
        _ detached: DetachedTerminal,
        title: String,
        activate: Bool = true
    ) -> NSWindow {
        dismiss()
        presentationGeneration &+= 1
        ignoreResignUntil = Date().addingTimeInterval(0.25)
        self.detached = detached

        let root = detached.rootView
        root.removeFromSuperview()
        let size = NSSize(
            width: root.bounds.width > 100 ? root.bounds.width : 960,
            height: root.bounds.height > 100 ? root.bounds.height : 520)
        root.frame = NSRect(origin: .zero, size: size)
        root.autoresizingMask = [.width, .height]

        let panel = DetachedTerminalPreviewPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false)
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = root
        panel.delegate = self
        panel.center()
        self.window = panel

        if activate {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            if let preferredFocus = detached.preferredFocus {
                panel.makeFirstResponder(preferredFocus)
            }
        } else {
            panel.orderFront(nil)
        }
        return panel
    }

    @discardableResult
    func dismiss(ifPresenting detached: DetachedTerminal? = nil) -> Bool {
        guard let current = self.detached,
              detached == nil || current === detached else { return false }
        dismiss()
        return true
    }

    func refreshRoot() {
        guard let detached, let window,
              window.contentView !== detached.rootView else { return }
        detached.rootView.removeFromSuperview()
        window.contentView = detached.rootView
        detached.rootView.frame = window.contentLayoutRect
        detached.rootView.autoresizingMask = [.width, .height]
    }

    func dismiss() {
        guard !dismissing, let window else { return }
        dismissing = true
        presentationGeneration &+= 1
        if let detached,
           let focused = window.firstResponder as? TerminalView,
           detached.contains(focused) {
            detached.preferredFocus = focused
        }
        window.delegate = nil
        window.contentView = nil
        window.orderOut(nil)
        window.close()
        self.window = nil
        detached = nil
        dismissing = false
        onDismiss?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss()
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow,
              panel === window else { return }
        let generation = presentationGeneration
        let delay = max(ignoreResignUntil.timeIntervalSinceNow, 0.05)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak panel] in
            guard let self, let panel,
                  self.presentationGeneration == generation,
                  self.window === panel,
                  !panel.isKeyWindow,
                  panel.attachedSheet == nil,
                  panel.childWindows?.contains(where: \.isVisible) != true
            else { return }
            self.dismiss()
        }
    }
}
