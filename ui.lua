local mq = require("mq")
local ImGui = require("ImGui")

local ui = {}

-- Helper function to parse ISO 8601 UTC date string into a local Unix timestamp
local function parseISOTimestamp(str)
	if not str then
		return nil
	end
	-- Pattern matches: YYYY-MM-DDTHH:MM:SS
	local year, month, day, hour, min, sec = str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
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

-- Helper function to format numbers with thousands separators
local function formatNumber(amount)
	if not amount then
		return "N/A"
	end
	local formatted = tostring(amount)
	while true do
		local k
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
		if k == 0 then
			break
		end
	end
	return formatted
end

-- Helper function to scan character inventory and return all unique items in worn bag slots (23 to 34)
local function getInventoryItems()
	local items = {}
	local seenIds = {}
	for i = 23, 34 do
		local bag = mq.TLO.Me.Inventory(i)
		if bag and bag() then
			if bag.Container() and bag.Container() > 0 then
				for slot = 1, bag.Container() do
					local item = bag.Item(slot)
					if item and item() then
						local itemId = item.ID()
						local itemName = item.Name()
						if itemId and itemId > 0 and not seenIds[itemId] then
							seenIds[itemId] = true
							table.insert(items, { id = itemId, name = itemName })
						end
					end
				end
			else
				local itemId = bag.ID()
				local itemName = bag.Name()
				if itemId and itemId > 0 and not seenIds[itemId] then
					seenIds[itemId] = true
					table.insert(items, { id = itemId, name = itemName })
				end
			end
		end
	end
	return items
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

	for _, entry in ipairs(state.priceHistory) do
		if entry.selected and entry.status == "Success" then
			local itemName = (entry.data and entry.data.item) or entry.item
			local listedPrice = entry.listedPrice or 0

			local countObj = mq.TLO.FindItemCount(string.format('=%s', itemName))
			local count = (countObj and countObj()) or 1
			if count == 0 then
				count = 1
			end

			local itemIdentifier = itemName
			if useLinks then
				local eqLink = mq.TLO.LinkDB(string.format('=%s', itemName))()
				if eqLink and eqLink ~= "" then
					itemIdentifier = eqLink
				end
			end

			if count > 1 then
				table.insert(segments, string.format("%dx %s %d pp", count, itemIdentifier, listedPrice))
			else
				table.insert(segments, string.format("%s %d pp", itemIdentifier, listedPrice))
			end
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

	if existingEntry then
		-- Move existing entry to the top of the history list for visibility
		if existingIndex > 1 then
			table.remove(state.priceHistory, existingIndex)
			table.insert(state.priceHistory, 1, existingEntry)
			state.saveRequested = true
		end

		if existingEntry.status ~= "Searching..." then
			existingEntry.status = "Searching..."
			existingEntry.data = nil
			table.insert(state.searchQueue, existingEntry)
			state.saveRequested = true
		end
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
		table.insert(state.searchQueue, entry)
		state.saveRequested = true
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
			local tFlags = bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.ScrollY, ImGuiTableFlags.Sortable)
			if ImGui.BeginTable(title .. "Table", 4, tFlags, 0, 105) then
				ImGui.TableSetupColumn("Trader", ImGuiTableColumnFlags.WidthStretch)
				ImGui.TableSetupColumn("Plat", ImGuiTableColumnFlags.WidthFixed, 55)
				ImGui.TableSetupColumn("Krono", ImGuiTableColumnFlags.WidthFixed, 45)
				ImGui.TableSetupColumn("Age", ImGuiTableColumnFlags.WidthFixed, 75) -- Time Column
				ImGui.TableHeadersRow()

				local sortSpecs = ImGui.TableGetSortSpecs()
				if sortSpecs and sortSpecs.SpecsDirty then
					local spec = sortSpecs:Specs(1)
					if spec then
						table.sort(logArray, function(a, b)
							local valA, valB

							if spec.ColumnIndex == 0 then
								valA = (a.auctioneer or ""):lower()
								valB = (b.auctioneer or ""):lower()
							elseif spec.ColumnIndex == 1 then
								valA = a.platPrice or 0
								valB = b.platPrice or 0
							elseif spec.ColumnIndex == 2 then
								valA = a.kronoPrice or 0
								valB = b.kronoPrice or 0
							elseif spec.ColumnIndex == 3 then
								valA = parseISOTimestamp(a.datetime) or 0
								valB = parseISOTimestamp(b.datetime) or 0
							else
								return false
							end

							if spec.SortDirection == ImGuiSortDirection.Ascending then
								return valA < valB
							else
								return valA > valB
							end
						end)
					end
					sortSpecs.SpecsDirty = false
				end

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
			local canSearch = true
			for _, entry in ipairs(state.priceHistory) do
				if entry.item:lower() == cursorItem.Name():lower() and entry.status == "Searching..." then
					canSearch = false
					break
				end
			end
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

		if ImGui.BeginTabBar("PriceCheckTabBar") then
			if ImGui.BeginTabItem("Search & Sales") then
				-- ----------------------------------------------------
				-- SECTION 2: Sales String Generation
				-- ----------------------------------------------------
				ImGui.Text("Pricing & Sales Tool:")

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

				local avail = ImGui.GetContentRegionAvail()
				local buttonWidth = (avail - ImGui.GetStyle().ItemSpacing.x) / 2

				local buttonLabel = isBroadcasting and "Broadcasting..."
					or string.format("Broadcast via %s", (state.broadcastCommand ~= "" and state.broadcastCommand or "/auction"))
				if ImGui.Button(buttonLabel, buttonWidth, 30) and canBroadcast then
					local realAuctionLines = getAuctionLines(state, true)
					for _, commandLine in ipairs(realAuctionLines) do
						table.insert(state.broadcastQueue, commandLine)
					end
				end
				if not canBroadcast then
					ImGui.PopStyleVar()
				end

				ImGui.SameLine()

				if ImGui.Button("Recheck Qty", buttonWidth, 30) then
					local removedAny = false
					local i = 1
					while i <= #state.priceHistory do
						local entry = state.priceHistory[i]
						local countObj = mq.TLO.FindItemCount(string.format('=%s', entry.item))
						local count = (countObj and countObj()) or 0
						local bankObj = mq.TLO.FindItemBankCount(string.format('=%s', entry.item))
						local bankCount = (bankObj and bankObj()) or 0
						if count + bankCount == 0 then
							if state.activeDetailEntry == entry then
								state.activeDetailEntry = nil
							end
							for sqIdx, sqEntry in ipairs(state.searchQueue) do
								if sqEntry == entry then
									table.remove(state.searchQueue, sqIdx)
									break
								end
							end
							table.remove(state.priceHistory, i)
							removedAny = true
						else
							i = i + 1
						end
					end
					if removedAny then
						state.saveRequested = true
					end
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
					state.saveRequested = true
				end

				local flags = bit32.bor(
					ImGuiTableFlags.Borders,
					ImGuiTableFlags.RowBg,
					ImGuiTableFlags.Resizable,
					ImGuiTableFlags.ScrollY,
					ImGuiTableFlags.Sortable
				)

				if ImGui.BeginTable("HistoryTable", 10, flags, 0, 0) then
					ImGui.TableSetupColumn("Sel", ImGuiTableColumnFlags.WidthFixed, 30)
					ImGui.TableSetupColumn("Item Name", ImGuiTableColumnFlags.WidthStretch)
					ImGui.TableSetupColumn("Qty (Bank)", ImGuiTableColumnFlags.WidthFixed, 70)
					ImGui.TableSetupColumn("Avg Sell", ImGuiTableColumnFlags.WidthFixed, 75)
					ImGui.TableSetupColumn("List Price", ImGuiTableColumnFlags.WidthFixed, 80)
					ImGui.TableSetupColumn("High WTS", ImGuiTableColumnFlags.WidthFixed, 70)
					ImGui.TableSetupColumn("Low WTS", ImGuiTableColumnFlags.WidthFixed, 70)
					ImGui.TableSetupColumn("Avg Buy", ImGuiTableColumnFlags.WidthFixed, 75)
					ImGui.TableSetupColumn("High WTB", ImGuiTableColumnFlags.WidthFixed, 70)
					ImGui.TableSetupColumn("Details", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.NoSort), 55)
					ImGui.TableHeadersRow()

					local sortSpecs = ImGui.TableGetSortSpecs()
					if sortSpecs and sortSpecs.SpecsDirty then
						local spec = sortSpecs:Specs(1)
						if spec then
							table.sort(state.priceHistory, function(a, b)
								local valA, valB

								if spec.ColumnIndex == 0 then
									valA = a.selected and 1 or 0
									valB = b.selected and 1 or 0
								elseif spec.ColumnIndex == 1 then
									valA = (a.data and a.data.item) or a.item
									valB = (b.data and b.data.item) or b.item
									valA = valA:lower()
									valB = valB:lower()
								elseif spec.ColumnIndex == 2 then
									local countObjA = mq.TLO.FindItemCount(string.format('=%s', a.item))
									local countA = (countObjA and countObjA()) or 0
									valA = countA
									local countObjB = mq.TLO.FindItemCount(string.format('=%s', b.item))
									local countB = (countObjB and countObjB()) or 0
									valB = countB
								elseif spec.ColumnIndex == 3 then
									valA = (a.status == "Success" and a.data and a.data.sellAverage) or -1
									valB = (b.status == "Success" and b.data and b.data.sellAverage) or -1
								elseif spec.ColumnIndex == 4 then
									valA = a.listedPrice or -1
									valB = b.listedPrice or -1
								elseif spec.ColumnIndex == 5 then
									local hA = getPriceStats(a)
									local hB = getPriceStats(b)
									valA = hA or -1
									valB = hB or -1
								elseif spec.ColumnIndex == 6 then
									local _, lA = getPriceStats(a)
									local _, lB = getPriceStats(b)
									valA = lA or -1
									valB = lB or -1
								elseif spec.ColumnIndex == 7 then
									valA = (a.status == "Success" and a.data and a.data.buyAverage) or -1
									valB = (b.status == "Success" and b.data and b.data.buyAverage) or -1
								elseif spec.ColumnIndex == 8 then
									local _, _, hA = getPriceStats(a)
									local _, _, hB = getPriceStats(b)
									valA = hA or -1
									valB = hB or -1
								else
									return false
								end

								if spec.SortDirection == ImGuiSortDirection.Ascending then
									return valA < valB
								else
									return valA > valB
								end
							end)
						end
						sortSpecs.SpecsDirty = false
						state.saveRequested = true
					end

					for index, entry in ipairs(state.priceHistory) do
						ImGui.TableNextRow()

						-- Column 0: Selected Checkbox
						ImGui.TableSetColumnIndex(0)
						if entry.status == "Success" then
							local val, changed = ImGui.Checkbox("##sel_" .. entry.id, entry.selected)
							entry.selected = val
							if changed then
								state.saveRequested = true
							end
						else
							ImGui.Text("-")
						end

						-- Column 1: Item Name
						ImGui.TableSetColumnIndex(1)
						if entry.status == "Success" and entry.data then
							local sellSamples = entry.data.sellSampleSize or 0
							if sellSamples <= 5 then
								ImGui.TextColored(1.0, 0.3, 0.3, 1.0, "[!] ")
								if ImGui.IsItemHovered() then
									ImGui.BeginTooltip()
									ImGui.Text(string.format("Small sample size: only %d sample(s) available", sellSamples))
									ImGui.EndTooltip()
								end
								ImGui.SameLine()
							end
						end
						local displayName = (entry.data and entry.data.item) or entry.item
						ImGui.Text(displayName)

						-- Column 2: Qty (Bank)
						ImGui.TableSetColumnIndex(2)
						local countObj = mq.TLO.FindItemCount(string.format('=%s', entry.item))
						local count = (countObj and countObj()) or 0
						local bankObj = mq.TLO.FindItemBankCount(string.format('=%s', entry.item))
						local bankCount = (bankObj and bankObj()) or 0
						ImGui.Text(string.format("%d (%d)", count, bankCount))

						-- Column 3: Avg Sell
						ImGui.TableSetColumnIndex(3)
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

						-- Column 4: List Price (Editable)
						ImGui.TableSetColumnIndex(4)
						if entry.status == "Success" then
							ImGui.PushItemWidth(-1)
							local val, changed = ImGui.InputInt("##list_" .. entry.id, entry.listedPrice or 0, 0, 0)
							if val < 0 then
								val = 0
							end
							entry.listedPrice = val
							if changed then
								state.saveRequested = true
							end
							ImGui.PopItemWidth()
						else
							ImGui.Text("-")
						end

						-- Extract highest/lowest stats
						local highestWTS, lowestWTS, highestWTB = getPriceStats(entry)

						-- Column 5: High WTS
						ImGui.TableSetColumnIndex(5)
						if entry.status == "Success" and highestWTS then
							ImGui.TextColored(0.4, 0.9, 0.4, 1.0, string.format("%d pp", math.floor(highestWTS)))
						else
							ImGui.Text("-")
						end

						-- Column 6: Low WTS
						ImGui.TableSetColumnIndex(6)
						if entry.status == "Success" and lowestWTS then
							ImGui.TextColored(0.4, 0.9, 0.4, 1.0, string.format("%d pp", math.floor(lowestWTS)))
						else
							ImGui.Text("-")
						end

						-- Column 7: Avg Buy
						ImGui.TableSetColumnIndex(7)
						if entry.status == "Success" then
							local buyPrice = entry.data.buyAverage or 0
							ImGui.TextColored(1.0, 0.7, 0.4, 1.0, string.format("%.1f pp", buyPrice))
						else
							ImGui.Text("-")
						end

						-- Column 8: High WTB
						ImGui.TableSetColumnIndex(8)
						if entry.status == "Success" and highestWTB then
							ImGui.TextColored(1.0, 0.7, 0.4, 1.0, string.format("%d pp", math.floor(highestWTB)))
						else
							ImGui.Text("-")
						end

						-- Column 9: Details button
						ImGui.TableSetColumnIndex(9)
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

				ImGui.EndTabItem()
			end

			if ImGui.BeginTabItem("Bulk Inventory Check") then
				-- ----------------------------------------------------
				-- SECTION 4: Bulk Price Check Table & Actions
				-- ----------------------------------------------------
				local canBulkSearch = not state.isBulkSearching and (#state.bulkQueue == 0)
				if not canBulkSearch then
					ImGui.PushStyleVar(ImGuiStyleVar.Alpha, 0.5)
				end
				if ImGui.Button(state.isBulkSearching and "Pricing Inventory..." or "Price Inventory", -1, 30) and canBulkSearch then
					local items = getInventoryItems()
					state.bulkPriceHistory = {}
					state.bulkQueue = {}

					-- Populate bulkPriceHistory with placeholder entries and collect IDs
					local ids = {}
					for _, item in ipairs(items) do
						table.insert(ids, item.id)
						table.insert(state.bulkPriceHistory, {
							itemId = item.id,
							item = item.name,
							medianPlatPrice = nil,
							hasData = false,
							status = "Searching...",
						})
					end

					state.bulkQueue = ids
					state.isBulkSearching = (#ids > 0)
				end
				if not canBulkSearch then
					ImGui.PopStyleVar()
				end

				if state.bulkLastUpdated or state.bulkKronoRate then
					ImGui.Spacing()
					if state.bulkLastUpdated then
						local localTime = parseISOTimestamp(state.bulkLastUpdated)
						local readableTime = "Unknown"
						if localTime then
							readableTime = os.date("%Y-%m-%d %H:%M:%S", localTime) .. " (" .. getRelativeTimeString(state.bulkLastUpdated) .. ")"
						end
						ImGui.TextColored(0.4, 0.8, 1.0, 1.0, "Last Updated: " .. readableTime)
					end
					if state.bulkKronoRate then
						ImGui.TextColored(1.0, 0.8, 0.2, 1.0, "Current Krono Price: " .. formatNumber(state.bulkKronoRate) .. " pp")
					end
					ImGui.Spacing()
				end

				ImGui.Separator()
				ImGui.Text("BULK Price History:")
				ImGui.SameLine(ImGui.GetWindowWidth() - 90)
				if ImGui.Button("Clear##Bulk", 75, 0) then
					state.bulkPriceHistory = {}
					state.bulkLastUpdated = nil
					state.bulkKronoRate = nil
				end

				local flags = bit32.bor(
					ImGuiTableFlags.Borders,
					ImGuiTableFlags.RowBg,
					ImGuiTableFlags.Resizable,
					ImGuiTableFlags.ScrollY,
					ImGuiTableFlags.Sortable
				)

				if ImGui.BeginTable("BulkHistoryTable", 3, flags, 0, 0) then
					ImGui.TableSetupColumn("Item Name", ImGuiTableColumnFlags.WidthStretch)
					ImGui.TableSetupColumn("Median Price", ImGuiTableColumnFlags.WidthFixed, 120)
					ImGui.TableSetupColumn("Add", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.NoSort), 45)
					ImGui.TableHeadersRow()

					local sortSpecs = ImGui.TableGetSortSpecs()
					if sortSpecs and sortSpecs.SpecsDirty then
						local spec = sortSpecs:Specs(1)
						if spec then
							table.sort(state.bulkPriceHistory, function(a, b)
								local valA, valB

								if spec.ColumnIndex == 0 then
									valA = (a.item or ""):lower()
									valB = (b.item or ""):lower()
								elseif spec.ColumnIndex == 1 then
									valA = (a.status == "Success" and a.hasData and a.medianPlatPrice) or -1
									valB = (b.status == "Success" and b.hasData and b.medianPlatPrice) or -1
								else
									return false
								end

								if spec.SortDirection == ImGuiSortDirection.Ascending then
									return valA < valB
								else
									return valA > valB
								end
							end)
						end
						sortSpecs.SpecsDirty = false
					end

					for index, entry in ipairs(state.bulkPriceHistory) do
						ImGui.TableNextRow()

						-- Column 0: Item Name
						ImGui.TableSetColumnIndex(0)
						ImGui.Text(entry.item)

						-- Column 1: Median Price / Status
						ImGui.TableSetColumnIndex(1)
						if entry.status == "Searching..." then
							ImGui.TextColored(1.0, 0.8, 0.2, 1.0, entry.status)
						elseif entry.status == "Success" then
							if entry.hasData and entry.medianPlatPrice then
								ImGui.TextColored(0.4, 1.0, 0.4, 1.0, string.format("%s pp", formatNumber(math.floor(entry.medianPlatPrice))))
							else
								ImGui.TextColored(1.0, 0.3, 0.3, 1.0, "No price found")
							end
						else
							ImGui.TextColored(1.0, 0.3, 0.3, 1.0, entry.status or "N/A")
						end

						-- Column 2: Add Button
						ImGui.TableSetColumnIndex(2)
						if entry.status == "Success" and entry.hasData and entry.medianPlatPrice then
							local isSearchingThis = false
							for _, hEntry in ipairs(state.priceHistory) do
								if hEntry.item:lower() == entry.item:lower() then
									if hEntry.status == "Searching..." then
										isSearchingThis = true
									end
									break
								end
							end

							if isSearchingThis then
								ImGui.TextColored(1.0, 0.8, 0.2, 1.0, "...")
							else
								if ImGui.Button("+##bulk_add_" .. index, -1, 18) then
									queueSearch(state, entry.item)
								end
							end
						else
							ImGui.Text("-")
						end
					end
					ImGui.EndTable()
				end

				ImGui.EndTabItem()
			end
			ImGui.EndTabBar()
		end

		if state.activeDetailEntry then
			renderDetailsModal(state)
		end
	end
	ImGui.End()
end

return ui
