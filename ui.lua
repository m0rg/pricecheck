local mq = require("mq")
local ImGui = require("ImGui")

local ui = {}

-- Helper function to parse ISO 8601 UTC date string into a local Unix timestamp
local function parseISOTimestamp(str)
	if not str then
		return nil
	end
	-- Pattern matches: YYYY-MM-DDTHH:MM:SSZ
	local year, month, day, hour, min, sec = str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)Z")
	if not year then
		return nil
	end

	-- Create UTC time table (interpreted as local by os.time)
	local utcTime = os.time({ year = year, month = month, day = day, hour = hour, min = min, sec = sec })

	-- Calculate timezone bias to shift UTC to your local system time (DST-safe)
	local now = os.time()
	local timezoneBias = os.difftime(now, os.time(os.date("!*t", now)))

	return utcTime + timezoneBias
end

-- Helper function to output a clean, human-readable relative string
local function getRelativeTimeString(isoStr)
	local pastTime = parseISOTimestamp(isoStr)
	if not pastTime then
		return "Unknown time"
	end

	local diff = os.difftime(os.time(), pastTime)
	if diff < 0 then
		diff = 0
	end -- Clamp future time sync deviations

	if diff < 60 then
		return "Just now"
	elseif diff < 3600 then
		local mins = math.floor(diff / 60)
		return string.format("%dm ago", mins)
	elseif diff < 86400 then
		local hours = math.floor(diff / 3600)
		return string.format("%dh ago", hours)
	else
		local days = math.floor(diff / 86400)
		return string.format("%dd ago", days)
	end
end

-- Helper function to extract price statistics from detailed lists
local function getPriceStats(entry)
	if not entry or not entry.data then
		return nil, nil, nil
	end

	local highestWTS = nil
	local lowestWTS = nil
	local highestWTB = nil

	local sellSales = entry.data.recentSellSales
	if sellSales and #sellSales > 0 then
		for _, sale in ipairs(sellSales) do
			local price = sale.platPrice or 0
			if not highestWTS or price > highestWTS then
				highestWTS = price
			end
			if not lowestWTS or price < lowestWTS then
				lowestWTS = price
			end
		end
	end

	local buySales = entry.data.recentBuySales
	if buySales and #buySales > 0 then
		for _, sale in ipairs(buySales) do
			local price = sale.platPrice or 0
			if not highestWTB or price > highestWTB then
				highestWTB = price
			end
		end
	end

	return highestWTS, lowestWTS, highestWTB
end

-- Helper function to generate an array of item string segments
local function generateItemSegments(state, useLinks)
	local segments = {}
	local multiplier = 1 + (state.priceModifier / 100)

	for _, entry in ipairs(state.priceHistory) do
		if entry.selected and entry.status == "Success" and entry.data then
			local itemName = entry.data.item or entry.item
			local basePrice = entry.data.sellAverage or 0
			local modifiedPrice = math.floor(basePrice * multiplier)
			if modifiedPrice < 0 then
				modifiedPrice = 0
			end

			local countObj = mq.TLO.FindItemCount(string.format('="%s"', itemName))
			local count = (countObj and countObj()) or 1
			if count == 0 then
				count = 1
			end

			local itemIdentifier = itemName
			if useLinks then
				local linkObj = mq.TLO.LinkDB(string.format('="%s"', itemName))
				local eqLink = linkObj and linkObj()
				if eqLink and eqLink ~= "" then
					itemIdentifier = eqLink
				end
			end

			table.insert(segments, string.format("%dx %s %d pp", count, itemIdentifier, modifiedPrice))
		end
	end
	return segments
end

-- Function to package segments into lines capped at 4 items each
local function getAuctionLines(state, useLinks)
	local segments = generateItemSegments(state, useLinks)
	if #segments == 0 then
		return {}
	end

	local lines = {}
	local currentLineItems = {}
	local prefix = (state.broadcastCommand ~= "") and state.broadcastCommand or "/auction"

	for i, segment in ipairs(segments) do
		table.insert(currentLineItems, segment)
		if #currentLineItems == 4 or i == #segments then
			table.insert(lines, string.format("%s WTS %s", prefix, table.concat(currentLineItems, ", ")))
			currentLineItems = {}
		end
	end

	return lines
