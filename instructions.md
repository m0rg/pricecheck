# Development Rules and Best Practices

To prevent recurring issues and keep the codebase clean, follow these guidelines when making modifications:

---

## 1. 🎛️ Command Execution (`mq.cmdf` vs. `mq.cmd`)
- **Rule**: Never use nested `mq.cmd(string.format(...))`.
- **Instruction**: Always use `mq.cmdf(...)` instead. It is cleaner, less verbose, and native to the MacroQuest Lua API.
  - 🛑 *Bad*: `mq.cmd(string.format("/plugin %s", p.name))`
  -   *Good*: `mq.cmdf("/plugin %s", p.name)`

---

## 2. 📂 Module Import Paths (No Package Prefixes)
- **Rule**: Do not use the `pricecheck.` package prefix in `require` calls.
- **Instruction**: Import modules relative to the script directory using `modules.x` directly.
  - 🛑 *Bad*: `local ui = require("pricecheck.modules.ui")`
  -   *Good*: `local ui = require("modules.ui")`

---

## 3. 🫧 Safe ImGui Tooltips
- **Rule**: Always wrap `ImGui.BeginTooltip()` calls in matching conditional checks.
- **Instruction**: ImGui stack errors and crashes occur if `ImGui.EndTooltip()` is called when the tooltip failed to begin. Always check the return value.
  - 🛑 *Bad*:
    ```lua
    ImGui.BeginTooltip()
    ImGui.Text("Tooltip text")
    ImGui.EndTooltip()
    ```
  -   *Good*:
    ```lua
    if ImGui.BeginTooltip() then
        ImGui.Text("Tooltip text")
        ImGui.EndTooltip()
    end
    ```

---

## 4. 🕒 DST-Resilient Timestamps
- **Rule**: Calculate timezone offsets dynamically using UTC-to-local differences rather than hardcoding.
- **Instruction**: Use the dynamic bias helper:
  ```lua
  local function getTimezoneBias()
      local now = os.time()
      return os.difftime(now, os.time(os.date("!*t", now)))
  end
  ```
