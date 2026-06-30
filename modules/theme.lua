local ImGui = require("ImGui")

local theme = {
	text = {},
	style = {},
	globalColors = {},
}

local presets = {
	["Default"] = {
		text = {
			success = { 0.06, 0.73, 0.51, 1.0 }, -- Mint Green
			info = { 0.23, 0.51, 0.96, 1.0 }, -- Modern Blue
			warning = { 0.96, 0.62, 0.04, 1.0 }, -- Amber
			error = { 0.94, 0.27, 0.27, 1.0 }, -- Rose Red
			muted = { 0.61, 0.64, 0.69, 1.0 }, -- Slate Gray
			disabled = { 0.42, 0.45, 0.50, 1.0 }, -- Dark Slate Gray
			gold = { 0.92, 0.70, 0.03, 1.0 }, -- Gold
			green = { 0.06, 0.73, 0.51, 1.0 }, -- Emerald Green
			orange = { 0.98, 0.45, 0.09, 1.0 }, -- Orange
		},
		style = {
			buttonCheck = { bg = { 0.02, 0.59, 0.41, 1.0 } },
			buttonCheckDisabled = { bg = { 0.22, 0.25, 0.32, 0.5 } },
			buttonDanger = {
				bg = { 0.86, 0.15, 0.15, 1.0 },
				hovered = { 0.94, 0.27, 0.27, 1.0 },
				active = { 0.73, 0.11, 0.11, 1.0 },
			},
			buttonRemove = {
				bg = { 0.86, 0.15, 0.15, 1.0 },
				hovered = { 0.94, 0.27, 0.27, 1.0 },
				active = { 0.73, 0.11, 0.11, 1.0 },
			},
			buttonDone = {
				bg = { 0.02, 0.59, 0.41, 1.0 },
				hovered = { 0.06, 0.73, 0.51, 1.0 },
				active = { 0.02, 0.47, 0.34, 1.0 },
			},
			tabConfig = {
				bg = { 0.06, 0.46, 0.43, 0.8 },
				hovered = { 0.05, 0.58, 0.53, 0.8 },
				active = { 0.08, 0.72, 0.65, 0.8 },
			},
			summaryFrame = { bg = { 0.09, 0.09, 0.11, 1.0 } },
		},
		globalColors = {
			{ ImGuiCol.WindowBg, { 0.08, 0.08, 0.10, 1.0 } },
			{ ImGuiCol.TitleBg, { 0.11, 0.11, 0.13, 1.0 } },
			{ ImGuiCol.TitleBgActive, { 0.15, 0.15, 0.18, 1.0 } },
			{ ImGuiCol.FrameBg, { 0.13, 0.13, 0.16, 1.0 } },
			{ ImGuiCol.FrameBgHovered, { 0.18, 0.18, 0.22, 1.0 } },
			{ ImGuiCol.FrameBgActive, { 0.22, 0.22, 0.28, 1.0 } },
			{ ImGuiCol.Button, { 0.18, 0.38, 0.90, 1.0 } },
			{ ImGuiCol.ButtonHovered, { 0.25, 0.45, 0.97, 1.0 } },
			{ ImGuiCol.ButtonActive, { 0.12, 0.31, 0.77, 1.0 } },
			{ ImGuiCol.Tab, { 0.11, 0.11, 0.13, 1.0 } },
			{ ImGuiCol.TabHovered, { 0.18, 0.18, 0.22, 1.0 } },
			{ ImGuiCol.TabActive, { 0.18, 0.38, 0.90, 1.0 } },
			{ ImGuiCol.Header, { 0.11, 0.11, 0.13, 1.0 } },
			{ ImGuiCol.HeaderHovered, { 0.18, 0.18, 0.22, 1.0 } },
			{ ImGuiCol.HeaderActive, { 0.22, 0.22, 0.28, 1.0 } },
			{ ImGuiCol.Separator, { 0.18, 0.18, 0.22, 1.0 } },
			{ ImGuiCol.Border, { 0.18, 0.18, 0.22, 1.0 } },
			{ ImGuiCol.ScrollbarBg, { 0.06, 0.06, 0.08, 1.0 } },
			{ ImGuiCol.ScrollbarGrab, { 0.18, 0.18, 0.22, 1.0 } },
			{ ImGuiCol.ScrollbarGrabHovered, { 0.25, 0.25, 0.30, 1.0 } },
			{ ImGuiCol.ScrollbarGrabActive, { 0.30, 0.30, 0.38, 1.0 } },
			{ ImGuiCol.Text, { 0.95, 0.95, 0.98, 1.0 } },
			{ ImGuiCol.TextDisabled, { 0.55, 0.55, 0.60, 1.0 } },
			{ ImGuiCol.CheckMark, { 0.18, 0.38, 0.90, 1.0 } },
		}
	},
	["Solarized Dark"] = {
		text = {
			success = { 0.52, 0.60, 0.00, 1.0 }, -- Green
			info = { 0.15, 0.55, 0.82, 1.0 }, -- Blue
			warning = { 0.71, 0.54, 0.00, 1.0 }, -- Yellow
			error = { 0.86, 0.20, 0.18, 1.0 }, -- Red
			muted = { 0.35, 0.43, 0.46, 1.0 }, -- Base01
			disabled = { 0.35, 0.43, 0.46, 1.0 },
			gold = { 0.71, 0.54, 0.00, 1.0 },
			green = { 0.52, 0.60, 0.00, 1.0 },
			orange = { 0.80, 0.29, 0.09, 1.0 },
		},
		style = {
			buttonCheck = { bg = { 0.16, 0.63, 0.60, 1.0 } }, -- Cyan
			buttonCheckDisabled = { bg = { 0.03, 0.21, 0.26, 0.5 } },
			buttonDanger = {
				bg = { 0.86, 0.20, 0.18, 1.0 },
				hovered = { 0.90, 0.30, 0.28, 1.0 },
				active = { 0.70, 0.15, 0.13, 1.0 },
			},
			buttonRemove = {
				bg = { 0.86, 0.20, 0.18, 1.0 },
				hovered = { 0.90, 0.30, 0.28, 1.0 },
				active = { 0.70, 0.15, 0.13, 1.0 },
			},
			buttonDone = {
				bg = { 0.52, 0.60, 0.00, 1.0 },
				hovered = { 0.60, 0.70, 0.00, 1.0 },
				active = { 0.40, 0.50, 0.00, 1.0 },
			},
			tabConfig = {
				bg = { 0.42, 0.44, 0.77, 0.8 },
				hovered = { 0.52, 0.54, 0.87, 0.8 },
				active = { 0.32, 0.34, 0.67, 0.8 },
			},
			summaryFrame = { bg = { 0.00, 0.17, 0.21, 1.0 } },
		},
		globalColors = {
			{ ImGuiCol.WindowBg, { 0.00, 0.17, 0.21, 1.0 } }, -- Base03
			{ ImGuiCol.TitleBg, { 0.03, 0.21, 0.26, 1.0 } }, -- Base02
			{ ImGuiCol.TitleBgActive, { 0.03, 0.21, 0.26, 1.0 } },
			{ ImGuiCol.FrameBg, { 0.03, 0.21, 0.26, 1.0 } },
			{ ImGuiCol.FrameBgHovered, { 0.05, 0.27, 0.33, 1.0 } },
			{ ImGuiCol.FrameBgActive, { 0.07, 0.32, 0.40, 1.0 } },
			{ ImGuiCol.Button, { 0.15, 0.55, 0.82, 1.0 } }, -- Blue
			{ ImGuiCol.ButtonHovered, { 0.20, 0.65, 0.92, 1.0 } },
			{ ImGuiCol.ButtonActive, { 0.10, 0.45, 0.72, 1.0 } },
			{ ImGuiCol.Tab, { 0.03, 0.21, 0.26, 1.0 } },
			{ ImGuiCol.TabHovered, { 0.05, 0.27, 0.33, 1.0 } },
			{ ImGuiCol.TabActive, { 0.15, 0.55, 0.82, 1.0 } },
			{ ImGuiCol.Header, { 0.03, 0.21, 0.26, 1.0 } },
			{ ImGuiCol.HeaderHovered, { 0.05, 0.27, 0.33, 1.0 } },
			{ ImGuiCol.HeaderActive, { 0.07, 0.32, 0.40, 1.0 } },
			{ ImGuiCol.Separator, { 0.35, 0.43, 0.46, 1.0 } }, -- Base01
			{ ImGuiCol.Border, { 0.35, 0.43, 0.46, 1.0 } },
			{ ImGuiCol.ScrollbarBg, { 0.00, 0.11, 0.15, 1.0 } },
			{ ImGuiCol.ScrollbarGrab, { 0.03, 0.21, 0.26, 1.0 } },
			{ ImGuiCol.ScrollbarGrabHovered, { 0.05, 0.27, 0.33, 1.0 } },
			{ ImGuiCol.ScrollbarGrabActive, { 0.07, 0.32, 0.40, 1.0 } },
			{ ImGuiCol.Text, { 0.51, 0.58, 0.59, 1.0 } }, -- Base0
			{ ImGuiCol.TextDisabled, { 0.35, 0.43, 0.46, 1.0 } }, -- Base01
			{ ImGuiCol.CheckMark, { 0.16, 0.63, 0.60, 1.0 } }, -- Cyan
		}
	},
	["Nord"] = {
		text = {
			success = { 0.63, 0.74, 0.55, 1.0 }, -- Nord Green
			info = { 0.53, 0.75, 0.82, 1.0 }, -- Nord Ice Blue
			warning = { 0.92, 0.80, 0.55, 1.0 }, -- Nord Gold
			error = { 0.75, 0.38, 0.42, 1.0 }, -- Nord Red
			muted = { 0.50, 0.54, 0.62, 1.0 },
			disabled = { 0.30, 0.34, 0.42, 1.0 },
			gold = { 0.92, 0.80, 0.55, 1.0 },
			green = { 0.63, 0.74, 0.55, 1.0 },
			orange = { 0.82, 0.53, 0.44, 1.0 },
		},
		style = {
			buttonCheck = { bg = { 0.56, 0.74, 0.73, 1.0 } }, -- Nord7
			buttonCheckDisabled = { bg = { 0.23, 0.26, 0.32, 0.5 } },
			buttonDanger = {
				bg = { 0.75, 0.38, 0.42, 1.0 },
				hovered = { 0.80, 0.44, 0.48, 1.0 },
				active = { 0.65, 0.32, 0.36, 1.0 },
			},
			buttonRemove = {
				bg = { 0.75, 0.38, 0.42, 1.0 },
				hovered = { 0.80, 0.44, 0.48, 1.0 },
				active = { 0.65, 0.32, 0.36, 1.0 },
			},
			buttonDone = {
				bg = { 0.63, 0.74, 0.55, 1.0 },
				hovered = { 0.70, 0.82, 0.60, 1.0 },
				active = { 0.55, 0.68, 0.48, 1.0 },
			},
			tabConfig = {
				bg = { 0.71, 0.56, 0.68, 0.8 }, -- Nord15 Purple
				hovered = { 0.77, 0.62, 0.74, 0.8 },
				active = { 0.61, 0.48, 0.58, 0.8 },
			},
			summaryFrame = { bg = { 0.18, 0.20, 0.25, 1.0 } },
		},
		globalColors = {
			{ ImGuiCol.WindowBg, { 0.18, 0.20, 0.25, 1.0 } }, -- Nord0
			{ ImGuiCol.TitleBg, { 0.23, 0.26, 0.32, 1.0 } }, -- Nord1
			{ ImGuiCol.TitleBgActive, { 0.23, 0.26, 0.32, 1.0 } },
			{ ImGuiCol.FrameBg, { 0.26, 0.30, 0.37, 1.0 } }, -- Nord2
			{ ImGuiCol.FrameBgHovered, { 0.30, 0.34, 0.42, 1.0 } }, -- Nord3
			{ ImGuiCol.FrameBgActive, { 0.35, 0.39, 0.48, 1.0 } },
			{ ImGuiCol.Button, { 0.37, 0.51, 0.68, 1.0 } }, -- Nord10
			{ ImGuiCol.ButtonHovered, { 0.43, 0.58, 0.76, 1.0 } },
			{ ImGuiCol.ButtonActive, { 0.30, 0.43, 0.58, 1.0 } },
			{ ImGuiCol.Tab, { 0.23, 0.26, 0.32, 1.0 } },
			{ ImGuiCol.TabHovered, { 0.26, 0.30, 0.37, 1.0 } },
			{ ImGuiCol.TabActive, { 0.37, 0.51, 0.68, 1.0 } },
			{ ImGuiCol.Header, { 0.23, 0.26, 0.32, 1.0 } },
			{ ImGuiCol.HeaderHovered, { 0.26, 0.30, 0.37, 1.0 } },
			{ ImGuiCol.HeaderActive, { 0.30, 0.34, 0.42, 1.0 } },
			{ ImGuiCol.Separator, { 0.30, 0.34, 0.42, 1.0 } },
			{ ImGuiCol.Border, { 0.26, 0.30, 0.37, 1.0 } },
			{ ImGuiCol.ScrollbarBg, { 0.15, 0.17, 0.21, 1.0 } },
			{ ImGuiCol.ScrollbarGrab, { 0.26, 0.30, 0.37, 1.0 } },
			{ ImGuiCol.ScrollbarGrabHovered, { 0.30, 0.34, 0.42, 1.0 } },
			{ ImGuiCol.ScrollbarGrabActive, { 0.35, 0.39, 0.48, 1.0 } },
			{ ImGuiCol.Text, { 0.85, 0.87, 0.91, 1.0 } }, -- Nord4
			{ ImGuiCol.TextDisabled, { 0.50, 0.54, 0.62, 1.0 } },
			{ ImGuiCol.CheckMark, { 0.53, 0.75, 0.82, 1.0 } }, -- Nord8
		}
	},
	["Pastel"] = {
		text = {
			success = { 0.45, 0.75, 0.68, 1.0 }, -- Soft Mint
			info = { 0.50, 0.70, 0.70, 1.0 }, -- Soft Sky Blue
			warning = { 0.95, 0.75, 0.65, 1.0 }, -- Soft Peach
			error = { 0.90, 0.60, 0.65, 1.0 }, -- Soft Rose
			muted = { 0.60, 0.58, 0.62, 1.0 },
			disabled = { 0.60, 0.58, 0.62, 1.0 },
			gold = { 0.95, 0.85, 0.55, 1.0 },
			green = { 0.45, 0.75, 0.68, 1.0 },
			orange = { 0.90, 0.65, 0.55, 1.0 },
		},
		style = {
			buttonCheck = { bg = { 0.53, 0.81, 0.74, 1.0 } },
			buttonCheckDisabled = { bg = { 0.90, 0.88, 0.92, 0.5 } },
			buttonDanger = {
				bg = { 0.90, 0.60, 0.65, 1.0 },
				hovered = { 0.95, 0.65, 0.70, 1.0 },
				active = { 0.80, 0.50, 0.55, 1.0 },
			},
			buttonRemove = {
				bg = { 0.90, 0.60, 0.65, 1.0 },
				hovered = { 0.95, 0.65, 0.70, 1.0 },
				active = { 0.80, 0.50, 0.55, 1.0 },
			},
			buttonDone = {
				bg = { 0.45, 0.75, 0.68, 1.0 },
				hovered = { 0.50, 0.80, 0.73, 1.0 },
				active = { 0.40, 0.70, 0.63, 1.0 },
			},
			tabConfig = {
				bg = { 0.77, 0.68, 0.84, 0.8 },
				hovered = { 0.83, 0.74, 0.90, 0.8 },
				active = { 0.69, 0.60, 0.77, 0.8 },
			},
			summaryFrame = { bg = { 0.95, 0.93, 0.96, 1.0 } },
		},
		globalColors = {
			{ ImGuiCol.WindowBg, { 0.96, 0.94, 0.98, 1.0 } }, -- Soft Lavender
			{ ImGuiCol.TitleBg, { 0.90, 0.88, 0.92, 1.0 } },
			{ ImGuiCol.TitleBgActive, { 0.88, 0.85, 0.90, 1.0 } },
			{ ImGuiCol.FrameBg, { 0.98, 0.99, 0.97, 1.0 } },
			{ ImGuiCol.FrameBgHovered, { 0.94, 0.92, 0.96, 1.0 } },
			{ ImGuiCol.FrameBgActive, { 0.90, 0.88, 0.92, 1.0 } },
			{ ImGuiCol.Button, { 0.77, 0.68, 0.84, 1.0 } }, -- Soft Purple
			{ ImGuiCol.ButtonHovered, { 0.84, 0.75, 0.90, 1.0 } },
			{ ImGuiCol.ButtonActive, { 0.69, 0.60, 0.77, 1.0 } },
			{ ImGuiCol.Tab, { 0.90, 0.88, 0.92, 1.0 } },
			{ ImGuiCol.TabHovered, { 0.94, 0.92, 0.96, 1.0 } },
			{ ImGuiCol.TabActive, { 0.77, 0.68, 0.84, 1.0 } },
			{ ImGuiCol.Header, { 0.90, 0.88, 0.92, 1.0 } },
			{ ImGuiCol.HeaderHovered, { 0.94, 0.92, 0.96, 1.0 } },
			{ ImGuiCol.HeaderActive, { 0.88, 0.85, 0.90, 1.0 } },
			{ ImGuiCol.Separator, { 0.88, 0.85, 0.90, 1.0 } },
			{ ImGuiCol.Border, { 0.88, 0.85, 0.90, 1.0 } },
			{ ImGuiCol.ScrollbarBg, { 0.96, 0.94, 0.98, 1.0 } },
			{ ImGuiCol.ScrollbarGrab, { 0.90, 0.88, 0.92, 1.0 } },
			{ ImGuiCol.ScrollbarGrabHovered, { 0.84, 0.82, 0.86, 1.0 } },
			{ ImGuiCol.ScrollbarGrabActive, { 0.77, 0.75, 0.80, 1.0 } },
			{ ImGuiCol.Text, { 0.18, 0.15, 0.21, 1.0 } }, -- Charcoal
			{ ImGuiCol.TextDisabled, { 0.55, 0.52, 0.58, 1.0 } },
			{ ImGuiCol.CheckMark, { 0.77, 0.68, 0.84, 1.0 } },
		}
	},
	["Solarized Light"] = {
		text = {
			success = { 0.35, 0.45, 0.00, 1.0 }, -- Green
			info = { 0.10, 0.45, 0.72, 1.0 }, -- Blue
			warning = { 0.60, 0.45, 0.00, 1.0 }, -- Yellow
			error = { 0.75, 0.10, 0.10, 1.0 }, -- Red
			muted = { 0.50, 0.55, 0.55, 1.0 },
			disabled = { 0.50, 0.55, 0.55, 1.0 },
			gold = { 0.60, 0.45, 0.00, 1.0 },
			green = { 0.35, 0.45, 0.00, 1.0 },
			orange = { 0.70, 0.20, 0.00, 1.0 },
		},
		style = {
			buttonCheck = { bg = { 0.10, 0.50, 0.48, 1.0 } }, -- Cyan
			buttonCheckDisabled = { bg = { 0.90, 0.88, 0.80, 0.5 } },
			buttonDanger = {
				bg = { 0.75, 0.10, 0.10, 1.0 },
				hovered = { 0.85, 0.20, 0.20, 1.0 },
				active = { 0.65, 0.05, 0.05, 1.0 },
			},
			buttonRemove = {
				bg = { 0.75, 0.10, 0.10, 1.0 },
				hovered = { 0.85, 0.20, 0.20, 1.0 },
				active = { 0.65, 0.05, 0.05, 1.0 },
			},
			buttonDone = {
				bg = { 0.35, 0.45, 0.00, 1.0 },
				hovered = { 0.45, 0.55, 0.05, 1.0 },
				active = { 0.25, 0.35, 0.00, 1.0 },
			},
			tabConfig = {
				bg = { 0.32, 0.34, 0.67, 0.8 },
				hovered = { 0.42, 0.44, 0.77, 0.8 },
				active = { 0.22, 0.24, 0.57, 0.8 },
			},
			summaryFrame = { bg = { 0.93, 0.91, 0.84, 1.0 } },
		},
		globalColors = {
			{ ImGuiCol.WindowBg, { 0.99, 0.96, 0.89, 1.0 } }, -- Base3
			{ ImGuiCol.TitleBg, { 0.93, 0.91, 0.84, 1.0 } }, -- Base2
			{ ImGuiCol.TitleBgActive, { 0.93, 0.91, 0.84, 1.0 } },
			{ ImGuiCol.FrameBg, { 0.93, 0.91, 0.84, 1.0 } },
			{ ImGuiCol.FrameBgHovered, { 0.88, 0.85, 0.78, 1.0 } },
			{ ImGuiCol.FrameBgActive, { 0.83, 0.80, 0.73, 1.0 } },
			{ ImGuiCol.Button, { 0.15, 0.55, 0.82, 1.0 } }, -- Blue
			{ ImGuiCol.ButtonHovered, { 0.20, 0.65, 0.92, 1.0 } },
			{ ImGuiCol.ButtonActive, { 0.10, 0.45, 0.72, 1.0 } },
			{ ImGuiCol.Tab, { 0.93, 0.91, 0.84, 1.0 } },
			{ ImGuiCol.TabHovered, { 0.88, 0.85, 0.78, 1.0 } },
			{ ImGuiCol.TabActive, { 0.15, 0.55, 0.82, 1.0 } },
			{ ImGuiCol.Header, { 0.93, 0.91, 0.84, 1.0 } },
			{ ImGuiCol.HeaderHovered, { 0.88, 0.85, 0.78, 1.0 } },
			{ ImGuiCol.HeaderActive, { 0.83, 0.80, 0.73, 1.0 } },
			{ ImGuiCol.Separator, { 0.58, 0.63, 0.63, 1.0 } }, -- Base1
			{ ImGuiCol.Border, { 0.58, 0.63, 0.63, 1.0 } },
			{ ImGuiCol.ScrollbarBg, { 0.99, 0.96, 0.89, 1.0 } },
			{ ImGuiCol.ScrollbarGrab, { 0.93, 0.91, 0.84, 1.0 } },
			{ ImGuiCol.ScrollbarGrabHovered, { 0.88, 0.85, 0.78, 1.0 } },
			{ ImGuiCol.ScrollbarGrabActive, { 0.83, 0.80, 0.73, 1.0 } },
			{ ImGuiCol.Text, { 0.00, 0.17, 0.21, 1.0 } }, -- Base03
			{ ImGuiCol.TextDisabled, { 0.50, 0.55, 0.55, 1.0 } },
			{ ImGuiCol.CheckMark, { 0.10, 0.50, 0.48, 1.0 } },
		}
	},
	["Windows 95"] = {
		text = {
			success = { 0.00, 0.50, 0.00, 1.0 }, -- Classic Green
			info = { 0.00, 0.00, 1.00, 1.0 }, -- Classic Blue
			warning = { 0.50, 0.50, 0.00, 1.0 }, -- Classic Olive
			error = { 0.50, 0.00, 0.00, 1.0 }, -- Classic Red
			muted = { 0.50, 0.50, 0.50, 1.0 }, -- Classic Gray
			disabled = { 0.50, 0.50, 0.50, 1.0 },
			gold = { 0.70, 0.50, 0.00, 1.0 },
			green = { 0.00, 0.50, 0.00, 1.0 },
			orange = { 0.80, 0.40, 0.00, 1.0 },
		},
		style = {
			buttonCheck = { bg = { 0.00, 0.50, 0.50, 1.0 } },
			buttonCheckDisabled = { bg = { 0.60, 0.60, 0.60, 0.5 } },
			buttonDanger = {
				bg = { 0.50, 0.00, 0.00, 1.0 },
				hovered = { 0.60, 0.10, 0.10, 1.0 },
				active = { 0.40, 0.00, 0.00, 1.0 },
			},
			buttonRemove = {
				bg = { 0.50, 0.00, 0.00, 1.0 },
				hovered = { 0.60, 0.10, 0.10, 1.0 },
				active = { 0.40, 0.00, 0.00, 1.0 },
			},
			buttonDone = {
				bg = { 0.00, 0.50, 0.00, 1.0 },
				hovered = { 0.10, 0.60, 0.10, 1.0 },
				active = { 0.00, 0.40, 0.00, 1.0 },
			},
			tabConfig = {
				bg = { 0.00, 0.00, 0.50, 0.8 },
				hovered = { 0.10, 0.10, 0.60, 0.8 },
				active = { 0.00, 0.00, 0.40, 0.8 },
			},
			summaryFrame = { bg = { 1.00, 1.00, 1.00, 1.0 } },
		},
		globalColors = {
			{ ImGuiCol.WindowBg, { 0.75, 0.75, 0.75, 1.0 } }, -- Win95 Gray
			{ ImGuiCol.TitleBg, { 0.50, 0.50, 0.50, 1.0 } },
			{ ImGuiCol.TitleBgActive, { 0.00, 0.00, 0.50, 1.0 } }, -- Blue active
			{ ImGuiCol.FrameBg, { 1.00, 1.00, 1.00, 1.0 } }, -- White input
			{ ImGuiCol.FrameBgHovered, { 0.90, 0.90, 0.90, 1.0 } },
			{ ImGuiCol.FrameBgActive, { 0.80, 0.80, 0.80, 1.0 } },
			{ ImGuiCol.Button, { 0.75, 0.75, 0.75, 1.0 } },
			{ ImGuiCol.ButtonHovered, { 0.85, 0.85, 0.85, 1.0 } },
			{ ImGuiCol.ButtonActive, { 0.60, 0.60, 0.60, 1.0 } },
			{ ImGuiCol.Tab, { 0.75, 0.75, 0.75, 1.0 } },
			{ ImGuiCol.TabHovered, { 0.85, 0.85, 0.85, 1.0 } },
			{ ImGuiCol.TabActive, { 0.75, 0.75, 0.75, 1.0 } },
			{ ImGuiCol.Header, { 0.50, 0.50, 0.50, 1.0 } },
			{ ImGuiCol.HeaderHovered, { 0.00, 0.00, 0.50, 1.0 } },
			{ ImGuiCol.HeaderActive, { 0.00, 0.00, 0.50, 1.0 } },
			{ ImGuiCol.Separator, { 0.50, 0.50, 0.50, 1.0 } },
			{ ImGuiCol.Border, { 0.50, 0.50, 0.50, 1.0 } },
			{ ImGuiCol.ScrollbarBg, { 0.75, 0.75, 0.75, 1.0 } },
			{ ImGuiCol.ScrollbarGrab, { 0.60, 0.60, 0.60, 1.0 } },
			{ ImGuiCol.ScrollbarGrabHovered, { 0.70, 0.70, 0.70, 1.0 } },
			{ ImGuiCol.ScrollbarGrabActive, { 0.50, 0.50, 0.50, 1.0 } },
			{ ImGuiCol.Text, { 0.00, 0.00, 0.00, 1.0 } }, -- Black text
			{ ImGuiCol.TextDisabled, { 0.50, 0.50, 0.50, 1.0 } },
			{ ImGuiCol.CheckMark, { 0.00, 0.00, 0.00, 1.0 } },
		}
	}
}

