<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Contributing

## Development setup

NotifyPoint is a macOS app built directly with `swiftc` and `make`.

Java scripts require Java 25 or newer and run through JBang. Declare `//JAVA 25+`
in each script so JBang selects a compatible JDK. Use modern Java features where
they simplify the code.

Useful commands:

```bash
make test
make build
make debug-build
make generate-icons
make license-check
make license-fix
```

The license targets require [LicenseOps](https://licenseops.github.io/docs/getting-started/) (`lops`).

`make generate-icons` uses `rsvg-convert` and JBang to regenerate the app icon
from `src/assets/icon.svg` and the 1x/2x menu bar icons from the nine source SVGs
in `src/assets/menu-bar-icon/`. Menu bar filenames match `NotificationPosition`
values so the icon reflects the selected position.

Artifacts:

- `NotifyPoint.app`
- `.build/`

## Changelog and releases

Record notable user-facing changes under `Unreleased` in [CHANGELOG.md](CHANGELOG.md),
following [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Summarise the
behaviour and its effect on users under `Added`, `Changed`, `Deprecated`, `Removed`,
`Fixed`, or `Security`, as applicable.

For a release, update both version fields in `src/Info.plist`, move the unreleased
entries into a version section dated `YYYY-MM-DD`, and update the comparison links.
Keep an empty `Unreleased` section for the next changes. Tag the release commit as
`v<version>` and use that version's changelog entry for the GitHub release notes.

## Tests

Run the local behavior test suite with:

```bash
make test
```

The GitHub Actions workflow runs the same command on pull requests and on pushes to `master`.

## Debug build and logs

To diagnose notification placement issues, especially around wake, login, and screen topology changes, use the debug build:

```bash
make debug-build
open NotifyPoint.app
```

The debug build enables verbose tracing by default and writes logs to:

```bash
~/Library/Logs/NotifyPoint/debug.log
```

You can override runtime debug mode with:

```bash
defaults write io.github.bric3.notifypoint debugMode -bool true
defaults write io.github.bric3.notifypoint debugMode -bool false
```

Useful log commands:

```bash
tail -f ~/Library/Logs/NotifyPoint/debug.log
rg "Moved notification|Recovery retry|recovery follow-up|read failed|Failed to get notification windows|Screen locked|Screen unlocked|observer" ~/Library/Logs/NotifyPoint/debug.log
```

The regular app reads `debugMode` at launch; quit and reopen it after changing the
setting. When reporting a missed move, include its approximate time and whether
`Rerun Detection` or restarting the app restored positioning.

The trace records Accessibility error names/codes, permission status, Notification
Center and observer PIDs, the last window-created event, lock/unlock and wake
events, and position-write results with readback verification. A move is reported
as successful only when the banner position matches the target within one point.
Unrecognised notification dialogs include a sample of up to 64 Accessibility
roles/subroles and subrole read errors, without notification text.

The five-second check restores missing observers; it does not reposition existing
notifications. Failed reads, unrecognised notification windows, and unverified
moves use fast retries, then follow up every 30 seconds for up to 30 minutes.
Unlock, wake, and restored observer connections restart recovery.
Lock/unlock detection uses undocumented macOS distributed notifications;
documented workspace session and display-wake notifications remain active too.

### Menu preview mode

To inspect the menu UI without starting the Accessibility/event-handling backend, launch a separate preview instance:

```bash
open -n NotifyPoint.app --args --menu-preview
```

Preview mode:

- shows the menu and 3x3 position picker
- does not request Accessibility permissions
- does not move notifications
- does not persist picker selections
- replaces any previous preview instance

## Documentation screenshots

Regenerate the menu images with:

```bash
make screenshots
```

This requires an interactive macOS desktop, the build tools above, JBang, Java 25 or newer,
and a display with 2x backing scale and enough room for a 400 x 520 point canvas.
Allow Screen Recording and Accessibility for the terminal or agent launching the
command. Reduce transparency and Increase contrast must be off. The runner
reports missing permissions or incompatible settings without changing them.

The default captures simulate display-selector availability using the real
AppKit menu. Both scenes work on a desktop Mac: the position scene hides the
selector, and the display scene selects Laptop Display. Simulation changes the
available controls; native macOS still renders the menu and its translucency.

To use actual hardware detection:

```bash
make screenshots SCREENSHOT_ARGS=--hardware
```

In hardware mode, the position scene uses the actual menu layout. The display
scene requires a Mac laptop with its built-in display available, so it is skipped
when that display is unavailable. Existing assets and metadata for skipped scenes
are preserved.

Each scene selects Middle and captures light and dark appearances. The position
scene hovers Top Left; the display scene hovers Middle Right. Captures use a fixed
blue background with a tapered orange curve passing behind the position picker.
Dark captures use a darker blue background and warmer orange. A full-width menu
bar at the top contains the app's position icon, Wi-Fi, Control Centre, a fixed
75% battery and a fixed date/clock. These preview items exclude personal menu bar
content; the menu and pickers are the same AppKit controls used by the app.

Outputs are 800 x 1040 PNGs:

- `.github/menu-screenshot.png` and `.github/menu-screenshot-dark.png`
- `.github/menu-display-screenshot.png` and `.github/menu-display-screenshot-dark.png`

`.github/menu-screenshots.properties` records each image's macOS version/build,
scale, scene state, strategy, and capture geometry. The initial generated set uses
macOS 26.7.1 (25G241) at 2x backing scale. Exact pixels can vary across macOS versions.

The runner builds and launches a temporary app bundle with an isolated settings
file. It captures composited screen regions with `screencapture`, checks readiness,
state, bounds and dimensions, then replaces documentation assets after all
available scenes pass. It restores originals if replacement fails. Cleanup closes
only owned processes and windows and restores the pointer, including on ordinary
failure or interruption. A parent watchdog also closes abandoned preview windows.
Avoid using the pointer during capture; it is temporarily moved to establish hover.
After building, a confirmation dialog warns that capture will use the mouse for
about 20 seconds. Choose Cancel to leave the desktop and documentation assets
unchanged. A slow or failed capture can take up to two minutes to stop.
Existing app instances, preferences, wallpaper and application positions are retained.

Run the Java runner checks without capturing the desktop:

```bash
make screenshots-check
```

For visual validation, run generation twice on the same machine and compare the
four images for tint, translucency, selection, hover and cropping. Validate hardware
mode separately on a laptop. This is a local documentation workflow; real
notification screenshots remain part of the smoke test below, and unattended CI
capture is outside its scope.

The light and dark background PNGs are checked in. To regenerate them from source:

```bash
rsvg-convert --output=scripts/screenshots/background.png scripts/screenshots/background.svg
rsvg-convert --output=scripts/screenshots/background-dark.png scripts/screenshots/background-dark.svg
```

## Local smoke test

To exercise the live Notification Center path with a real notification, use the local smoke test:

```bash
make smoke-test
```

> [!NOTE]
> [`alerter`](https://github.com/vjeantet/alerter) must be installed before.
>
> ```shell
> brew install vjeantet/tap/alerter
> ```
>
> `alerter` is chosen over `terminal-notifier` because it's a native swift app that do not require `ruby`.

What it does:

- builds a fresh debug app
- writes smoke-test-only settings into an isolated JSON file
- asks before stopping any running regular NotifyPoint instance
- leaves preview instances alone
- launches the repo's `NotifyPoint.app` in `--smoke-test` mode
- sends a notification with `alerter`
- exercises the laptop-display target as well when the app reports that the built-in display is available
- checks the debug log for move activity

Useful options:

```bash
make smoke-test SMOKE_TEST_ARGS=--yes
make smoke-test SMOKE_TEST_ARGS=--no-build
```

Environment variables:

- `NOTIFYPOINT_SMOKE_SETTINGS_FILE`
- `NOTIFYPOINT_SMOKE_POSITION`
- `NOTIFYPOINT_SMOKE_DISPLAY_TARGET`
- `NOTIFYPOINT_SMOKE_TITLE`
- `NOTIFYPOINT_SMOKE_MESSAGE`
- `NOTIFYPOINT_SMOKE_SENDER`
- `NOTIFYPOINT_SMOKE_NOTIFICATION_TIMEOUT`

Notes:

- `alerter` must be installed and allowed to post notifications
- the smoke test is local-only and not suitable for CI
- the launched smoke-test instance is closed automatically when the smoke-test run finishes
- the smoke test stops the regular NotifyPoint instance before launching so the two instances do not fight over notifications
- if a regular NotifyPoint instance was running before the smoke test, that same app bundle is reopened afterward
- smoke-test preferences are isolated from the regular app by default in `${TMPDIR}/NotifyPoint.smoke-test.json`
- when the built-in display is unavailable, the laptop-display scenario is logged as skipped rather than treated as a failure

## Changing settings from the command line

NotifyPoint currently reads settings at launch from `UserDefaults`.

The regular app uses:

```bash
defaults write io.github.bric3.notifypoint notificationPosition -string deadCenter
defaults write io.github.bric3.notifypoint notificationDisplayTarget -string mainDisplay
defaults write io.github.bric3.notifypoint debugMode -bool true
```

The smoke-test mode uses a separate JSON file by default:

```bash
cat > "${TMPDIR}/NotifyPoint.smoke-test.json" <<'EOF'
{
  "debugMode": true,
  "notificationDisplayTarget": "mainDisplay",
  "notificationPosition": "deadCenter"
}
EOF
```

You can also launch any instance against an explicit file:

```bash
open -n NotifyPoint.app --args --smoke-test --settings-file "${TMPDIR}/NotifyPoint.smoke-test.json"
```

The smoke-test mode polls its JSON file and applies `notificationPosition` / `notificationDisplayTarget` changes live. The regular app still reads `UserDefaults` at launch.

## Build metadata

Builds generate metadata in `.build/BuildInfo.generated.swift` at build time. The startup log includes:

- git commit
- dirty or clean working tree state
- UTC build timestamp
- source fingerprint

This is meant to distinguish local debug builds, including builds created from uncommitted changes.

## Code signing

By default, local builds use ad-hoc signing (`-`).

That is enough to run the app locally, but macOS Accessibility permissions may need to be re-approved for rebuilt binaries.

If you want more stable local signing, save a codesign identity:

```bash
make save-codesign-identity CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
```

To clear it:

```bash
make clear-codesign-identity
```

The local identity is stored in `.codesign_identity`, which is intentionally ignored by git.

## Scope of tests

The current test suite focuses on extracted, testable logic:

- notification move policy
- Notification Center panel state policy
- retry and follow-up recovery behavior
- placement and cache behavior
- screen resolution policy
- tree traversal

The suite does not fully cover real macOS Accessibility behavior, Notification Center timing, or AppKit subscription wiring. Those still need live verification on macOS.