end

-- Helper function to queue a price check and immediately create or update the history placeholder
local function queueSearch(state, itemName)
	if not itemName or itemName == "" then
		return
	end
	if state.isSearching or state.pendingSearch then
		return
	end

	-- Check if the item already exists in history (case-insensitive lookup)
	local existingEntry = nil
	local existingIndex = nil
	for i, entry in ipairs(state.priceHistory) do
		if entry.item:lower() == itemName:lower() then
			existingEntry = entry
			existingIndex = i
			break
		end
	end

	state.isSearching = true

	if existingEntry then
		existingEntry.status = "Searching..."
		existingEntry.data = nil

		-- Move existing entry to the top of the history list for visibility
		if existingIndex > 1 then
			table.remove(state.priceHistory, existingIndex)
			table.insert(state.priceHistory, 1, existingEntry)
		end

		state.pendingSearch = existingEntry
	else
		local uniqueId = tostring(os.clock()):gsub("%.", "")
		local entry = {
			id = uniqueId,
			item = itemName,
			data = nil,
			status = "Searching...",
			selected = false,
		}
		table.insert(state.priceHistory, 1, entry)
		state.pendingSearch = entry
	end
end

-- Helper window loop to display comprehensive historical details
local function renderDetailsModal(state)
	if not state.activeDetailEntry or not state.activeDetailEntry.data then
		return
	end

	local data = state.activeDetailEntry.data
	-- Widened default window width slightly to cleanly present the 4-column sub-tables
	ImGui.SetNextWindowSize(460, 360, ImGuiCond.FirstUseEver)

	local open, shouldDraw = ImGui.Begin(string.format("Market Details: %s", data.item or "Unknown"), true)
	if not open then
		state.activeDetailEntry = nil
		ImGui.End()
		return
	end

	if shouldDraw then
		ImGui.TextColored(0.4, 0.8, 1.0, 1.0, "Summary Analytics:")
		ImGui.Separator()
		ImGui.Text(string.format("Sellers Avg: %.1f pp (Samples: %d)", data.sellAverage or 0, data.sellSampleSize or 0))
		ImGui.Text(string.format("Buyers Avg: %.1f pp (Samples: %d)", data.buyAverage or 0, data.buySampleSize or 0))
		ImGui.Spacing()

		-- Render historical log data with relative times added
		local function drawLogTable(title, logArray)
			ImGui.TextColored(0.4, 1.0, 0.4, 1.0, title)
			if not logArray or #logArray == 0 then
				ImGui.TextDisabled("   No recent transactions recorded.")
				return
			end

			-- Incremented column count from 3 to 4 to host the relative timer column
			local tFlags = bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.ScrollY)
			if ImGui.BeginTable(title .. "Table", 4, tFlags, 0, 105) then
				ImGui.TableSetupColumn("Trader", ImGuiTableColumnFlags.WidthStretch)
				ImGui.TableSetupColumn("Plat", ImGuiTableColumnFlags.WidthFixed, 55)
				ImGui.TableSetupColumn("Krono", ImGuiTableColumnFlags.WidthFixed, 45)
				ImGui.TableSetupColumn("Age", ImGuiTableColumnFlags.WidthFixed, 75) -- Time Column
				ImGui.TableHeadersRow()

				for _, log in ipairs(logArray) do
					ImGui.TableNextRow()
					ImGui.TableSetColumnIndex(0)
					ImGui.Text(log.auctioneer or "Unknown")
					ImGui.TableSetColumnIndex(1)
					ImGui.Text(tostring(math.floor(log.platPrice or 0)))
					ImGui.TableSetColumnIndex(2)
					ImGui.Text(tostring(log.kronoPrice or 0))

					ImGui.TableSetColumnIndex(3)
					-- Pull dynamic localized relative time label string
					local ageString = getRelativeTimeString(log.datetime)
					ImGui.TextColored(0.7, 0.7, 0.7, 1.0, ageString)
				end
				ImGui.EndTable()
			end
		end

		drawLogTable("Recent Sell Offers (WTS)", data.recentSellSales)
		ImGui.Spacing()
		drawLogTable("Recent Buy Offers (WTB)", data.recentBuySales)
	end

	ImGui.End()
