import Foundation

/// Notch settings, stored in the app's defaults under `notch.*` keys so they can't collide with the
/// menu bar settings in `Pref`. `NotchSettingsView` binds to the same keys with @AppStorage.
enum NotchPrefs {
    static let defaults = UserDefaults.standard

    enum Key {
        static let enabled = "notch.enabled"
        static let cornersEnabled = "notch.cornersEnabled"
        static let cornerRadius = "notch.cornerRadius"
        static let bottomCorners = "notch.bottomCorners"
        static let allScreens = "notch.allScreens"
        static let showInMissionControl = "notch.showInMissionControl"
        static let mode = "notch.mode"
        static let barLevel = "notch.barLevel"
        static let cleanExit = "notch.cleanExit"
        static let wallpaperRecords = "notch.wallpaperRecords"
        static let migrated = "notch.migratedFromNotchHider"
    }

    /// Bundle identifier of the standalone NotchHider app this feature replaces.
    static let legacyBundleID = "com.example.NotchHider"

    /// Off until the user turns it on: editing the wallpaper should never happen as a surprise after an update.
    static var enabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }
    static var cornersEnabled: Bool {
        get { defaults.object(forKey: Key.cornersEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.cornersEnabled) }
    }
    static var cornerRadius: Double {
        get { defaults.object(forKey: Key.cornerRadius) as? Double ?? 20 }
        set { defaults.set(newValue, forKey: Key.cornerRadius) }
    }
    static var bottomCorners: Bool {
        get { defaults.bool(forKey: Key.bottomCorners) }
        set { defaults.set(newValue, forKey: Key.bottomCorners) }
    }
    static var allScreens: Bool {
        get { defaults.bool(forKey: Key.allScreens) }
        set { defaults.set(newValue, forKey: Key.allScreens) }
    }
    /// Keep the corners / overlay bar visible in Mission Control (.stationary) instead of hiding them (.transient).
    static var showInMissionControl: Bool {
        get { defaults.bool(forKey: Key.showInMissionControl) }
        set { defaults.set(newValue, forKey: Key.showInMissionControl) }
    }
    /// "wallpaper" or "overlay"
    static var mode: String {
        get { defaults.string(forKey: Key.mode) ?? "wallpaper" }
        set { defaults.set(newValue, forKey: Key.mode) }
    }
    /// Window level of the overlay bar. 23 = just below the menu bar (kCGMainMenuWindowLevel is 24).
    /// Clamped to 21...24: on macOS 27 Mission Control's own windows use layers up to 20, so a lower bar gets
    /// covered by its blur; 24 is the menu bar itself.
    static let barLevelRange = 21...24
    static var barLevel: Int {
        get { min(max(defaults.object(forKey: Key.barLevel) as? Int ?? 23, barLevelRange.lowerBound), barLevelRange.upperBound) }
        set { defaults.set(newValue, forKey: Key.barLevel) }
    }
    /// False from launch until a clean quit; true at next launch means the previous run crashed.
    static var cleanExit: Bool? {
        get { defaults.object(forKey: Key.cleanExit) as? Bool }
        set { defaults.set(newValue, forKey: Key.cleanExit) }
    }
    /// Changes whenever a setting that affects layout changes (ignores unrelated defaults writes).
    static var signature: String {
        "\(enabled)\(cornersEnabled)\(cornerRadius)\(bottomCorners)\(allScreens)\(mode)\(barLevel)\(showInMissionControl)"
    }

    /// One-time import of the standalone NotchHider's settings. Wallpaper records aren't imported: the old app
    /// restores its wallpapers when it quits, and it is asked to quit before this runs.
    static func migrateFromLegacyAppIfNeeded() {
        guard !defaults.bool(forKey: Key.migrated) else { return }
        defaults.set(true, forKey: Key.migrated)
        guard let old = defaults.persistentDomain(forName: legacyBundleID) else { return }
        let map = ["enabled": Key.enabled, "cornersEnabled": Key.cornersEnabled, "cornerRadius": Key.cornerRadius,
                   "bottomCorners": Key.bottomCorners, "allScreens": Key.allScreens,
                   "showInMissionControl": Key.showInMissionControl, "mode": Key.mode, "barLevel": Key.barLevel]
        for (oldKey, newKey) in map {
            if let value = old[oldKey], defaults.object(forKey: newKey) == nil { defaults.set(value, forKey: newKey) }
        }
    }
}
