# Changelog

All notable changes to **Hidex** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned

- Additional HID++ touchpad WPIDs beyond the documented T650 profile
- Notarized Developer ID builds (optional maintainer path)

## [2.0.5] — 2026-10-26

### Added

- 1-finger double-tap → maximize focused window (fill visible screen via Accessibility; Zoom fallback)
- Preferences: independent 1-finger vs 2-finger tap/scroll controls

### Fixed

- 2-finger scroll no longer fires right-click on lift: keep `scrollIntent` when fingers lift 2→1, path-length intent, min frames/duration for real taps, ~0.55 s cooldown against ghost re-contacts after scroll
- Stricter default 2-finger tap window (≈220 ms / move 16) so short scrolls are not classified as right-click

## [2.0.4] — 2026-10-26

### Note

Superseded by 2.0.5 (same-day tap/scroll and maximize refinements).

## [2.0.3] — 2026-10-26

### Changed

- Menu bar shows the touchpad icon only; battery % stays in the dropdown menu (not beside the icon)

### Fixed

- Soft tap / two-finger tap clicks: inject with HID-system `CGEventSource`, Quartz cursor position, and a short down→up gap (nil-source clicks were classified but ignored by WindowServer)
- Tap detection: measure displacement from start centroid; finish once per contact; relax default window to 400 ms / 64 units
- Unifying multi-device: scan all paired slots (1…6) for TouchPadRawXY `0x6100` so a Master Keys / MX Keys on the same receiver no longer blocks the T650
- Prefer classic Unifying (`0xC52B`) over Logi Bolt when both receivers are present
- Accessibility help on recent macOS: open Settings + clear manual steps when the system TCC popup never appears

## [2.0.2] — 2026-10-26

### Note

Superseded by 2.0.3 (same-day fixes bundled for release).

## [2.0.1] — 2026-10-26

### Note

Superseded by 2.0.3 (same-day fixes bundled for release).

## [2.0.0] — 2026-10-24

### Added

- Product rebrand to **Hidex** (independent brand; Logitech T650 referenced only as compatible hardware)
- Bilingual UI (Spanish default; English when the OS preferred language is English)
- Custom menu-bar icon (touchpad silhouette + charge bar) with live **battery %** title
- Version shown in the menu bar menu and About dialog (`CFBundleShortVersionString` + build)
- `CHANGELOG.md`, `VERSION`, brand research (`Docs/BRAND.md`)
- User self-sign helper `scripts/self-sign-installed.sh` for a stable local Accessibility identity
- Universal installer artifacts under Releases (`Hidex-*-universal.dmg` / `.pkg`)

### Changed

- Bundle ID → `com.jimmks7.hidex`
- Log file → `~/.hidex.log`
- Signing identity CN → `Hidex Local`
- Repository home → `https://github.com/jimmks7/Hidex`
- Documentation fully bilingual (ES first, then EN)

### Removed

- Product name “T650 Gestures” / bundle `com.t650.gestures` (breaking for Accessibility TCC entries — re-grant permissions after upgrade)

## [1.1.0] — 2026-10-24

### Added

- Universal (arm64 + x86_64) DMG/PKG packaging
- Gesture Lab, configurable 1/2-finger taps
- Dual HID++ raw mode (native 1–2 finger move/scroll + app-owned 3/4 finger gestures)
- Spaces via System Events; Mission Control via Mission Control.app
- MIT license, NOTICE, LEGAL notes

### Notes

- Published briefly under a previous account/name; superseded by Hidex 2.0.0

[Unreleased]: https://github.com/jimmks7/Hidex/compare/v2.0.5...HEAD
[2.0.5]: https://github.com/jimmks7/Hidex/releases/tag/v2.0.5
[2.0.4]: https://github.com/jimmks7/Hidex/releases/tag/v2.0.4
[2.0.3]: https://github.com/jimmks7/Hidex/releases/tag/v2.0.3
[2.0.2]: https://github.com/jimmks7/Hidex/compare/v2.0.1...v2.0.2
[2.0.1]: https://github.com/jimmks7/Hidex/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/jimmks7/Hidex/releases/tag/v2.0.0
[1.1.0]: https://github.com/jimmks7/Hidex/releases/tag/v1.1.0
