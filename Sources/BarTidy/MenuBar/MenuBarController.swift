import Cocoa

// BarTidy: a minimal Hidden Bar style menu bar declutterer.
//
// Three status items sit in the menu bar (right side shown):
//
//   [ always hidden ]  ┊  [ hidden ]  |  [ always shown ]  ‹   (system items)
//                      ^alwaysHidden  ^separator            ^toggle
//
// Hiding works by making a separator very wide: the menu bar has no room for
// the items on its left, so they are pushed out of view. Expanding shrinks it.
// Cmd-drag icons in the menu bar to choose which zone they live in.
//
// macOS 27 note: status items are laid out by the new MenuBarAgent, which moves
// items that don't fit into its own overflow group instead of off-screen, and
// silently drops any single item wider than roughly half the screen. The classic
// 10,000pt separator is therefore thrown away and hides nothing. Instead we use
// the widest length MenuBarAgent still accepts (see `hidingLength`): the separator
// can't fit, so it and everything to its left go into the overflow group, which
// is not shown when the group is that wide.

// MARK: - Status items

final class MenuBarController: NSObject {
    enum State: String { case collapsed, expanded, expandedAll }

    /// Classic hiding width, still right for macOS 26 and earlier.
    static let legacyHidingLength: CGFloat = 10_000
    /// Width of the separator when "Show separator" is off (still draggable).
    static let invisibleSeparatorLength: CGFloat = 8

    let toggle: NSStatusItem
    let separator: NSStatusItem
    let alwaysHiddenSeparator: NSStatusItem

    private(set) var state: State = .expanded
    private var collapseTimer: Timer?
    private var warnedAboutOrder = false
    private var warnedAboutRescue = false
    /// Set when hiding made the arrow itself unreachable; blocks automatic re-collapse.
    private var hidingBlocked = false
    private var watchdogWork: DispatchWorkItem?
    private var verifyWork: DispatchWorkItem?
    var onShowPreferences: (() -> Void)?
    /// Extra items for the right-click menu (the Notch submenu), built fresh on each right-click.
    var extraMenuItems: (() -> [NSMenuItem])?

