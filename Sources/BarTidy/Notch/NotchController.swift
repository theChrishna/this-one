import AppKit

/// Owns the notch feature: black menu bar (wallpaper edit or overlay bar) and the concave corners.
/// Event-driven only: screen, Space, wake and wallpaper-change notifications plus settings changes.
final class NotchController: NSObject {
    private let overlays = OverlayManager()
    private let wallpaper = WallpaperManager()
    private var lastSignature = NotchPrefs.signature
    private var refreshWork: DispatchWorkItem?
    private var legacyApp: NSRunningApplication?   // KVO doesn't retain the observed object
    private var legacyQuitObservation: NSKeyValueObservation?
    private var started = false
    private var lastLog = ""

    /// Asks a still-running standalone NotchHider to quit first (it would draw a second set of overlays,
    /// and it restores its own wallpaper on quit), then starts.
    func start() {
        guard let old = NSRunningApplication.runningApplications(withBundleIdentifier: NotchPrefs.legacyBundleID).first else {
            finishStart(); return
        }
        // NSWorkspace doesn't post didTerminateApplication for LSUIElement apps, so observe the app itself.
        legacyApp = old
        legacyQuitObservation = old.observe(\.isTerminated, options: [.initial, .new]) { [weak self] app, _ in
            guard app.isTerminated else { return }
            DispatchQueue.main.async { self?.finishStart() }
        }
        debugLog("notch: asking standalone NotchHider to quit")
        old.terminate()
        // If it doesn't quit (hung, or showing an alert), start anyway rather than never.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.finishStart() }
    }

    private func finishStart() {
        guard !started else { return }
        started = true
        legacyQuitObservation = nil
        legacyApp = nil
        NotchPrefs.migrateFromLegacyAppIfNeeded()
        lastSignature = NotchPrefs.signature

        // Preferences write UserDefaults; re-apply when a notch setting changes.
        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged),
            name: UserDefaults.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(changed(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(changed(_:)),
            name: NSWorkspace.didWakeNotification, object: nil)
        // The system posts this when the desktop picture changes (undocumented; we only re-check).
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(changed(_:)),
            name: NSNotification.Name("com.apple.desktop"), object: nil)

        wallpaper.onChange = { [weak self] in self?.reconcileOverlays() }

