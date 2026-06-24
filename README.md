# EverQuest MacroQuest PriceCheck

An in-game market checking, bulk inventory evaluation, and sales broadcasting assistant for EverQuest Time-Locked Progression (TLP) servers, built for the MacroQuest Lua Sandbox.

---
## 🤖 AI-Assisted Development
> [!NOTE]
> This codebase was developed with heavy AI assistance. All major features, bug fixes, architecture splits, safety error-resiliency wrappers (`pcall`s), and ImGui layout designs were codeveloped, refactored, and audited in collaboration with **Antigravity**, Google DeepMind's agentic coding AI.

## 🚀 Intent & Core Purpose
**PriceCheck** acts as your personal merchant companion in EverQuest. It connects directly to live progression market API endpoints (`tlp-auctions.com`) to evaluate item values, log user tells, and automate broadcast marketing (`/auction`) with human-like timing delay debounces. It ensures you never undersell valuable loot to NPC merchants or buy items at inflated prices.

---

## ✨ Features
* **Individual Market Queries**: Drag items to the Drop Slot or query them to view live statistical analytics (Average Sell/Buy, High/Low WTS/WTB, and sample counts).
* **Automated Sales Broadcaster**: Select checked items from your history, set custom listed plat prices, and queue multi-line broadcasts with customizable random debounce delays (default 400-600ms) to evade chat filters.
* **Bulk Inventory Scanner**: Instantly evaluate your current bags on startup or demand. The scanner pulls median prices, compares them with merchant values (Value), and highlights vendor-profitable items in gold/green.
* **Lootly/SetItem Quick Sells**: Profitable vendor items show a `/setitem sell` button to automate quick offloads.
* **Tells Logger & Quick Reply**: Keeps a clean history tab of incoming Tells. It dynamically parses messages, highlights match interest in your listed items with sum totals, and supports custom quick replies (e.g., `"Sure, near Parcel"`).
* **Sample Size Alerts**: Displays warning icons `[!]` with informative tooltips next to entries with low price samples (configurable threshold).
* **Configuration Suite**: Adjust safety thresholds, debounce timings, and default replies inside a green-styled Configuration dashboard, automatically persisted to local JSON files.

---



---

## 📦 Installation & Setup

1. Copy the `pricecheck` folder contents into your MacroQuest directory:
   ```text
   <MacroQuest_Directory>/lua/pricecheck/
   ```
2. Make sure the folder contains:
   * `init.lua` (Core controller)
   * `ui.lua` (ImGui Render layout)
   * `http.lua` (API communications)
   * `pricecheck.lua` (Compatibility wrapper)
3. Launch EverQuest and start the script:
   ```text
   /lua run pricecheck
   ```

---

## 🧪 Offline Testing
To verify network connectivity and parsing logic without launching the game client, run the mock environment runner from your terminal:
```bash
lua scratch_test.lua
```
This runs a mock EverQuest environment that outputs HTTP transaction results directly to the console.