function theme.apply(state)
	local themeName = (state and state.config and state.config.themeName) or "Default"
	local active = presets[themeName] or presets["Default"]

	-- Dynamically expose variables to getters
	theme.text = active.text
	theme.style = active.style
	theme.globalColors = active.globalColors

	local roundWindow, roundFrame, roundGrab, roundTab, roundScrollbar
	if themeName == "Windows 95" then
		roundWindow, roundFrame, roundGrab, roundTab, roundScrollbar = 0, 0, 0, 0, 0
	else
		roundWindow, roundFrame, roundGrab, roundTab, roundScrollbar = 8, 4, 4, 4, 4
	end

	ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, roundWindow)
	ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, roundFrame)
	ImGui.PushStyleVar(ImGuiStyleVar.GrabRounding, roundGrab)
	ImGui.PushStyleVar(ImGuiStyleVar.TabRounding, roundTab)
	ImGui.PushStyleVar(ImGuiStyleVar.CellPadding, 6, 6)
	ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 12, 12)
	ImGui.PushStyleVar(ImGuiStyleVar.ScrollbarRounding, roundScrollbar)

	for _, col in ipairs(theme.globalColors) do
		ImGui.PushStyleColor(col[1], col[2][1], col[2][2], col[2][3], col[2][4])
	end
end

function theme.pop()
	ImGui.PopStyleColor(#theme.globalColors)
	ImGui.PopStyleVar(7)
end

return theme