        let crashed = NotchPrefs.cleanExit == false
        NotchPrefs.cleanExit = false
        log("launch (previous run crashed: \(crashed))")
        if crashed && wallpaper.hasGeneratedWallpaperSet { offerRecovery() }
        refresh()
    }

    /// Call from applicationWillTerminate: original wallpapers back, all overlay windows gone.
    func stop() {
        guard started else { return }
        wallpaper.restoreAll()
        overlays.removeAll()
        NotchPrefs.cleanExit = true
    }

    private func offerRecovery() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "BarTidy didn't quit cleanly"
        alert.informativeText = "A wallpaper with a black menu bar band is still set. Restore your original wallpaper now?"
        alert.addButton(withTitle: "Restore original")
        alert.addButton(withTitle: "Keep and continue")
        if alert.runModal() == .alertFirstButtonReturn {
            wallpaper.restoreAll()
            NotchPrefs.enabled = false
        }
    }

    // MARK: Coordination

    private func targets() -> [ScreenGeometry] {
        ScreenGeometry.all().filter { NotchPrefs.allScreens || $0.hasNotch }
    }

    private func barDisplays() -> Set<CGDirectDisplayID> {
        guard NotchPrefs.enabled else { return [] }
        // Overlay mode, or wallpaper mode where the wallpaper can't be edited. When overlays should survive Mission Control
        // the bar must be a window too: the wallpaper itself is blurred away there.
        if NotchPrefs.mode == "overlay" || NotchPrefs.showInMissionControl { return Set(targets().map(\.displayID)) }
        return wallpaper.needsOverlay
    }

    /// Single entry point after any event: restores, regenerates or removes things as settings dictate.
    private func refresh() {
        guard started else { return }
        if !NotchPrefs.enabled || NotchPrefs.mode == "overlay" {
            wallpaper.restoreAll()
        } else {
            wallpaper.apply(targets: targets())
        }
        reconcileOverlays()
    }

    private func reconcileOverlays() {
        let bars = barDisplays()
        overlays.reconcile(barDisplays: bars, blackDisplays: bars.union(NotchPrefs.enabled ? wallpaper.editedDisplays : []))
    }

    @objc private func prefsChanged() {
        guard NotchPrefs.signature != lastSignature else { return }
        lastSignature = NotchPrefs.signature
        refresh()
    }

    @objc private func changed(_ note: Notification) {
        log(note.name.rawValue)
        refresh()
        // Coalesced follow-up: visibleFrame and the wallpaper URL can lag the notification slightly.
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.log("\(note.name.rawValue) (+0.5s)")
            self?.refresh()
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: Menu

    /// "Notch" submenu for the arrow's right-click menu. Built fresh each time, so check marks are current.
    func makeMenuItem() -> NSMenuItem {
        let menu = NSMenu()
        for (id, text) in wallpaper.status.sorted(by: { $0.key < $1.key }) where NotchPrefs.enabled {
            let name = ScreenGeometry.all().first { $0.displayID == id }?.name ?? "Display \(id)"
            let item = NSMenuItem(title: "\(name): \(text)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }

        add(menu, "Hide the notch", #selector(toggleEnabled), on: NotchPrefs.enabled)
        add(menu, "Rounded corners", #selector(toggleCorners), on: NotchPrefs.cornersEnabled)
        add(menu, "Bottom corners too", #selector(toggleBottom), on: NotchPrefs.bottomCorners)
        add(menu, "Apply to all screens", #selector(toggleAll), on: NotchPrefs.allScreens)
        add(menu, "Keep overlays in Mission Control", #selector(toggleMissionControl), on: NotchPrefs.showInMissionControl)

        let modeMenu = NSMenu()
        for (title, value) in [("Edit wallpaper", "wallpaper"), ("Overlay window", "overlay")] {
            let i = NSMenuItem(title: title, action: #selector(setMode(_:)), keyEquivalent: "")
            i.representedObject = value; i.target = self
            i.state = NotchPrefs.mode == value ? .on : .off
            modeMenu.addItem(i)
        }
        let modeItem = NSMenuItem(title: "Black bar method", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let radiusMenu = NSMenu()
        for r in [8, 10, 12, 16, 20, 24, 28] {
            let i = NSMenuItem(title: "\(r) pt", action: #selector(setRadius(_:)), keyEquivalent: "")
            i.tag = r; i.target = self
            i.state = Double(r) == NotchPrefs.cornerRadius ? .on : .off
            radiusMenu.addItem(i)
        }
        let radiusItem = NSMenuItem(title: "Corner radius", action: nil, keyEquivalent: "")
        radiusItem.submenu = radiusMenu
        menu.addItem(radiusItem)

        menu.addItem(.separator())
        add(menu, "Restore original wallpaper", #selector(restoreWallpaper))
        add(menu, "Log screen geometry", #selector(logNow))
        add(menu, "Copy last geometry log", #selector(copyLog))

        let root = NSMenuItem(title: "Notch", action: nil, keyEquivalent: "")
        root.submenu = menu
        return root
    }

    private func add(_ menu: NSMenu, _ title: String, _ sel: Selector, on: Bool? = nil) {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        item.target = self
        if let on { item.state = on ? .on : .off }
        menu.addItem(item)
    }

    @objc private func setMode(_ item: NSMenuItem) { NotchPrefs.mode = item.representedObject as? String ?? "wallpaper"; prefsChanged() }
    @objc private func restoreWallpaper() { wallpaper.restoreAll(); NotchPrefs.enabled = false; prefsChanged() }
    @objc private func toggleEnabled() { NotchPrefs.enabled.toggle(); prefsChanged() }
    @objc private func toggleCorners() { NotchPrefs.cornersEnabled.toggle(); prefsChanged() }
    @objc private func toggleBottom() { NotchPrefs.bottomCorners.toggle(); prefsChanged() }
    @objc private func toggleMissionControl() { NotchPrefs.showInMissionControl.toggle(); prefsChanged() }
    @objc private func toggleAll() { NotchPrefs.allScreens.toggle(); prefsChanged() }
    @objc private func setRadius(_ item: NSMenuItem) { NotchPrefs.cornerRadius = Double(item.tag); prefsChanged() }

    // MARK: Geometry log

    @objc private func logNow() { log("manual", force: true) }

    @objc private func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastLog, forType: .string)
    }

    /// Keeps the latest geometry snapshot for "Copy"; prints it only with debug logging on (or when asked).
    private func log(_ reason: String, force: Bool = false) {
        let screens = ScreenGeometry.all()
        var out = "=== notch geometry [\(reason)] \(Date()) — \(screens.count) screen(s) ===\n"
        out += screens.map(\.debugDescription).joined(separator: "\n")
        lastLog = out
        if force { FileHandle.standardError.write(Data((out + "\n").utf8)) } else { debugLog(out) }
    }
}
