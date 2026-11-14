# BarTidy Plus

A tiny, fast menu bar utility for macOS 27, combining two tools in one app (**BarTidy** + **NotchHider**):

- **Menu bar declutterer**, built to feel exactly like Hidden Bar.
- **Notch hider** (formerly the separate NotchHider app): paints the menu bar pure black so the notch on a MacBook blends in, with concave rounded corners under the bar so it looks like part of the bezel.

One menu bar arrow, one Preferences window (tabs **Menu Bar** and **Notch**), one login item.

```
 [ always hidden ]  ┊  [ hidden ]  |  [ always shown ]  ‹   (clock, Control Center…)
```

- **Click** the arrow to show or hide the icons left of `|`.
- **⌥-click** the arrow to also show the always-hidden icons left of `┊` (when enabled).
- **⌃⌥B** toggles from anywhere.
- **Right-click** the arrow for Preferences, the **Notch** submenu and Quit.
- **⌘-drag** any menu bar icon to move it between sections.
- Hidden icons collapse again by themselves after 10 seconds (configurable), but never while the pointer is in the menu bar.
- No Dock icon. Open the app again from Finder or Spotlight to get Preferences.

## Build and run

```bash
./build.sh
open "build.noindex/BarTidy Plus.app"
```

Requires the Xcode command line tools (`xcode-select --install`). The build is a universal binary for macOS 13 and later. `swift build` also works for development (see `Package.swift`). To keep it, copy it to `/Applications` **before** turning on *Launch at login*, since the login item remembers where the app was:

```bash
rm -rf "/Applications/BarTidy Plus.app" && cp -R "build.noindex/BarTidy Plus.app" /Applications/
```

The build goes into `build.noindex/` because Spotlight and Launchpad skip `.noindex` folders, so the build copy never shows up as a second app.

## Living next to the original apps

BarTidy Plus has its own name and bundle ID (`com.krishna.bartidyplus`), so it can be installed alongside the original **BarTidy** (`com.krishna.bartidy`) and **NotchHider** (`com.example.NotchHider`).

- **Settings:** on first launch it imports the original BarTidy's menu bar settings and NotchHider's notch settings, once. After that each app keeps its own settings.
- **Running:** only one should run at a time, or you get two arrows, a ⌃⌥B clash and doubled black bars. When BarTidy Plus starts it asks a running BarTidy or NotchHider to quit (NotchHider restores its wallpaper as it quits). You can still open either original on its own after quitting BarTidy Plus.
- **Login items:** if more than one app has *Launch at login* on, they all start and BarTidy Plus quits the others. Turn it off in the originals if you only want Plus.

## Preferences

**Menu Bar tab**

| Setting | Default |
|---|---|
| Launch at login | off |
| Enable always-hidden section | off |
| Show separator icons | on (when off, the separators are invisible but still draggable) |
| Auto-collapse after | 10 seconds (Never, 5 s … 5 min) |