end

-- ImGui Render Loop
function ui.render(state)
	if not state.openGUI then
		return
	end

	ImGui.SetNextWindowSize(550, 520, ImGuiCond.FirstUseEver)

	local open, shouldDraw = ImGui.Begin("TLP Price Checker & Sales Tool", state.openGUI)
	state.openGUI = open
	if shouldDraw then
		local cursorItem = mq.TLO.Cursor

		-- ----------------------------------------------------
		-- SECTION 1: Item Drop Slot
		-- ----------------------------------------------------
		ImGui.Text("Item Drop Slot:")
		if cursorItem() then
			local canSearch = not state.isSearching and not state.pendingSearch
			if not canSearch then
				ImGui.PushStyleVar(ImGuiStyleVar.Alpha, 0.5)
			end
			ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.6, 0.2, 1.0)
			if ImGui.Button(string.format("Click to Check: %s", cursorItem.Name()), -1, 40) and canSearch then
				queueSearch(state, cursorItem.Name())
			end
			ImGui.PopStyleColor()
			if not canSearch then
				ImGui.PopStyleVar()
			end
		else
			ImGui.PushStyleColor(ImGuiCol.Button, 0.3, 0.3, 0.3, 0.5)
			ImGui.Button("Query Cursor Item\n(Hold an item on cursor to check price)", -1, 40)
			ImGui.PopStyleColor()
		end

		ImGui.Separator()

		-- ----------------------------------------------------
		-- SECTION 2: Modifier & Sales String Generation
		-- ----------------------------------------------------
		ImGui.Text("Pricing & Sales Tool:")

		state.priceModifier = ImGui.SliderInt("Price Modifier (%)", state.priceModifier, -100, 100, "%d%%")
		state.broadcastCommand = ImGui.InputText("Chat Command", state.broadcastCommand)

		ImGui.Text("Preview String(s) (Plain Text, Max 4 items per line):")
		local previewLines = getAuctionLines(state, false)
		local previewText = table.concat(previewLines, "\n")
		if previewText == "" then
			previewText = "No items selected or no valid prices available."
		end

		ImGui.PushStyleColor(ImGuiCol.FrameBg, 0.15, 0.15, 0.15, 1.0)
		ImGui.InputTextMultiline("##salesString", previewText, -1, 60, ImGuiInputTextFlags.ReadOnly)
		ImGui.PopStyleColor()

		local hasItemsSelected = (#previewLines > 0)
		local isBroadcasting = (#state.broadcastQueue > 0)
		local canBroadcast = hasItemsSelected and not isBroadcasting

		if not canBroadcast then
			ImGui.PushStyleVar(ImGuiStyleVar.Alpha, 0.5)
		end

		local buttonLabel = isBroadcasting and "Broadcasting..."
			or string.format("Broadcast via %s", (state.broadcastCommand ~= "" and state.broadcastCommand or "/auction"))
		if ImGui.Button(buttonLabel, -1, 30) and canBroadcast then
			local realAuctionLines = getAuctionLines(state, true)
			for _, commandLine in ipairs(realAuctionLines) do
				table.insert(state.broadcastQueue, commandLine)
			end
		end
		if not canBroadcast then
			ImGui.PopStyleVar()
		end

		ImGui.Separator()

		-- ----------------------------------------------------
		-- SECTION 3: Price History Table
		-- ----------------------------------------------------
		ImGui.Text("Price History:")
		ImGui.SameLine(ImGui.GetWindowWidth() - 90)
		if ImGui.Button("Clear All", 75, 0) then
			state.priceHistory = {}
			state.activeDetailEntry = nil
		end

		local flags = bit32.bor(
			ImGuiTableFlags.Borders,
			ImGuiTableFlags.RowBg,
			ImGuiTableFlags.Resizable,
			ImGuiTableFlags.ScrollY
		)

		if ImGui.BeginTable("HistoryTable", 8, flags, 0, 0) then
			ImGui.TableSetupColumn("Sel", ImGuiTableColumnFlags.WidthFixed, 30)
			ImGui.TableSetupColumn("Item Name", ImGuiTableColumnFlags.WidthStretch)
			ImGui.TableSetupColumn("Avg Sell", ImGuiTableColumnFlags.WidthFixed, 75)
			ImGui.TableSetupColumn("High WTS", ImGuiTableColumnFlags.WidthFixed, 70)
			ImGui.TableSetupColumn("Low WTS", ImGuiTableColumnFlags.WidthFixed, 70)
			ImGui.TableSetupColumn("Avg Buy", ImGuiTableColumnFlags.WidthFixed, 75)
			ImGui.TableSetupColumn("High WTB", ImGuiTableColumnFlags.WidthFixed, 70)
			ImGui.TableSetupColumn("Details", ImGuiTableColumnFlags.WidthFixed, 55)
			ImGui.TableHeadersRow()

			for index, entry in ipairs(state.priceHistory) do
				ImGui.TableNextRow()

				-- Column 0: Selected Checkbox
				ImGui.TableSetColumnIndex(0)
				if entry.status == "Success" then
					entry.selected = ImGui.Checkbox("##sel_" .. entry.id, entry.selected)
				else
					ImGui.Text("-")
				end

				-- Column 1: Item Name
				ImGui.TableSetColumnIndex(1)
				local displayName = (entry.data and entry.data.item) or entry.item
				ImGui.Text(displayName)

				-- Column 2: Avg Sell
				ImGui.TableSetColumnIndex(2)
				if entry.status ~= "Success" then
					if entry.status == "Searching..." then
						ImGui.TextColored(1.0, 0.8, 0.2, 1.0, entry.status)
					else
						ImGui.TextColored(1.0, 0.3, 0.3, 1.0, entry.status)
					end
				else
					local sellPrice = entry.data.sellAverage or 0
					ImGui.TextColored(0.4, 1.0, 0.4, 1.0, string.format("%.1f pp", sellPrice))
				end

				-- Extract highest/lowest stats
				local highestWTS, lowestWTS, highestWTB = getPriceStats(entry)

				-- Column 3: High WTS
				ImGui.TableSetColumnIndex(3)
				if entry.status == "Success" and highestWTS then
					ImGui.TextColored(0.4, 0.9, 0.4, 1.0, string.format("%d pp", math.floor(highestWTS)))
				else
					ImGui.Text("-")
				end

				-- Column 4: Low WTS
				ImGui.TableSetColumnIndex(4)
				if entry.status == "Success" and lowestWTS then
					ImGui.TextColored(0.4, 0.9, 0.4, 1.0, string.format("%d pp", math.floor(lowestWTS)))
				else
					ImGui.Text("-")
				end

				-- Column 5: Avg Buy
				ImGui.TableSetColumnIndex(5)
				if entry.status == "Success" then
					local buyPrice = entry.data.buyAverage or 0
					ImGui.TextColored(1.0, 0.7, 0.4, 1.0, string.format("%.1f pp", buyPrice))
				else
					ImGui.Text("-")
				end

				-- Column 6: High WTB
				ImGui.TableSetColumnIndex(6)
				if entry.status == "Success" and highestWTB then
					ImGui.TextColored(1.0, 0.7, 0.4, 1.0, string.format("%d pp", math.floor(highestWTB)))
				else
					ImGui.Text("-")
				end

				-- Column 7: Details button
				ImGui.TableSetColumnIndex(7)
				if entry.status == "Success" then
					if ImGui.Button("View##" .. entry.id, -1, 18) then
						state.activeDetailEntry = entry
					end
				else
					ImGui.Text("-")
				end
			end
			ImGui.EndTable()
		end

		if state.activeDetailEntry then
			renderDetailsModal(state)
		end
	end
	ImGui.End()
end

return ui