    override init() {
        // New status items appear to the left of existing ones, so creating them
        // right-to-left gives the right default order on first launch. After that
        // autosaveName restores wherever the user dragged them.
        let bar = NSStatusBar.system
        toggle = bar.statusItem(withLength: NSStatusItem.variableLength)
        toggle.autosaveName = "bartidy.toggle"
        separator = bar.statusItem(withLength: NSStatusItem.variableLength)
        separator.autosaveName = "bartidy.separator"
        alwaysHiddenSeparator = bar.statusItem(withLength: NSStatusItem.variableLength)
        alwaysHiddenSeparator.autosaveName = "bartidy.alwaysHidden"
        super.init()

        if let b = toggle.button {
            b.target = self
            b.action = #selector(toggleClicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.setAccessibilityLabel(AppInfo.name)
            b.toolTip = "Click: show/hide • ⌥-click: also always-hidden • Right-click: menu • ⌃⌥B"
        }
        separator.button?.image = Icons.separator
        separator.button?.setAccessibilityLabel("\(AppInfo.name) separator")
        alwaysHiddenSeparator.button?.image = Icons.alwaysHiddenSeparator
        alwaysHiddenSeparator.button?.setAccessibilityLabel("\(AppInfo.name) always-hidden separator")

        alwaysHiddenSeparator.isVisible = Pref.alwaysHiddenEnabled
        render()

        // Display arrangement or resolution changes alter the usable hiding width.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.render() }
        }
    }

    // MARK: Hiding width (macOS 27)

    /// Width that hides everything left of a separator on the toggle's screen.
    var hidingLength: CGFloat {
        guard #available(macOS 27, *) else { return Self.legacyHidingLength }
        let width = screenWidth
        if let learned = Pref.learnedHidingLengths[Self.key(width)] { return learned }
        // Measured on macOS 27.2: 1920pt screen accepts <= 935, rejects >= 950.
        return floor(width / 2 - 28)
    }

    private var screenWidth: CGFloat {
        (toggle.button?.window?.screen ?? NSScreen.main)?.frame.width ?? 1440
    }

    private static func key(_ width: CGFloat) -> String { String(Int(width)) }

    /// After collapsing, MenuBarAgent either overflows the separator (its window
    /// stops being visible) or rejects the length (window stays "visible" and the
    /// icons stay put). On rejection, shrink and remember what works for this screen.
    private func verifyCollapse(attempt: Int = 0) {
        verifyWork?.cancel()
        guard #available(macOS 27, *) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .collapsed,
                  let w = self.separator.button?.window else { return }
            let rejected = w.occlusionState.contains(.visible)
            debugLog("verify collapse: length=\(self.separator.length) rejected=\(rejected)")
            guard rejected else { return }
            let width = self.screenWidth
            let shrunk = floor(self.separator.length * 0.92)
            guard shrunk >= width * 0.3, attempt < 6 else {
                debugLog("verify collapse: giving up at \(self.separator.length)")
                return
            }
            Pref.learnedHidingLengths[Self.key(width)] = shrunk
            self.render()
            self.verifyCollapse(attempt: attempt + 1)
        }
        verifyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Collapse once the menu bar has laid our items out (frames are zero until then).
    func collapseWhenReady(attempt: Int = 0) {
        if frameX(toggle) != nil && frameX(separator) != nil {
            apply(.collapsed, userInitiated: false)
        } else if attempt < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.collapseWhenReady(attempt: attempt + 1)
            }
        }
    }

    // MARK: Actions

    @objc private func toggleClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        debugLog("toggle clicked: event=\(event.type.rawValue) modifiers=\(event.modifierFlags.rawValue)")
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else if event.modifierFlags.contains(.option) {
            apply(state == .expandedAll ? .collapsed : .expandedAll, userInitiated: true)
        } else {
            apply(state == .collapsed ? .expanded : .collapsed, userInitiated: true)
        }
    }

    /// Global hotkey and other non-click toggles.
    func toggleHidden() {
        apply(state == .collapsed ? .expanded : .collapsed, userInitiated: true)
    }

    private func showMenu() {
        let menu = NSMenu()
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        if let extra = extraMenuItems?(), !extra.isEmpty {
            menu.addItem(.separator())
            extra.forEach(menu.addItem)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        // Pop the menu up from the arrow directly. (Attaching it and calling performClick could also
        // deliver the toggle action, so a right-click would expand the hidden icons.)
        guard let button = toggle.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func openPreferences() { onShowPreferences?() }

    // MARK: State

    func apply(_ requested: State, userInitiated: Bool) {
        debugLog("apply \(requested.rawValue) user=\(userInitiated) from=\(state.rawValue)")
        var target = requested
        if target == .expandedAll && !Pref.alwaysHiddenEnabled { target = .expanded }
        if userInitiated { hidingBlocked = false }
        if target == .collapsed && hidingBlocked {
            debugLog("collapse skipped: hiding blocked after rescue")
            return
        }

        // Collapsing with the separator on the wrong side of the toggle would hide
        // the toggle itself (and the user would lose the app). Refuse instead.
        if target == .collapsed && !isLeft(separator, of: toggle) {
            debugLog("refusing to collapse: separator is right of toggle")
            if userInitiated { warnWrongOrder() }
            target = .expanded
            if state == .expanded { scheduleAutoCollapse(); return }
        }

        let wasCollapsed = state == .collapsed
        state = target
        render()
        scheduleAutoCollapse()
        if state == .collapsed && !wasCollapsed { verifyCollapse() }
    }

    /// Re-applies preferences (separator visibility, always-hidden zone).
    func preferencesChanged() {
        alwaysHiddenSeparator.isVisible = Pref.alwaysHiddenEnabled
        if state == .expandedAll && !Pref.alwaysHiddenEnabled { state = .expanded }
        hidingBlocked = false
        render()
        scheduleAutoCollapse()
    }

    private func render() {
        // The always-hidden zone is only hidden when its separator is left of BOTH the
        // main separator and the arrow. Otherwise a 900pt-wide separator would push the
        // arrow itself out of the menu bar.
        let hideAlwaysHiddenZone = Pref.alwaysHiddenEnabled && state == .expanded && !hidingBlocked
            && isLeft(alwaysHiddenSeparator, of: separator)
            && isLeft(alwaysHiddenSeparator, of: toggle)

        switch state {
        case .collapsed:
            separator.button?.image = nil
            separator.length = hidingLength
            toggle.button?.image = Icons.collapsed
        case .expanded, .expandedAll:
            if Pref.showSeparator {
                separator.button?.image = Icons.separator
                separator.length = NSStatusItem.variableLength
            } else {
                separator.button?.image = nil
                separator.length = Self.invisibleSeparatorLength
            }
            toggle.button?.image = Icons.expanded
        }

        if Pref.alwaysHiddenEnabled {
            // When collapsed, the main separator already hides everything to its left
            // (including the always-hidden zone), so this one stays small. Two huge
            // separators at once is what overflowed the arrow.
            if hideAlwaysHiddenZone {
                alwaysHiddenSeparator.button?.image = nil
                alwaysHiddenSeparator.length = hidingLength
            } else {
                alwaysHiddenSeparator.button?.image = Pref.showSeparator ? Icons.alwaysHiddenSeparator : nil
                alwaysHiddenSeparator.length = Pref.showSeparator ? NSStatusItem.variableLength : Self.invisibleSeparatorLength
            }
        }
        debugLog("render state=\(state.rawValue)")
        dumpFrames("render")
        if state == .collapsed || hideAlwaysHiddenZone { scheduleWatchdog() }
    }

    // MARK: Self-rescue

    /// True when the arrow is somewhere the user can actually click it.
    private func toggleIsReachable() -> Bool {
        if Pref.debugLogging && UserDefaults.standard.bool(forKey: "debugFakeToggleHidden") { return false }
        guard let w = toggle.button?.window, w.frame.height > 0 else { return true }  // not laid out yet
        guard let screen = w.screen ?? NSScreen.main else { return false }
        // Only the horizontal position matters: status item windows can be taller than the menu bar
        // (38pt windows in a 34pt bar at 1710x1107) and stick out above the screen while fully clickable.
        let s = screen.frame
        return w.frame.minX >= s.minX - 1 && w.frame.maxX <= s.maxX + 1 && w.frame.intersects(s)
    }

    /// If hiding ever takes the arrow itself off the menu bar (wrong order, a crowded
    /// bar, a display change…), put everything back so the user is never locked out.
    private func scheduleWatchdog() {
        watchdogWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.toggleIsReachable() else { return }
            debugLog("RESCUE: arrow is not reachable, expanding")
            self.hidingBlocked = true
            self.state = .expanded
            self.render()
            self.scheduleAutoCollapse()
            self.explainRescue()
        }
        watchdogWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    private func explainRescue() {
        guard !warnedAboutRescue else { return }
        warnedAboutRescue = true
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "\(AppInfo.name) showed your menu bar icons again"
        alert.informativeText = "Hiding was pushing \(AppInfo.name)'s own arrow off the menu bar. Hold ⌘ and drag the | separators so they sit to the left of the arrow (the arrow must be the right-most \(AppInfo.name) item), then click the arrow to hide again. Automatic hiding stays off until you click the arrow."
        alert.runModal()
    }

    private func scheduleAutoCollapse() {
        collapseTimer?.invalidate()
        collapseTimer = nil
        let delay = Pref.autoCollapseDelay
        guard state != .collapsed, delay > 0 else { return }
        collapseTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.autoCollapse()
        }
    }

    private func autoCollapse() {
        // Don't yank icons away while the pointer is in the menu bar (e.g. the user is
        // about to click a revealed icon, or one of its menus is open).
        if mouseIsInMenuBar() {
            collapseTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                self?.autoCollapse()
            }
            return
        }
        apply(.collapsed, userInitiated: false)
    }

    private func mouseIsInMenuBar() -> Bool {
        let p = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) else { return false }
        let barHeight = max(NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)
        return p.y >= screen.frame.maxY - barHeight - 1
    }

    // MARK: Order guard

    /// The item's x position relative to its screen, or nil if it isn't laid out yet.
    private func frameX(_ item: NSStatusItem) -> CGFloat? {
        guard item.isVisible, let w = item.button?.window, w.frame.height > 0 else { return nil }
        return w.frame.minX - (w.screen?.frame.minX ?? 0)
    }

    /// True when `a` is left of `b`, or when we can't tell (no layout yet).
    private func isLeft(_ a: NSStatusItem, of b: NSStatusItem) -> Bool {
        guard let ax = frameX(a), let bx = frameX(b) else { return true }
        return ax < bx
    }

    private func warnWrongOrder() {
        NSSound.beep()
        guard !warnedAboutOrder else { return }
        warnedAboutOrder = true
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "The separator is on the wrong side"
        alert.informativeText = "\(AppInfo.name) hides the icons to the left of the | separator. Hold ⌘ and drag the separator so it sits to the left of the \(AppInfo.name) arrow, then try again."
        alert.runModal()
    }

    // MARK: Debug

    func dumpFrames(_ tag: String) {
        guard Pref.debugLogging else { return }
        func d(_ n: String, _ i: NSStatusItem) -> String {
            let w = i.button?.window
            return "\(n) len=\(i.length) vis=\(i.isVisible) frame=\(w.map { NSStringFromRect($0.frame) } ?? "nil") onscreen=\(w.map { $0.occlusionState.contains(.visible) } ?? false)"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            debugLog("[\(tag)+0.5s] \(d("toggle", toggle)) | \(d("sep", separator)) | \(d("ahSep", alwaysHiddenSeparator))")
        }
    }
}
