import Cocoa
import Carbon.HIToolbox
import ServiceManagement
import os

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

// MARK: - Preferences

enum Pref {
    private static let d = UserDefaults.standard

    static func registerDefaults() {
        d.register(defaults: [
            "autoCollapseDelay": 10.0,
            "alwaysHiddenEnabled": false,
            "showSeparator": true,
            "debugLogging": false,
        ])
    }

    /// Seconds before the hidden zone collapses again. 0 = never.
    static var autoCollapseDelay: Double {
        get { d.double(forKey: "autoCollapseDelay") }
        set { d.set(newValue, forKey: "autoCollapseDelay") }
    }
    static var alwaysHiddenEnabled: Bool {
        get { d.bool(forKey: "alwaysHiddenEnabled") }
        set { d.set(newValue, forKey: "alwaysHiddenEnabled") }
    }
    static var showSeparator: Bool {
        get { d.bool(forKey: "showSeparator") }
        set { d.set(newValue, forKey: "showSeparator") }
    }
    /// Hiding widths that MenuBarAgent accepted, keyed by screen width in points.
    static var learnedHidingLengths: [String: CGFloat] {
        get { (d.dictionary(forKey: "learnedHidingLengths") as? [String: Double])?.mapValues { CGFloat($0) } ?? [:] }
        set { d.set(newValue.mapValues { Double($0) }, forKey: "learnedHidingLengths") }
    }
    /// `defaults write com.krishna.bartidy debugLogging -bool YES`
    static var debugLogging: Bool { d.bool(forKey: "debugLogging") }
}

private let logger = Logger(subsystem: "com.krishna.bartidy", category: "bar")

func debugLog(_ message: @autoclosure () -> String) {
    guard Pref.debugLogging else { return }
    let t = Date().formatted(.dateTime.hour().minute().second().secondFraction(.fractional(3)))
    let m = "\(t) " + message()
    logger.info("\(m, privacy: .public)")
    FileHandle.standardError.write(Data((m + "\n").utf8))
}

// MARK: - Menu bar icons (template images, so they follow light/dark/tinted menu bars)

enum Icons {
    static func symbol(_ name: String, _ description: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let img = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(config)
        img?.isTemplate = true
        return img
    }

    static let collapsed = symbol("chevron.left", "Show hidden menu bar items")
    static let expanded = symbol("chevron.right", "Hide menu bar items")

    /// A thin solid vertical line.
    static let separator: NSImage = line(dashed: false)
    /// A dotted vertical line marking the always-hidden zone.
    static let alwaysHiddenSeparator: NSImage = line(dashed: true)

    private static func line(dashed: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 8, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            if dashed {
                var y: CGFloat = 1
                while y < rect.height - 1 {
                    NSBezierPath(roundedRect: NSRect(x: 3, y: y, width: 2, height: 2), xRadius: 1, yRadius: 1).fill()
                    y += 4
                }
            } else {
                NSBezierPath(roundedRect: NSRect(x: 3, y: 1, width: 2, height: 14), xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

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
    private var verifyWork: DispatchWorkItem?
    var onShowPreferences: (() -> Void)?

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
            b.setAccessibilityLabel("BarTidy")
            b.toolTip = "Click: show/hide • ⌥-click: also always-hidden • Right-click: menu • ⌃⌥B"
        }
        separator.button?.image = Icons.separator
        separator.button?.setAccessibilityLabel("BarTidy separator")
        alwaysHiddenSeparator.button?.image = Icons.alwaysHiddenSeparator
        alwaysHiddenSeparator.button?.setAccessibilityLabel("BarTidy always-hidden separator")

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
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit BarTidy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        // Attach the menu only for this click so a normal left-click keeps toggling.
        toggle.menu = menu
        toggle.button?.performClick(nil)
        toggle.menu = nil
    }

    @objc private func openPreferences() { onShowPreferences?() }

    // MARK: State

    func apply(_ requested: State, userInitiated: Bool) {
        debugLog("apply \(requested.rawValue) user=\(userInitiated) from=\(state.rawValue)")
        var target = requested
        if target == .expandedAll && !Pref.alwaysHiddenEnabled { target = .expanded }

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
        render()
        scheduleAutoCollapse()
    }

    private func render() {
        let hideAlwaysHiddenZone = Pref.alwaysHiddenEnabled && state != .expandedAll
            && isLeft(alwaysHiddenSeparator, of: separator)

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
            if state == .collapsed || hideAlwaysHiddenZone {
                alwaysHiddenSeparator.button?.image = nil
                alwaysHiddenSeparator.length = hidingLength
            } else {
                alwaysHiddenSeparator.button?.image = Pref.showSeparator ? Icons.alwaysHiddenSeparator : nil
                alwaysHiddenSeparator.length = Pref.showSeparator ? NSStatusItem.variableLength : Self.invisibleSeparatorLength
            }
        }
        debugLog("render state=\(state.rawValue)")
        dumpFrames("render")
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
        alert.informativeText = "BarTidy hides the icons to the left of the | separator. Hold ⌘ and drag the separator so it sits to the left of the BarTidy arrow, then try again."
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

// MARK: - Global hotkey (Carbon; needs no Accessibility permission)

final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &spec, me, &handlerRef)
        guard installed == noErr else { return nil }

