import Cocoa
import ServiceManagement
import SwiftUI

// MARK: - Preferences window

final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let bar: MenuBarController
    private let loginBox = NSButton(checkboxWithTitle: "Launch BarTidy at login", target: nil, action: nil)
    private let loginNote = NSTextField(labelWithString: "")
    private let alwaysHiddenBox = NSButton(checkboxWithTitle: "Enable always-hidden section", target: nil, action: nil)
    private let separatorBox = NSButton(checkboxWithTitle: "Show separator icons", target: nil, action: nil)
    private let delayPopup = NSPopUpButton()
    private var stack: NSStackView?
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
        help.preferredMaxLayoutWidth = 380

        // Footer: version on the left, Quit on the right.
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let versionLabel = NSTextField(labelWithString: "BarTidy \(version)")
        versionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        versionLabel.textColor = .tertiaryLabelColor
        let quitButton = NSButton(title: "Quit BarTidy", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quitButton.keyEquivalent = "q"
        quitButton.keyEquivalentModifierMask = .command
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [versionLabel, spacer, quitButton])
        footer.orientation = .horizontal
        footer.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [loginBox, loginNote, alwaysHiddenBox, separatorBox, delayRow, help])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(18, after: delayRow)
        self.stack = stack
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Tab 1: the menu bar (hidden icons) settings. Tab 2: the notch settings (SwiftUI).
        let barPane = NSView()
        barPane.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: barPane.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: barPane.trailingAnchor),
            stack.topAnchor.constraint(equalTo: barPane.topAnchor),
        ])
        let notchPane = NSHostingView(rootView: NotchSettingsView())

        let tabs = NSTabView()
        for (label, view) in [("Menu Bar", barPane), ("Notch", notchPane as NSView)] {
            let item = NSTabViewItem(identifier: label)
            item.label = label
            item.view = view
            tabs.addTabViewItem(item)
        }
        tabs.translatesAutoresizingMaskIntoConstraints = false
        barPane.layoutSubtreeIfNeeded()
        let paneHeight = max(stack.fittingSize.height, notchPane.fittingSize.height)

        let content = NSView()
        content.addSubview(tabs)
        content.addSubview(footer)
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: 468),
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            // Content rect plus the tab strip and bezel.
            tabs.heightAnchor.constraint(equalToConstant: paneHeight + 44),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            footer.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 12),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
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
        // Keep the note tucked under its checkbox, but normal spacing when it's hidden.
        stack?.setCustomSpacing(loginNote.isHidden ? 10 : 2, after: loginBox)
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
