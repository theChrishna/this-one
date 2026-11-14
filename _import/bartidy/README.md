# BarTidy

A tiny, fast menu bar declutterer for macOS, built to feel exactly like Hidden Bar, and working on macOS 27.

```
 [ always hidden ]  ┊  [ hidden ]  |  [ always shown ]  ‹   (clock, Control Center…)
```

- **Click** the arrow to show or hide the icons left of `|`.
- **⌥-click** the arrow to also show the always-hidden icons left of `┊` (when enabled).
- **⌃⌥B** toggles from anywhere.
- **Right-click** the arrow for Preferences and Quit.
- **⌘-drag** any menu bar icon to move it between sections.
- Hidden icons collapse again by themselves after 10 seconds (configurable), but never while the pointer is in the menu bar.
- No Dock icon. Open the app again from Finder or Spotlight to get Preferences.

## Build and run

```bash
./build.sh
open BarTidy.app
```

Requires the Xcode command line tools (`xcode-select --install`). The build is a universal binary for macOS 13 and later. To keep it, move `BarTidy.app` to `/Applications` **before** turning on *Launch at login*, since the login item remembers where the app was.

## Preferences

| Setting | Default |
|---|---|
| Launch at login | off |
| Enable always-hidden section | off |
| Show separator icons | on (when off, the separators are invisible but still draggable) |
| Auto-collapse after | 10 seconds (Never, 5 s … 5 min) |

## How it works

BarTidy adds three status items: the toggle arrow, the `|` separator and the optional `┊` separator. To hide icons it makes a separator very wide, so the icons to its left no longer fit in the menu bar.

**macOS 27 changed the rules.** Status items are now laid out by the system `MenuBarAgent`, which:

1. moves items that don't fit into its own *overflow* group (with a `«` button) instead of pushing them off-screen, and
2. silently **drops any item wider than about half the screen**.

The classic 10,000pt separator (what Hidden Bar uses) hits rule 2: the separator is thrown away and nothing gets hidden. BarTidy instead uses the widest length the system still accepts, `screen width / 2 − 28` (932pt on a 1920pt display). The separator then can't fit, so it and everything to its left go into the overflow group. After each collapse BarTidy checks whether the length was rejected, and if so shrinks it and remembers a working value per screen width. macOS 26 and earlier keep the 10,000pt behaviour.

If BarTidy's separator ends up to the right of the arrow, collapsing would hide the arrow itself, so BarTidy refuses, beeps, and explains how to fix it.

## Known limitations

- **macOS 27, always-hidden section:** while expanded (not fully collapsed), macOS shows its own `«` overflow button where the always-hidden icons were. Clicking it shows those icons. Fully collapsed, there is no `«`. This is system behaviour BarTidy can't turn off.
- The hotkey is fixed to ⌃⌥B. If another app already uses that shortcut, the hotkey won't work.
- If your menu bar is crowded even when expanded, macOS 27 puts the overflow into its own `«` menu. That's the system, not BarTidy.

## Debugging

```bash
defaults write com.krishna.bartidy debugLogging -bool YES
./BarTidy.app/Contents/MacOS/BarTidy        # logs item frames and state changes to the terminal
log stream --predicate 'subsystem == "com.krishna.bartidy"'   # or watch the unified log
```

With debug logging on, BarTidy also listens for these distributed notifications so it can be scripted while testing: `com.krishna.bartidy.toggle`, `.debugState` (object `collapsed`/`expanded`/`expandedAll`), `.debugLength` (object `<pt>` or `ah:<pt>`), `.debugLoginItem` (object `on`/`off`), and `.debugSnapshot` (object: output PDF path).

## Sharing it with other people

An ad-hoc signed build (the default) only runs smoothly on the Mac that built it. You have two options.

**1. Notarized (recommended, needs the $99/year Apple Developer Program).** Recipients just unzip and open it.

```bash
# one-time
xcrun notarytool store-credentials bartidy --apple-id you@example.com --team-id TEAMID
# each release
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" tools/notarize.sh
```

This builds with the hardened runtime, submits to Apple's notary service, staples the ticket, and writes `BarTidy-1.0.zip`. Put the zip on GitHub Releases. Later you can add a Homebrew cask that points at it.

**2. Free, unsigned.** Zip `BarTidy.app` (`ditto -c -k --keepParent BarTidy.app BarTidy.zip`) and share it. Recipients will get a "can't be verified" warning. They need to try opening it once, then go to **System Settings › Privacy & Security** and click **Open Anyway**. Or, if they trust you, run `xattr -dr com.apple.quarantine /Applications/BarTidy.app`. Fine for friends, not for the public.

## Regenerating the icon

```bash
swift tools/make-icon.swift   # writes Resources/AppIcon.icns and AppIcon-1024.png
```
