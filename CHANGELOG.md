# Changelog

## [1.1.1] - 2026-07-01

### Fixed
- **Cursor query window crash**: Fixed a crash when closing the standalone cursor query window caused by calling a non-existent method `setShowCursorQueryWindow` on the state wrapper.
- **Vulnerability/format string crash**: Fixed a potential crash in `mq.cmdf` when broadcasting item/player names containing `%` by passing them via `%s` format specifiers.

### Refactored
- **State manager setters**: Removed unused simple getters and setters (`setBulkQueue` and `setBulkPriceHistory`) and moved queue logging directly into the state metatable `__newindex` method.

## [1.1.0] - 2026-06-30

### Added
- **Visual Color Themes**: Introduced 6 UI styling presets ("Default", "Solarized Dark", "Nord", "Pastel", "Solarized Light", and "Windows 95").
- **Drop Slot & Floating Appraisals**: Querying the cursor item now opens a standalone details window showing averages, spreads, and recent transaction history tables (WTS/WTB).
- **Default Listing Price**: Support for adding items with no online price history using a configurable default price (default: 1000pp).
- **Interactive Broadcasting Timeline**: Dual progress bars showing current step countdowns (WTS lines and anti-spam delays) and overall cycle progress.
- **Cursor Grab Shortcut**: Right-click on any item in the trade history list uses `/itemnotify` to pick the item out of your inventory directly to your cursor.
- **Auto-Load Plugin Dependency**: Added startup check that dynamically installs and loads `MQ2LinkDB` if missing.
- **Release Automation**: Integrated custom GitHub Actions workflow (`redguides-publish.yml`) to automatically zip repository files and publish release tags to RedGuides.

### Changed


### Fixed

### Removed

---

## [1.0.0] - 2026-06-26

### Added
- **Core Market Appraisal**: Created connections to progression server API endpoints at `tlp-auctions.com`.
- **Frostreaver Trade Tools Tab Layout**: Built initial ImGui window with "Your Items" (bulk scanning), "Trade" (broadcast checklists and history lists), "Communication" (customer tells log), and "Configuration" (low sample warnings, custom intervals).
- **Persistent Pickled Storage**: Integrated configuration and list history persistence to `mq.configDir` using unpickle/pickle logic.
- **Offline testing harness**: Created `scratch_test.lua` mock file runner to check API integrations.
