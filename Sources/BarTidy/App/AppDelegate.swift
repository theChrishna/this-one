import Cocoa
import Carbon.HIToolbox
import ServiceManagement

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var bar: MenuBarController!
    private var prefs: PreferencesWindowController?
    private var hotKey: HotKey?
    private let notch = NotchController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.registerDefaults()
        bar = MenuBarController()
        bar.onShowPreferences = { [weak self] in self?.showPreferences() }
        bar.extraMenuItems = { [weak self] in self.map { [$0.notch.makeMenuItem()] } ?? [] }

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
                // object: "<length>" for the separator, "ah:<length>" for the always-hidden one
                guard let self, let arg = n.object as? String else { return }
                let isAH = arg.hasPrefix("ah:")
                guard let l = Double(isAH ? String(arg.dropFirst(3)) : arg) else { return }
                let item = isAH ? self.bar.alwaysHiddenSeparator : self.bar.separator
                item.button?.image = nil
                item.length = l
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
                forName: .init("com.krishna.bartidy.debugState"), object: nil, queue: .main
            ) { [weak self] n in
                if let st = MenuBarController.State(rawValue: n.object as? String ?? "") {
                    self?.bar.apply(st, userInitiated: true)
                }
            }
            DistributedNotificationCenter.default().addObserver(
                forName: .init("com.krishna.bartidy.debugSnapshot"), object: nil, queue: .main
            ) { [weak self] n in
                if let path = n.object as? String { self?.snapshotPreferences(to: path) }
            }
        }

        bar.collapseWhenReady()
        notch.start()
    }

    /// Always put the original wallpapers back and remove the notch overlays on quit.
    func applicationWillTerminate(_ notification: Notification) {
        notch.stop()
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