**Notch tab** (also in the arrow's right-click menu under **Notch**)

| Setting | Default |
|---|---|
| Hide the notch (black menu bar) | **off** (imported from NotchHider if you used it) |
| Apply to all screens | off (only screens with a notch) |
| Keep overlays visible in Mission Control | off |
| Black bar method | Edit wallpaper (falls back to an overlay window when the wallpaper can't be edited) |
| Rounded corners / radius | on / 20 pt |
| Also draw corners at the bottom of the screen | off |
| Overlay bar window level (Advanced) | 23 (range 21–24) |

## How the menu bar hiding works

BarTidy adds three status items: the toggle arrow, the `|` separator and the optional `┊` separator. To hide icons it makes a separator very wide, so the icons to its left no longer fit in the menu bar.

**macOS 27 changed the rules.** Status items are now laid out by the system `MenuBarAgent`, which:

1. moves items that don't fit into its own *overflow* group (with a `«` button) instead of pushing them off-screen, and
2. silently **drops any item wider than about half the screen**.

The classic 10,000pt separator (what Hidden Bar uses) hits rule 2: the separator is thrown away and nothing gets hidden. BarTidy instead uses the widest length the system still accepts, `screen width / 2 − 28` (932pt on a 1920pt display). The separator then can't fit, so it and everything to its left go into the overflow group. After each collapse BarTidy checks whether the length was rejected, and if so shrinks it and remembers a working value per screen width. macOS 26 and earlier keep the 10,000pt behaviour.

If BarTidy's separator ends up to the right of the arrow, collapsing would hide the arrow itself, so BarTidy refuses, beeps, and explains how to fix it.

## How the notch hiding works

| Piece | What it does |
|---|---|
| `ScreenGeometry` | Per-display snapshot: menu bar height (`frame.maxY - visibleFrame.maxY`), `safeAreaInsets.top`, `auxiliaryTopLeft/RightArea`, notch rect. A display has a notch when the safe area is non-zero and both auxiliary areas exist. |
| `WallpaperManager` | **Edit wallpaper.** Reads the wallpaper and its options, redraws it at the screen's native pixel size using the same fill / fit / stretch / center rule, paints a black band the height of the menu bar, saves it to `~/Library/Application Support/NotchHider/` under a new filename each time (macOS caches by URL) and applies it. Originals and options are stored per display and restored on disable, restore or quit. |
| `OverlayManager` | **Overlay window** (and the fallback): a black borderless click-through window over the menu bar, plus the concave corner windows. |
| `NotchController` | Event wiring (screen changes, Space changes, wake, wallpaper-change notification), crash recovery, the Notch submenu. Event-driven, no timers. |
| `NotchSettingsView` | The Notch tab (SwiftUI). |

**Edit wallpaper falls back to the overlay bar** for wallpapers it can't edit: dynamic or multi-image HEIC, Apple built-in, stock and aerial wallpapers, folders / rotating wallpapers, and files that are missing or unreadable. The Notch submenu shows the reason per display.

**Corners** are small transparent click-through windows (four with bottom corners) that draw a black square minus a quarter circle. They are only shown on displays where the menu bar is actually black.

**Window levels (measured on macOS 27, notched MacBook).** The menu bar is a Window Server window at layer 24; status items are at 25; Mission Control uses layers up to 20 (WindowManager 14–19, Dock 20). The overlay bar defaults to level **23**: below the menu bar items, above Mission Control. Corners are at 25 and never overlap the menu bar.

**Mission Control.** By default the overlays use `.transient` collection behavior and are hidden by Mission Control. With *Keep overlays visible in Mission Control* on, they use `.stationary` and the bar is drawn as a window even in wallpaper mode (the wallpaper itself is blurred away in Mission Control).

## Project layout

```
Sources/BarTidy/
  main.swift                       entry point (accessory app, no Dock icon)
  App/AppDelegate.swift            wires both features, hotkey, debug hooks
  App/PreferencesWindowController  Preferences window with Menu Bar and Notch tabs
  MenuBar/                         Pref, MenuBarController, HotKey, LoginItem
  Notch/                           NotchController, NotchPrefs, ScreenGeometry,
                                   WallpaperManager, OverlayManager, NotchSettingsView
tools/                             make-icon.swift, notarize.sh
build.sh                           universal "BarTidy Plus.app" in build.noindex/
```

The Swift module is still called `BarTidy`. The git history of both original projects is kept: they were imported, then moved into this layout.

## Notch verification checklist (manual)

Record outcomes in the table under [Known limitations](#known-limitations).

### 1. Edit-wallpaper basics
1. Use a plain image wallpaper that exists on disk (not a dynamic, stock or Apple built-in one; avoid Downloads / Desktop / Documents unless you accept the Files & Folders prompt). Notch tab → *Hide the notch* on, *Black bar method* → Edit wallpaper.
2. Right-click the arrow → Notch: the top line should read `wallpaper edited`, and a `.jpg` should appear in `~/Library/Application Support/NotchHider/`.
3. The menu bar is black across the full width and the notch is not distinguishable. Check light **and** dark appearance: menu bar text should be white.
4. Quit BarTidy: the original wallpaper returns and the generated `.jpg` is deleted.

### 2. Lock screen (Ctrl+Cmd+Q) with the black band applied
1. With the band applied, wait about 5 seconds so macOS can refresh its lock-screen copy of the wallpaper.
2. Press **Ctrl+Cmd+Q**. BarTidy keeps running while the screen is locked.
3. Look at the very top edge of the lock screen and note each of these:
   - **a. Band present?** A solid black strip across the full width, about as tall as the notch (≈38 pt). *Yes* = the band reached the lock screen. *No* = the wallpaper image runs right up to the top edge.
   - **b. Notch hidden?** Can you still see where the notch ends, or does it disappear into the strip?
   - **c. Edge quality.** Is the strip's bottom edge crisp, or soft/blurry (the lock screen blurs the wallpaper)? Is it noticeably taller or shorter than the notch?
   - **d. Legibility.** Are the lock-screen clock, Wi-Fi and battery items readable?
   - **e. Corners.** Expect **no** concave corners (they are app windows and don't exist at the lock screen).
   - **f. Stale image?** Is it showing an old wallpaper rather than the current one?
4. Unlock. The band and corners should still be in place.
5. Switch *Black bar method* → Overlay window, lock again and repeat 3a: expect **no bar at all** (see limitations).

### 3. Login window after a restart
**Expectation to confirm:** Restart and Log Out both quit BarTidy first, and quitting restores the original wallpaper, so the login window will most likely show the **original** wallpaper with **no** band.
1. With the band applied, choose Apple menu → Restart (untick "Reopen windows when logging back in"). If auto-login is on you won't see a login window; use **Log Out** (Shift+Cmd+Q) instead.
2. At the login window, check the same items as in 2.3 (a–f).
3. Log in (with *Launch at login* on, BarTidy starts by itself). Confirm the band is regenerated.

**Variant: login window with the band left in place.**
1. With the band applied, run `pkill -9 BarTidyPlus` (kills the app without restoring).
2. Log Out, check 2.3 (a–f) at the login window, log back in.
3. Open BarTidy: the crash-recovery prompt should offer to restore the original. Accept it and confirm the original wallpaper returns.

### 4. Revert check
Quit BarTidy, lock the screen once more and confirm there is no black strip left at the top.

## Known limitations

**Menu bar hiding**

- **macOS 27, always-hidden section:** while expanded (not fully collapsed), macOS shows its own `«` overflow button where the always-hidden icons were. Clicking it shows those icons. Fully collapsed, there is no `«`. This is system behaviour BarTidy can't turn off.
- The hotkey is fixed to ⌃⌥B. If another app already uses that shortcut, the hotkey won't work.
- If your menu bar is crowded even when expanded, macOS 27 puts the overflow into its own `«` menu. That's the system, not BarTidy.

**Notch: lock screen and login window**

- **The overlay window can never appear on the lock screen or login window.** `loginwindow` draws above all app windows, so the overlay bar and the corner windows are not visible there. Only Edit wallpaper can affect what the lock screen shows, and only indirectly.
- **Edit wallpaper on the lock screen: result not recorded yet.** Fill in the table after running checklist items 2 and 3:

| Test | Band present (a) | Notch hidden (b) | Edge (c) | Legible (d) | Notes |
|---|---|---|---|---|---|
| Lock screen, Edit wallpaper (Ctrl+Cmd+Q) | _not yet tested_ | | | | |
| Lock screen, Overlay window | expected: none | | | | |
| Login window after restart / log out | _not yet tested_ (expected: original wallpaper, no band) | | | | |
| Login window with app killed (`pkill -9`) | _not yet tested_ | | | | |

- Quitting, logging out or restarting restores the original wallpaper by design, so the band is not expected at the login window unless the app is killed first.

**Notch: other**

- Menu bar text turning white relies on macOS tinting from the wallpaper under the menu bar. Expected to work with Edit wallpaper; **not yet verified** in light and dark mode. With the overlay window the tint comes from the wallpaper underneath, so on a bright wallpaper in light mode the menu text will probably be black on black.
- Whether `setDesktopImageURL` applies to every Space or only the current one is unverified. BarTidy re-checks on each Space change.
- **Apple / stock wallpapers are never edited.** For any wallpaper that isn't a plain image file (aerials, dynamic and stock Apple wallpapers, or when the chosen file is missing) macOS reports `/System/Library/CoreServices/DefaultDesktop.heic`, a symlink to the default aerial. System locations are excluded and the overlay bar is used instead. To use Edit wallpaper, pick a plain image file.
- Centered wallpapers are approximate (they depend on image DPI). "Tile" is not supported.
- Not implemented yet: hiding the notch overlays in full-screen Spaces and with an auto-hidden menu bar (currently the top corners are hidden when the menu bar height reads 0), screenshot / recording exclusion, Stage Manager and clamshell checks. The app is unsandboxed with no entitlements.

## How to fully revert the notch changes

1. Right-click the arrow → Notch → **Restore original wallpaper** (this also turns *Hide the notch* off), or just **Quit**: both put the original wallpaper and options back and remove every overlay window.
2. If the app crashed or was force-quit, open it again and choose **Restore original** in the prompt. Or set your wallpaper again in System Settings.
3. Generated images live in `~/Library/Application Support/NotchHider/`; notch settings are the `notch.*` keys in `defaults read com.krishna.bartidyplus`.

## Debugging

```bash
defaults write com.krishna.bartidyplus debugLogging -bool YES     # or pass -debugLogging YES on the command line
"build.noindex/BarTidy Plus.app/Contents/MacOS/BarTidyPlus"   # logs item frames, state changes and notch geometry
log stream --predicate 'subsystem == "com.krishna.bartidyplus"'   # or watch the unified log
```

With debug logging on, BarTidy also listens for these distributed notifications so it can be scripted while testing: `com.krishna.bartidyplus.toggle`, `.debugState` (object `collapsed`/`expanded`/`expandedAll`), `.debugLength` (object `<pt>` or `ah:<pt>`), `.debugLoginItem` (object `on`/`off`), and `.debugSnapshot` (object: output PDF path). Right-click → Notch → *Log screen geometry* prints the notch measurements.

## Sharing it with other people

An ad-hoc signed build (the default) only runs smoothly on the Mac that built it. You have two options.

**1. Notarized (recommended, needs the $99/year Apple Developer Program).** Recipients just unzip and open it.

```bash
# one-time
xcrun notarytool store-credentials bartidy --apple-id you@example.com --team-id TEAMID
# each release
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" tools/notarize.sh
```

This builds with the hardened runtime, submits to Apple's notary service, staples the ticket, and writes `BarTidyPlus-<version>.zip`. Put the zip on GitHub Releases.

**2. Free, unsigned.** Zip the app (`ditto -c -k --keepParent "build.noindex/BarTidy Plus.app" BarTidyPlus.zip`) and share it. Recipients will get a "can't be verified" warning. They need to try opening it once, then go to **System Settings › Privacy & Security** and click **Open Anyway**. Or, if they trust you, run `xattr -dr com.apple.quarantine "/Applications/BarTidy Plus.app"`.