        let id = EventHotKeyID(signature: OSType(0x4254_4459) /* 'BTDY' */, id: 1)
        let registered = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == noErr else {
            debugLog("RegisterEventHotKey failed: \(registered)")
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

// MARK: - Launch at login

enum LoginItem {
    static var isEnabled: Bool {
        let s = SMAppService.mainApp.status
        return s == .enabled || s == .requiresApproval
    }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

// MARK: - Preferences window

final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let bar: MenuBarController
    private let loginBox = NSButton(checkboxWithTitle: "Launch BarTidy at login", target: nil, action: nil)
    private let loginNote = NSTextField(labelWithString: "")
    private let alwaysHiddenBox = NSButton(checkboxWithTitle: "Enable always-hidden section", target: nil, action: nil)
    private let separatorBox = NSButton(checkboxWithTitle: "Show separator icons", target: nil, action: nil)
    private let delayPopup = NSPopUpButton()
    private static let delays: [(String, Double)] = [
        ("Never", 0), ("5 seconds", 5), ("10 seconds", 10), ("15 seconds", 15),
        ("30 seconds", 30), ("1 minute", 60), ("5 minutes", 300),
    ]

    init(bar: MenuBarController) {
        self.bar = bar
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 10),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "BarTidy Preferences"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildUI() {
        for b in [loginBox, alwaysHiddenBox, separatorBox] { b.target = self; b.action = #selector(changed(_:)) }
        loginNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        loginNote.textColor = .secondaryLabelColor

        for (title, _) in Self.delays { delayPopup.addItem(withTitle: title) }
        delayPopup.target = self
        delayPopup.action = #selector(changed(_:))
        let delayLabel = NSTextField(labelWithString: "Auto-collapse after:")
        let delayRow = NSStackView(views: [delayLabel, delayPopup])
        delayRow.spacing = 8

        let help = NSTextField(wrappingLabelWithString:
            "Click the arrow to show or hide icons, or press ⌃⌥B anywhere.\n" +
            "⌥-click the arrow to also show the always-hidden section.\n" +
            "Hold ⌘ and drag menu bar icons to move them between sections: " +
            "icons left of | are hidden, icons left of ┊ are always hidden.")
        help.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        help.textColor = .secondaryLabelColor
        help.preferredMaxLayoutWidth = 372

        let stack = NSStackView(views: [loginBox, loginNote, alwaysHiddenBox, separatorBox, delayRow, help])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(2, after: loginBox)
        stack.setCustomSpacing(18, after: delayRow)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: 420),
        ])
        window?.contentView = content
        content.layoutSubtreeIfNeeded()
        window?.setContentSize(content.fittingSize)
    }

