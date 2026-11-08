import Cocoa
import ServiceManagement

// BarTidy: a minimal Hidden Bar style menu bar decluttering app.
//
// How it works: two status items sit in the menu bar.
//   [ icons you want hidden ]  |  [ icons you keep ]  ‹  (system icons)
//                              ^separator            ^toggle
// Collapsing makes the separator 10,000pt wide, which pushes every item to its
// left off the edge of the screen. Expanding shrinks it back.
// Cmd-drag the icons in the menu bar to choose which side of the separator they sit on.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let separatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private let normalLength: CGFloat = 16
    private let collapsedLength: CGFloat = 10_000
    private let autoCollapseDelay: TimeInterval = 15

    private var isCollapsed = false
    private var autoCollapseTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Stable names so macOS remembers the positions between launches.
        toggleItem.autosaveName = "bartidy.toggle"
        separatorItem.autosaveName = "bartidy.separator"

        if let button = toggleItem.button {
            button.target = self
            button.action = #selector(toggleClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        separatorItem.menu = nil
        applyState(collapsed: false)
        // Start collapsed shortly after launch so the bar is tidy by default.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.applyState(collapsed: true)
        }
    }

    // MARK: - Actions

    @objc private func toggleClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            applyState(collapsed: !isCollapsed)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit BarTidy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
        toggleItem.menu = nil   // so left-click keeps toggling
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("BarTidy: launch at login failed: \(error)")
        }
    }

    // MARK: - State

    private func applyState(collapsed: Bool) {
        // Safety: if the user dragged the separator to the right of the toggle,
        // collapsing would hide the toggle itself. Refuse in that case.
        if collapsed, !separatorIsLeftOfToggle() {
            NSSound.beep()
            return
        }

        isCollapsed = collapsed
        autoCollapseTimer?.invalidate()

        if collapsed {
            separatorItem.length = collapsedLength
            separatorItem.button?.image = nil
            toggleItem.button?.image = symbol("chevron.left")
        } else {
            separatorItem.length = normalLength
            separatorItem.button?.image = symbol("line.diagonal")
            toggleItem.button?.image = symbol("chevron.right")
            autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: autoCollapseDelay, repeats: false) { [weak self] _ in
                self?.applyState(collapsed: true)
            }
        }
    }

    private func separatorIsLeftOfToggle() -> Bool {
        guard let sepX = separatorItem.button?.window?.frame.origin.x,
              let togX = toggleItem.button?.window?.frame.origin.x else { return true }
        return sepX < togX
    }

    private func symbol(_ name: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        img?.isTemplate = true
        return img
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon
app.run()
