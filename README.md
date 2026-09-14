<!-- SPDX-License-Identifier: GPL-3.0-only -->

# NotifyPoint

Control notification position on macOS.

| Menu | Notification moved |
| --- | --- |
| ![NotifyPoint menu](.github/menu-screenshot.png)<br>![NotifyPoint display menu](.github/menu-display-screenshot.png) | ![Notification moved to top left](.github/moved-notification-to-top-left.png) |

## Fork changes

NotifyPoint is a substantially modified fork of the original [PingPlace](https://github.com/NotWadeGrimridge/PingPlace) 1.3.1. It was renamed to NotifyPoint in 2026.

- Handles system sleep and lid close
- External monitors plug/unplug, including different resolutions
- Notification Center handling when swiping right to left or toggling it
- Recovery mechanisms for delayed notification availability
- New menu with a visual position picker
- On laptops, an option to target either the Main Display or the Laptop Display
- Split code into smaller components and added tests

## Installation

Clone, build with `make build`, then copy to `/Applications` or `$HOME/Applications` folder.

XCode is needed.

Hidden settings:

- Enable debug logs:
  - `defaults write io.github.bric3.notifypoint debugMode -bool true`
- Disable debug logs:
  - `defaults write io.github.bric3.notifypoint debugMode -bool false`
- Debug log path:
  - `~/Library/Logs/NotifyPoint/debug.log`
- Set notification position:
  - `defaults write io.github.bric3.notifypoint notificationPosition -string deadCenter`
- Set notification display target:
  - `defaults write io.github.bric3.notifypoint notificationDisplayTarget -string mainDisplay`
  - `defaults write io.github.bric3.notifypoint notificationDisplayTarget -string builtInDisplay`
- Show the `Rerun Detection` menu item:
  - `defaults write io.github.bric3.notifypoint showRerunDetectionMenuItem -bool true`
- Hide the `Rerun Detection` menu item:
  - `defaults write io.github.bric3.notifypoint showRerunDetectionMenuItem -bool false`

## Usage

The app needs accessibility permissions to work. It lives in the top bar. You can set notifications to appear in nine positions:

- Top Left
- Top Center (default)
- Top Right (macOS default)
- Middle Left
- Middle Center
- Middle Right
- Bottom Left
- Bottom Center
- Bottom Right

For local development, debugging, and test workflows, see `CONTRIBUTING.md`.

## Requirements

- macOS 14 or later
- Accessibility permissions

## License

Original PingPlace app by [Wade Grimridge](https://github.com/NotWadeGrimridge/PingPlace).

NotifyPoint fork and later evolutions by bric3.

Copyright © 2025 Wade Grimridge.

Copyright © 2026 Brice Dutheil and Wojciech Gawinski.

This project is licensed under the GNU General Public License version 3 only.
See [LICENSE](LICENSE).