    func refresh() {
        loginBox.state = LoginItem.isEnabled ? .on : .off
        loginNote.stringValue = LoginItem.needsApproval
            ? "Waiting for approval in System Settings › General › Login Items."
            : ""
        loginNote.isHidden = loginNote.stringValue.isEmpty
        alwaysHiddenBox.state = Pref.alwaysHiddenEnabled ? .on : .off
        separatorBox.state = Pref.showSeparator ? .on : .off
        let delay = Pref.autoCollapseDelay
        let index = Self.delays.firstIndex(where: { $0.1 == delay }) ?? 2
        delayPopup.selectItem(at: index)
    }

    @objc private func changed(_ sender: Any) {
        switch sender as AnyObject {
        case let b as NSButton where b === loginBox:
            do {
                try LoginItem.set(b.state == .on)
                if LoginItem.needsApproval { SMAppService.openSystemSettingsLoginItems() }
            } catch {
                let alert = NSAlert(error: error)
                alert.messageText = "Couldn't change the login item"
                alert.runModal()
            }
        case let b as NSButton where b === alwaysHiddenBox:
            Pref.alwaysHiddenEnabled = b.state == .on
            bar.preferencesChanged()
        case let b as NSButton where b === separatorBox:
            Pref.showSeparator = b.state == .on
            bar.preferencesChanged()
        case let p as NSPopUpButton where p === delayPopup:
            Pref.autoCollapseDelay = Self.delays[max(0, p.indexOfSelectedItem)].1
            bar.preferencesChanged()
        default: break
        }
        refresh()
    }

    func show() {
        refresh()
        if window?.isVisible != true { window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) { refresh() }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var bar: MenuBarController!
    private var prefs: PreferencesWindowController?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.registerDefaults()
        bar = MenuBarController()
        bar.onShowPreferences = { [weak self] in self?.showPreferences() }

        // ⌃⌥B toggles from anywhere.
        hotKey = HotKey(keyCode: kVK_ANSI_B, modifiers: controlKey | optionKey) { [weak self] in
            self?.bar.toggleHidden()
        }
        if hotKey == nil { NSLog("BarTidy: could not register ⌃⌥B (already taken by another app?)") }

        if Pref.debugLogging {
            // Lets scripts drive the app while debugging.
            DistributedNotificationCenter.default().addObserver(
                forName: .init("com.krishna.bartidy.toggle"), object: nil, queue: .main
            ) { [weak self] _ in self?.bar.toggleHidden() }
            DistributedNotificationCenter.default().addObserver(
                forName: .init("com.krishna.bartidy.debugLength"), object: nil, queue: .main
            ) { [weak self] n in
                guard let self, let l = Double(n.object as? String ?? "") else { return }
                self.bar.separator.button?.image = nil
                self.bar.separator.length = l
                self.bar.dumpFrames("debugLength \(l)")
            }
            DistributedNotificationCenter.default().addObserver(
                forName: .init("com.krishna.bartidy.debugLoginItem"), object: nil, queue: .main
            ) { n in
                let on = (n.object as? String) == "on"
                do { try LoginItem.set(on) } catch { debugLog("login item error: \(error)") }
                debugLog("login item set \(on) -> status \(SMAppService.mainApp.status.rawValue) enabled=\(LoginItem.isEnabled) needsApproval=\(LoginItem.needsApproval)")
            }
            DistributedNotificationCenter.default().addObserver(
                forName: .init("com.krishna.bartidy.debugSnapshot"), object: nil, queue: .main
            ) { [weak self] n in
                if let path = n.object as? String { self?.snapshotPreferences(to: path) }
            }
        }

        bar.collapseWhenReady()
    }

    /// Opening the app again from Finder/Spotlight shows Preferences, as there is no Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreferences()
        return false
    }

    /// Debug: render the Preferences window to a PNG (works while the screen is locked).
    func snapshotPreferences(to path: String) {
        showPreferences()
        guard let view = prefs?.window?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        try? view.dataWithPDF(inside: view.bounds).write(to: URL(fileURLWithPath: path))
        debugLog("snapshot \(NSStringFromRect(view.bounds)) -> \(path)")
    }

    private func showPreferences() {
        if prefs == nil { prefs = PreferencesWindowController(bar: bar) }
        prefs?.show()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon
app.run()
