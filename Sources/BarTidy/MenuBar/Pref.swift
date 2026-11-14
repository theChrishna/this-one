import Cocoa
import os

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
