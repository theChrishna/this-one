import SwiftUI

/// The "Notch" tab of the Preferences window.
struct NotchSettingsView: View {
    @AppStorage(NotchPrefs.Key.enabled) private var enabled = false
    @AppStorage(NotchPrefs.Key.cornersEnabled) private var cornersEnabled = true
    @AppStorage(NotchPrefs.Key.cornerRadius) private var cornerRadius = 20.0
    @AppStorage(NotchPrefs.Key.bottomCorners) private var bottomCorners = false
    @AppStorage(NotchPrefs.Key.allScreens) private var allScreens = false
    @AppStorage(NotchPrefs.Key.showInMissionControl) private var showInMissionControl = false
    @AppStorage(NotchPrefs.Key.mode) private var mode = "wallpaper"
    @AppStorage(NotchPrefs.Key.barLevel) private var storedBarLevel = 23
    private var barLevel: Binding<Int> {
        Binding(get: { min(max(storedBarLevel, NotchPrefs.barLevelRange.lowerBound), NotchPrefs.barLevelRange.upperBound) },
                set: { storedBarLevel = $0 })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Hide the notch (black menu bar)", isOn: $enabled)
                Toggle("Apply to all screens", isOn: $allScreens)
                Toggle("Keep overlays visible in Mission Control", isOn: $showInMissionControl)
                Picker("Black bar method", selection: $mode) {
                    Text("Edit wallpaper").tag("wallpaper")
                    Text("Overlay window").tag("overlay")
                }
            }
            Section("Rounded corners") {
                Toggle("Show corners under the menu bar", isOn: $cornersEnabled)
                LabeledContent("Radius") {
                    HStack {
                        Slider(value: $cornerRadius, in: 4...40, step: 1)
                        Text("\(Int(cornerRadius)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
                .disabled(!cornersEnabled)
                Toggle("Also draw corners at the bottom of the screen", isOn: $bottomCorners)
                    .disabled(!cornersEnabled)
            }
            Section("Advanced") {
                Stepper("Overlay bar window level: \(barLevel.wrappedValue)", value: barLevel, in: NotchPrefs.barLevelRange)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
