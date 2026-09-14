<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Contributing

## Development setup

NotifyPoint is a macOS app built directly with `swiftc` and `make`.

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

`make generate-icons` uses JBang to regenerate the app and menu-bar icons from
`src/assets/icon.png`. The editable vector artwork is `src/assets/icon.svg`.

Artifacts:

- `NotifyPoint.app`
- `.build/`

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
rg "Moved notification|Recovery retry|placeholder follow-up" ~/Library/Logs/NotifyPoint/debug.log
```

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
