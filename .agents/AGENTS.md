# Project Rules

- **Use `mq.cmdf`**: Never use `mq.cmd(string.format(...))`. Always prefer `mq.cmdf(...)` for formatted commands.
- **Require Paths**: Do not use `pricecheck.` package prefix in `require` calls; always use direct relative imports like `modules.xxx`.
- **ImGui Tooltips**: Always wrap `ImGui.BeginTooltip()` inside a conditional block (`if ImGui.BeginTooltip() then ... end`) before rendering and calling `ImGui.EndTooltip()`.
