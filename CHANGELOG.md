# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Visual Color Themes**: Introduced 6 UI styling presets ("Default", "Solarized Dark", "Nord", "Pastel", "Solarized Light", and "Windows 95").
- **Drop Slot & Floating Appraisals**: Querying the cursor item now opens a standalone details window showing averages, spreads, and recent transaction history tables (WTS/WTB).
- **Default Listing Price**: Support for adding items with no online price history using a configurable default price (default: 1000pp).
- **Interactive Broadcasting Timeline**: Dual progress bars showing current step countdowns (WTS lines and anti-spam delays) and overall cycle progress.
- **Cursor Grab Shortcut**: Right-click on any item in the trade history list uses `/itemnotify` to pick the item out of your inventory directly to your cursor.
- **Auto-Load Plugin Dependency**: Added startup check that dynamically installs and loads `MQ2LinkDB` if missing.
- **Release Automation**: Integrated custom GitHub Actions workflow (`redguides-publish.yml`) to automatically zip repository files and publish release tags to RedGuides.

### Changed
- **Modular Codebase Restructuring**: Extracted large single files into highly cohesive sub-modules under `modules/` (including `char.lua`, `chat.lua`, `dto.lua`, `http.lua`, `log.lua`, `state.lua`, `storage.lua`, `theme.lua`, `ui.lua`, and `util.lua`) utilizing Dependency Injection.
- **Asynchronous HTTP Fetching**: Restructured network query logic in `http.lua` to leverage non-blocking `lua-curl` multi-handles and background loop ticks.
- **Tell Interest Matcher**: Enhanced customer tells logger to search incoming messages against active WTS lists, highlight matches, and calculate sum totals.
- **Standardized Commands & Pathing**:
  - Replaced all nested `mq.cmd(string.format(...))` calls with clean `mq.cmdf(...)`.
  - Swapped package absolute requires to relative modules pathing.
  - Timezone calculations are now computed dynamically instead of statically defined.
- **Rounding Logic**: Rounded list prices based on average sell price (to the nearest 10 for prices $\le$ 100, nearest 50 for prices $\le$ 1000, and nearest 100 for prices > 1000).

### Fixed
- **Client Hangs / Freeze**: Corrected an infinite loop in `multi:info_read` inside `http.lua` by breaking when the easy handle is `0` or invalid.
- **Timing Cooldown Glitch**: Switched `processBroadcastQueue` logic to evaluate millisecond wall-clock checks (`mq.gettime()`) instead of raw CPU clock ticks.
- **Concurrency Modifications**: Fixed race conditions during background history filtering by making evaluations non-blocking.
- **Safe Tooltips**: Wrapped ImGui tooltips inside BeginTooltip/EndTooltip return value checks to prevent GUI stack crashes.

### Removed
- **Legacy Compatibility Wrapper**: Removed obsolete `pricecheck.lua`.
- **SetItem Features**: Completely purged obsolete `/setitem` logic and buttons.

---

## [1.0.0] - 2026-06-26

### Added
- **Core Market Appraisal**: Created connections to progression server API endpoints at `tlp-auctions.com`.
- **Frostreaver Trade Tools Tab Layout**: Built initial ImGui window with "Your Items" (bulk scanning), "Trade" (broadcast checklists and history lists), "Communication" (customer tells log), and "Configuration" (low sample warnings, custom intervals).
- **Persistent Pickled Storage**: Integrated configuration and list history persistence to `mq.configDir` using unpickle/pickle logic.
- **Offline testing harness**: Created `scratch_test.lua` mock file runner to check API integrations.
