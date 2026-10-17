<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Changelog

Notable changes are recorded here using [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions are listed newest first. NotifyPoint releases start at 1.5.0; earlier
entries summarise the inherited PingPlace releases.

## [Unreleased]

## [1.5.1] - 2026-10-17

### Changed

- Larger, grey menu bar icon with a rounded notification marker that follows the selected position.
- Translucent blue position chooser with borderless zones that stay within the rounded screen surface.

### Fixed

- Restore notification detection after wake, unlock, Notification Center restarts, and Accessibility permission changes.
- Retry failed reads and unverified moves for longer, checking the resulting position before reporting success.
- Recognise grouped notification stacks while preserving Notification Center focus and widget safeguards.
- Prevent failed test compilation from running an old test binary.

### Added

- Recovery diagnostics for observer state, Accessibility errors, position readback, and unrecognised notification containers, without logging notification text.
- Editable SVG sources for all nine menu bar icon positions and PNG generation from those sources.
- This changelog and contributor guidance for maintaining release notes.

## [1.5.0] - 2026-09-14

### Added

- Graphical chooser for all nine notification positions, with hover previews.
- Laptop display targeting alongside the main display on portable Macs.
- Menu preview mode and isolated notification smoke tests.
- Automated behaviour tests, debug builds, file logging, and build metadata for troubleshooting.

### Changed

- Renamed the fork to NotifyPoint, with a new app icon and bundle identifier.
- Updated notification placement when displays connect, disconnect, wake, or change resolution.
- Split notification detection, placement, and recovery into testable components.

### Fixed

- Recover positioning after sleep, session activation, and delayed notification availability.
- Avoid moving desktop widgets or the open Notification Center panel.
- Correct display targeting and recover when Notification Center closes or loses focus.

## [1.3.2] - 2026-01-09

Inherited from [sk0gen's PingPlace fork](https://github.com/sk0gen/PingPlace/releases/tag/v1.3.2), before NotifyPoint.

### Fixed

- Restore windowed notification positioning on macOS 26 and recognise newer banner types.

### Changed

- Provide an ad-hoc signed build with configurable signing identity.

## [1.3.1] - 2025-06-15

### Fixed

- macOS 15 support, centred placement, and the Accessibility permission prompt.

## [1.3.0] - 2025-05-26

### Added

- Centre position, completing the nine notification positions.

### Fixed

- Keep Notification Center in place and reposition notifications when it closes, at launch, and after changing position.

## [1.2.0] - 2025-05-03

### Added

- Option to hide the menu bar icon.

## [1.1.0] - 2025-04-18

### Added

- Middle-left and middle-right positions and self-signed app builds.

## [1.0.1] - 2025-04-09

### Fixed

- Attempt to resolve the Accessibility permission loop.

## [1.0.0] - 2025-04-08

### Added

- Initial PingPlace release for choosing notification positions from the menu bar.

[Unreleased]: https://github.com/bric3/NotifyPoint/compare/v1.5.1...HEAD
[1.5.1]: https://github.com/bric3/NotifyPoint/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/bric3/NotifyPoint/compare/406d8103dc2e3e6bcf504e1a5ae68b72551fd2cb...v1.5.0
[1.3.2]: https://github.com/sk0gen/PingPlace/releases/tag/v1.3.2
[1.3.1]: https://github.com/NotWadeGrimridge/PingPlace/releases/tag/v1.3.1
[1.3.0]: https://github.com/NotWadeGrimridge/PingPlace/releases/tag/v1.3.0
[1.2.0]: https://github.com/NotWadeGrimridge/PingPlace/releases/tag/v1.2.0
[1.1.0]: https://github.com/NotWadeGrimridge/PingPlace/releases/tag/v1.1.0
[1.0.1]: https://github.com/NotWadeGrimridge/PingPlace/releases/tag/v1.0.1
[1.0.0]: https://github.com/NotWadeGrimridge/PingPlace/releases/tag/v1.0.0
