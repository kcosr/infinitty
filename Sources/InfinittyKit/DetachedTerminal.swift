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
