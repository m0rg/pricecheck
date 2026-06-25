local ImGui = require("ImGui")

local ui = {}

-- Pure formatting and calculation utilities delegated to util.lua

local char
local dto
local chat
local util

-- Injects character, data transfer, chat, and utility dependencies (SRP)
function ui.setup(charModule, dtoModule, chatModule, utilModule)
	char = charModule
	dto = dtoModule
	chat = chatModule
	util = utilModule
end



-- Date relative helper delegated to util.lua

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
		if entry.status == "Success" then
			local itemName = (entry.data and entry.data.item) or entry.item
			local listedPrice = entry.listedPrice or 0

			local count = char.getItemCounts(itemName)
			if count == 0 then
				count = 1
			end

			local itemIdentifier = itemName
			if useLinks then
				local eqLink = char.getItemLink(itemName)
				if eqLink then
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
function ui.getAuctionLines(state, useLinks)
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
	state:queueSearch(itemName, dto)
end

-- Helper function to render detailed log data inside an ImGui tooltip on hover
local function renderDetailsTooltip(entry)
	if not entry or not entry.data then return end
	local data = entry.data

	ImGui.BeginTooltip()
	ImGui.TextColored(0.4, 0.8, 1.0, 1.0, string.format("Market Details: %s", data.item or "Unknown"))
	ImGui.Separator()
	ImGui.Text(string.format("Sellers Avg: %.1f pp (Samples: %d)", data.sellAverage or 0, data.sellSampleSize or 0))
	ImGui.Text(string.format("Buyers Avg: %.1f pp (Samples: %d)", data.buyAverage or 0, data.buySampleSize or 0))
	ImGui.Spacing()

	local function drawCompactTable(title, logArray)
		ImGui.TextColored(0.4, 1.0, 0.4, 1.0, title)
		if not logArray or #logArray == 0 then
			ImGui.TextDisabled("   No recent transactions recorded.")
			return
		end

		local tFlags = bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg)
		if ImGui.BeginTable(title .. "TooltipTable", 4, tFlags, 0, 0) then
			ImGui.TableSetupColumn("Trader", ImGuiTableColumnFlags.WidthStretch)
			ImGui.TableSetupColumn("Plat", ImGuiTableColumnFlags.WidthFixed, 55)
			ImGui.TableSetupColumn("Krono", ImGuiTableColumnFlags.WidthFixed, 45)
			ImGui.TableSetupColumn("Age", ImGuiTableColumnFlags.WidthFixed, 75)
			ImGui.TableHeadersRow()

			local limit = math.min(#logArray, 5)
			for i = 1, limit do
				local log = logArray[i]
				ImGui.TableNextRow()
				ImGui.TableSetColumnIndex(0)
				ImGui.Text(log.auctioneer or "Unknown")
				ImGui.TableSetColumnIndex(1)
				ImGui.Text(tostring(math.floor(log.platPrice or 0)))
				ImGui.TableSetColumnIndex(2)
				ImGui.Text(tostring(log.kronoPrice or 0))
				ImGui.TableSetColumnIndex(3)
				ImGui.TextColored(0.7, 0.7, 0.7, 1.0, util.getRelativeTimeString(log.datetime))
			end
			ImGui.EndTable()
		end
	end

	drawCompactTable("Recent Sell Offers (WTS)", data.recentSellSales)
	ImGui.Spacing()
	drawCompactTable("Recent Buy Offers (WTB)", data.recentBuySales)
	ImGui.EndTooltip()
end

-- ImGui Render Loop
function ui.render(state)
	if not state.openGUI then
		return
	end

	ImGui.SetNextWindowSize(550, 520, ImGuiCond.FirstUseEver)

	local open, shouldDraw = ImGui.Begin("Frostreaver Trade Tools", state.openGUI)
	if state.openGUI ~= open then
		state:setOpenGUI(open)
	end
	if shouldDraw then
		local cursorItemName = char.getCursorItemName()

		-- ----------------------------------------------------
		-- SECTION 1: Item Drop Slot
		-- ----------------------------------------------------
		ImGui.Text("Item Drop Slot:")
		if cursorItemName then
			local canSearch = true
			if state.cursorQueryResult and state.cursorQueryResult.item:lower() == cursorItemName:lower() and state.cursorQueryResult.status == "Searching..." then
				canSearch = false
			end
			if not canSearch then
				ImGui.PushStyleVar(ImGuiStyleVar.Alpha, 0.5)
			end
			ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.6, 0.2, 1.0)
			if ImGui.Button(string.format("Click to Check: %s", cursorItemName), -1, 40) and canSearch then
				state:requestCursorQuery(cursorItemName)
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
			if ImGui.BeginTabItem("Your Items") then
				-- ----------------------------------------------------
				-- SECTION 4: Bulk Price Check Table & Actions
				-- ----------------------------------------------------
				local canBulkSearch = not state.isBulkSearching and (#state.bulkQueue == 0)
				if not canBulkSearch then
					ImGui.PushStyleVar(ImGuiStyleVar.Alpha, 0.5)
				end
				if ImGui.Button(state.isBulkSearching and "Pricing Inventory..." or "BULK PRICE CHECK", -1, 30) and canBulkSearch then
					local items = char.getUniqueInventoryItemTypes()
					state:startBulkSearch(items)
				end
				if not canBulkSearch then
					ImGui.PopStyleVar()
				end

				if state.bulkLastUpdated or state.bulkKronoRate then
					ImGui.Spacing()
					if state.bulkLastUpdated then
						local localTime = util.parseISOTimestamp(state.bulkLastUpdated)
						local readableTime = "Unknown"
						if localTime then
							readableTime = os.date("%Y-%m-%d %H:%M:%S", localTime) .. " (" .. util.getRelativeTimeString(state.bulkLastUpdated) .. ")"
						end
						ImGui.TextColored(0.4, 0.8, 1.0, 1.0, "Last Updated: " .. readableTime)
					end
					if state.bulkKronoRate then
						ImGui.TextColored(1.0, 0.8, 0.2, 1.0, "Current Krono Price: " .. util.formatNumber(state.bulkKronoRate) .. " pp")
					end
					ImGui.Spacing()
				end

				ImGui.Separator()
				ImGui.Text("BULK Price History:")
				ImGui.SameLine(ImGui.GetWindowWidth() - 90)
				if ImGui.Button("Clear##Bulk", 75, 0) then
					state:clearBulkHistory()
				end

				local flags = bit32.bor(
					ImGuiTableFlags.Borders,
					ImGuiTableFlags.RowBg,
					ImGuiTableFlags.Resizable,
					ImGuiTableFlags.ScrollY,
					ImGuiTableFlags.Sortable
				)

				if ImGui.BeginTable("BulkHistoryTable", 4, flags, 0, 0) then
					ImGui.TableSetupColumn("Item Name", ImGuiTableColumnFlags.WidthStretch)
					ImGui.TableSetupColumn("Median Price", ImGuiTableColumnFlags.WidthFixed, 100)
					ImGui.TableSetupColumn("Vendor Sell", ImGuiTableColumnFlags.WidthFixed, 100)
					ImGui.TableSetupColumn("Add", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.NoSort), 45)
					ImGui.TableHeadersRow()

					local sortSpecs = ImGui.TableGetSortSpecs()
					if sortSpecs and sortSpecs.SpecsDirty then
						local spec = sortSpecs:Specs(1)
						if spec then
							state:sortBulkHistory(function(a, b)
								local valA, valB

								if spec.ColumnIndex == 0 then
									valA = (a.item or ""):lower()
									valB = (b.item or ""):lower()
								elseif spec.ColumnIndex == 1 then
									valA = (a.status == "Success" and a.hasData and a.medianPlatPrice) or -1
									valB = (b.status == "Success" and b.hasData and b.medianPlatPrice) or -1
								elseif spec.ColumnIndex == 2 then
									valA = char.getItemValue(a.item)
									valB = char.getItemValue(b.item)
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

						-- Pre-calculate vendor sell price and check if it is higher/equal to market median price
						local vValue = char.getItemValue(entry.item)

						local isVendorBetter = false
						if entry.status == "Success" and entry.hasData and entry.medianPlatPrice then
							local vendorPlatPrice = vValue / 1000
							if vendorPlatPrice >= entry.medianPlatPrice then
								isVendorBetter = true
							end
						end

						-- Column 0: Item Name
						ImGui.TableSetColumnIndex(0)
						if isVendorBetter then
							ImGui.TextColored(1.0, 0.8, 0.2, 1.0, entry.item) -- Highlight item name in gold
							if ImGui.IsItemHovered() then
								ImGui.BeginTooltip()
								ImGui.Text("Vendor sell price is higher or equal to market median price!")
								ImGui.EndTooltip()
							end
						else
							ImGui.Text(entry.item)
						end

						-- Column 1: Median Price / Status
						ImGui.TableSetColumnIndex(1)
						if entry.status == "Searching..." then
							ImGui.TextColored(1.0, 0.8, 0.2, 1.0, entry.status)
						elseif entry.status == "Success" then
							if entry.hasData and entry.medianPlatPrice then
								ImGui.TextColored(0.4, 1.0, 0.4, 1.0, string.format("%s pp", util.formatNumber(math.floor(entry.medianPlatPrice))))
							else
								ImGui.TextColored(1.0, 0.3, 0.3, 1.0, "No price found")
							end
						elseif entry.status == "Not Checked" then
							ImGui.TextColored(0.6, 0.6, 0.6, 1.0, "-")
						else
							ImGui.TextColored(1.0, 0.3, 0.3, 1.0, entry.status or "N/A")
						end

						-- Column 2: Vendor Sell Price
						ImGui.TableSetColumnIndex(2)
						if vValue > 0 then
							if isVendorBetter then
								ImGui.TextColored(0.4, 1.0, 0.4, 1.0, util.formatVendorPrice(vValue)) -- Highlight vendor price in green if it's better
							else
								ImGui.TextColored(0.7, 0.7, 0.7, 1.0, util.formatVendorPrice(vValue))
							end
						else
							ImGui.Text("-")
						end

						-- Column 3: Add Button / Lootly Button
						ImGui.TableSetColumnIndex(3)
						if isVendorBetter then
							if ImGui.Button("SetItem##" .. index, -1, 18) then
								chat.executeCommand(string.format('/setitem sell "%s"', entry.item))
							end
						else
							local isAlreadyListed = false
							for _, hEntry in ipairs(state.priceHistory) do
								if hEntry.item:lower() == entry.item:lower() then
									isAlreadyListed = true
									break
								end
							end

							if entry.status == "Success" and entry.hasData and entry.medianPlatPrice then
								if isAlreadyListed then
									ImGui.PushStyleVar(ImGuiStyleVar.Alpha, 0.5)
								end
								if ImGui.Button("+##bulk_add_" .. index, -1, 18) and not isAlreadyListed then
									queueSearch(state, entry.item)
								end
								if isAlreadyListed then
									ImGui.PopStyleVar()
								end
							elseif entry.status == "Success" and (not entry.hasData or not entry.medianPlatPrice) then
								ImGui.PushStyleColor(ImGuiCol.Button, 0.6, 0.15, 0.15, 1.0)
								ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.8, 0.25, 0.25, 1.0)
								ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.5, 0.1, 0.1, 1.0)

								if isAlreadyListed then
									ImGui.PushStyleVar(ImGuiStyleVar.Alpha, 0.5)
								end
								if ImGui.Button("+##bulk_add_no_price_" .. index, -1, 18) and not isAlreadyListed then
									local defaultPrice = (state.config and state.config.defaultPlatPrice) or 1000
									state:addHistoryEntryWithDefaultPrice(entry.item, defaultPrice, dto)
								end
								if isAlreadyListed then
									ImGui.PopStyleVar()
								end

								ImGui.PopStyleColor(3)
							else
								ImGui.Text("-")
							end
						end
					end
					ImGui.EndTable()
				end

				ImGui.EndTabItem()
			end

			if ImGui.BeginTabItem("Trade") then
				-- ----------------------------------------------------
				-- SECTION 2: Sales String Generation
				-- ----------------------------------------------------
				ImGui.Text("Pricing & Sales Tool:")

				local newBroadcastCmd, changedBroadcastCmd = ImGui.InputText("Chat Command", state.broadcastCommand)
				if changedBroadcastCmd then
					state:setBroadcastCommand(newBroadcastCmd)
				end

				ImGui.Text("Preview String(s) (Plain Text, Max 4 items per line):")
				local previewLines = ui.getAuctionLines(state, false)
				local previewText = table.concat(previewLines, "\n")
				if previewText == "" then
					previewText = "No items or no valid prices available."
				end

				ImGui.PushStyleColor(ImGuiCol.FrameBg, 0.15, 0.15, 0.15, 1.0)
				ImGui.InputTextMultiline("##salesString", previewText, -1, 60, ImGuiInputTextFlags.ReadOnly)
				ImGui.PopStyleColor()

				local hasItemsToBroadcast = (#previewLines > 0)
				local isToggled = not not state.isBroadcastingToggled
				local canBroadcast = hasItemsToBroadcast or isToggled

				if not canBroadcast then
					ImGui.PushStyleVar(ImGuiStyleVar.Alpha, 0.5)
				end

				local avail = ImGui.GetContentRegionAvail()
				local buttonWidth = (avail - ImGui.GetStyle().ItemSpacing.x) / 2

				local buttonLabel
				if isToggled then
					local remaining = math.max(0, (state.nextToggleBroadcastTime or os.time()) - os.time())
					buttonLabel = string.format("Stop Broadcast (%ds)", remaining)
					ImGui.PushStyleColor(ImGuiCol.Button, 0.6, 0.15, 0.15, 1.0)
					ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.8, 0.25, 0.25, 1.0)
					ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.5, 0.1, 0.1, 1.0)
				else
					buttonLabel = string.format("Broadcast via %s", (state.broadcastCommand ~= "" and state.broadcastCommand or "/auction"))
				end

				if ImGui.Button(buttonLabel, buttonWidth, 30) and canBroadcast then
					if isToggled then
						state:setBroadcastingToggled(false)
						state:clearBroadcastQueue()
					else
						state:setBroadcastingToggled(true)
						local realAuctionLines = ui.getAuctionLines(state, true)
						state:enqueueBroadcast(realAuctionLines)
						state:setNextToggleBroadcastTime(os.time() + (state.config.broadcastInterval or 120))
					end
				end

				if isToggled then
					ImGui.PopStyleColor(3)
				end

				if not canBroadcast then
					ImGui.PopStyleVar()
				end

				ImGui.SameLine()

				if ImGui.Button("Recheck Qty", buttonWidth, 30) then
					state:recheckQty(char.getItemCounts)
				end

				ImGui.Separator()

				-- ----------------------------------------------------
				-- SECTION 3: Price History Table
				-- ----------------------------------------------------
				ImGui.Text("Price History:")
				ImGui.SameLine(ImGui.GetWindowWidth() - 90)
				if ImGui.Button("Clear All", 75, 0) then
					state:clearHistory()
				end

				local flags = bit32.bor(
					ImGuiTableFlags.Borders,
					ImGuiTableFlags.RowBg,
					ImGuiTableFlags.Resizable,
					ImGuiTableFlags.ScrollY,
					ImGuiTableFlags.Sortable
				)

				if ImGui.BeginTable("HistoryTable", 10, flags, 0, 0) then
					ImGui.TableSetupColumn("Rem", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.NoSort), 30)
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
							state:sortPriceHistory(function(a, b)
								local valA, valB

								if spec.ColumnIndex == 0 then
									valA = 0
									valB = 0
								elseif spec.ColumnIndex == 1 then
									valA = (a.data and a.data.item) or a.item
									valB = (b.data and b.data.item) or b.item
									valA = valA:lower()
									valB = valB:lower()
								elseif spec.ColumnIndex == 2 then
									valA = char.getItemCounts(a.item)
									valB = char.getItemCounts(b.item)
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
					end

					for index, entry in ipairs(state.priceHistory) do
						ImGui.TableNextRow()

						-- Column 0: Remove Button
						ImGui.TableSetColumnIndex(0)

						-- Draw the red remove button (X)
						ImGui.PushStyleColor(ImGuiCol.Button, 0.6, 0.1, 0.1, 1.0)
						ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.8, 0.2, 0.2, 1.0)
						ImGui.PushStyleColor(ImGuiCol.ButtonActive, 1.0, 0.3, 0.3, 1.0)
						if ImGui.Button("X##rem_" .. entry.id, 18, 18) then
							state:setItemToRemove(entry)
						end
						ImGui.PopStyleColor(3)

						-- Column 1: Item Name
						ImGui.TableSetColumnIndex(1)
						if entry.status == "Success" and entry.data then
							local sellSamples = entry.data.sellSampleSize or 0
							local limit = (state.config and state.config.lowSampleSize) or 5
							if sellSamples <= limit then
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
						ImGui.TextColored(0.4, 0.8, 1.0, 1.0, displayName)
						if ImGui.IsItemHovered() then
							ImGui.BeginTooltip()
							ImGui.Text("Left-click to view standalone price details\nRight-click to pick up item to cursor")
							ImGui.EndTooltip()
						end
						if ImGui.IsItemClicked(0) then
							state:requestCursorQuery(entry.item)
						end
						if ImGui.IsItemClicked(1) then
							chat.executeCommand(string.format('/nomodkey /itemnotify "%s" leftmouseup', entry.item))
						end

						-- Column 2: Qty (Bank)
						ImGui.TableSetColumnIndex(2)
						local count, bankCount = char.getItemCounts(entry.item)
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
							local sellPrice = (entry.data and entry.data.sellAverage) or 0
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
							if changed then
								state:updateListedPrice(entry, val)
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
							local buyPrice = (entry.data and entry.data.buyAverage) or 0
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

						-- Column 9: Details on hover
						ImGui.TableSetColumnIndex(9)
						if entry.status == "Success" then
							ImGui.TextColored(0.4, 0.8, 1.0, 1.0, "Hover")
							if ImGui.IsItemHovered() then
								renderDetailsTooltip(entry)
							end
						else
							ImGui.Text("-")
						end
					end

					state:removePendingItem()

					ImGui.EndTable()
				end

				ImGui.EndTabItem()
			end

			if ImGui.BeginTabItem("Communication") then
				ImGui.TextColored(0.4, 0.8, 1.0, 1.0, "Tells Received Log:")
				ImGui.Separator()
				ImGui.Spacing()

				-- Add inline configuration for reply message
				ImGui.PushItemWidth(-1)
				local valReply, changedReply = ImGui.InputText("##quick_reply_msg", state.config.replyMessage or "Sure, near Parcel")
				if changedReply then
					state:updateConfigKey("replyMessage", valReply)
				end
				ImGui.PopItemWidth()

				ImGui.Spacing()

				local tellFlags = bit32.bor(
					ImGuiTableFlags.Borders,
					ImGuiTableFlags.RowBg,
					ImGuiTableFlags.Resizable,
					ImGuiTableFlags.ScrollY
				)

				if ImGui.BeginTable("TellsTable", 3, tellFlags, 0, 0) then
					ImGui.TableSetupColumn("From", ImGuiTableColumnFlags.WidthFixed, 90)
					ImGui.TableSetupColumn("Message", ImGuiTableColumnFlags.WidthStretch)
					ImGui.TableSetupColumn("Operations", ImGuiTableColumnFlags.WidthFixed, 85)
					ImGui.TableHeadersRow()

					for index, tell in ipairs(state.receivedTells) do
						ImGui.TableNextRow()

						-- Column 0: From
						ImGui.TableSetColumnIndex(0)
						ImGui.Text(tell.sender or "Unknown")

						-- Column 1: Message
						ImGui.TableSetColumnIndex(1)
						ImGui.TextWrapped(tell.message or "")

						-- Highlight listed items matched in the message
						local msgLower = (tell.message or ""):lower()
						local matched = {}
						local totalPrice = 0
						for _, entry in ipairs(state.priceHistory) do
							if entry.status == "Success" then
								local itemName = (entry.data and entry.data.item) or entry.item
								if itemName and itemName ~= "" then
									if string.find(msgLower, itemName:lower(), 1, true) then
										local price = entry.listedPrice or 0
										table.insert(matched, string.format("\"%s\" for %d pp", itemName, price))
										totalPrice = totalPrice + price
									end
								end
							end
						end
						if #matched > 0 then
							ImGui.PushStyleColor(ImGuiCol.Text, 0.4, 1.0, 0.4, 1.0)
							ImGui.TextWrapped(string.format(" (interested in %s, expect a total of %d pp in the Trade Window!)", table.concat(matched, ", "), totalPrice))
							ImGui.PopStyleColor()
						end

						-- Column 2: Operations
						ImGui.TableSetColumnIndex(2)

						-- Done/Check button
						ImGui.PushStyleColor(ImGuiCol.Button, 0.1, 0.5, 0.1, 1.0)
						ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.2, 0.7, 0.2, 1.0)
						ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.3, 0.9, 0.3, 1.0)
						if ImGui.Button("V##done_" .. index, 30, 18) then
							state:setTellToRemove(tell)
						end
						ImGui.PopStyleColor(3)

						ImGui.SameLine()

						-- Reply button
						if ImGui.Button("Reply##rep_" .. index, 42, 18) then
							local replyCmd = string.format("/tell %s %s", tell.sender or "Unknown", state.config.replyMessage or "Sure, near Parcel")
							chat.executeCommand(replyCmd)
						end
					end

					state:removePendingTell()

					ImGui.EndTable()
				end

				ImGui.EndTabItem()
			end



			-- Configuration Tab (Colored Green)
			ImGui.PushStyleColor(ImGuiCol.Tab, 0.1, 0.4, 0.1, 0.8)
			ImGui.PushStyleColor(ImGuiCol.TabHovered, 0.2, 0.6, 0.2, 0.8)
			ImGui.PushStyleColor(ImGuiCol.TabActive, 0.3, 0.8, 0.3, 0.8)

			if ImGui.BeginTabItem("Configuration") then
				ImGui.PopStyleColor(3)

				ImGui.TextColored(0.4, 0.8, 1.0, 1.0, "Configuration Settings:")
				ImGui.Separator()
				ImGui.Spacing()

				ImGui.Text("Low Sample Size Warning Limit:")
				ImGui.PushItemWidth(100)
				local valLimit, changedLimit = ImGui.InputInt("##low_sample_size", state.config.lowSampleSize or 5, 1, 5)
				if valLimit < 0 then
					valLimit = 0
				end
				if changedLimit then
					state:updateConfigKey("lowSampleSize", valLimit)
				end
				ImGui.PopItemWidth()

				ImGui.Spacing()
				ImGui.Text("Broadcast Debounce Delays (milliseconds):")
				
				ImGui.AlignTextToFramePadding()
				ImGui.Text("Min Delay:")
				ImGui.SameLine()
				ImGui.PushItemWidth(100)
				local valMin, changedMin = ImGui.InputInt("##debounce_min", state.config.debounceMin or 400, 10, 100)
				if valMin < 0 then
					valMin = 0
				end
				if changedMin then
					state:updateConfigKey("debounceMin", valMin)
				end
				ImGui.PopItemWidth()

				ImGui.SameLine(180)
				ImGui.AlignTextToFramePadding()
				ImGui.Text("Max Delay:")
				ImGui.SameLine()
				ImGui.PushItemWidth(100)
				local valMax, changedMax = ImGui.InputInt("##debounce_max", state.config.debounceMax or 600, 10, 100)
				if valMax < 0 then
					valMax = 0
				end
				if changedMax then
					state:updateConfigKey("debounceMax", valMax)
				end
				ImGui.PopItemWidth()

				ImGui.Spacing()
				ImGui.Text("Default Reply Message:")
				ImGui.PushItemWidth(-1)
				local valReply, changedReply = ImGui.InputText("##default_reply_msg", state.config.replyMessage or "Sure, near Parcel")
				if changedReply and valReply ~= "" then
					state:updateConfigKey("replyMessage", valReply)
				end
				ImGui.PopItemWidth()

				ImGui.Spacing()
				ImGui.Text("Broadcast Interval (seconds):")
				ImGui.PushItemWidth(-1)
				local valBroadcastInterval, changedBroadcastInterval = ImGui.SliderInt("##broadcast_interval", state.config.broadcastInterval or 120, 120, 1200, "%d seconds")
				if changedBroadcastInterval then
					state:updateConfigKey("broadcastInterval", valBroadcastInterval)
				end
				ImGui.PopItemWidth()

				ImGui.Spacing()
				ImGui.Text("Default Item Price (pp) for No-Price Adds:")
				ImGui.PushItemWidth(120)
				local valDefaultPrice, changedDefaultPrice = ImGui.InputInt("##default_item_price", state.config.defaultPlatPrice or 1000, 50, 500)
				if valDefaultPrice < 0 then
					valDefaultPrice = 0
				end
				if changedDefaultPrice then
					state:updateConfigKey("defaultPlatPrice", valDefaultPrice)
				end
				ImGui.PopItemWidth()

				ImGui.Spacing()
				local valDebug, changedDebug = ImGui.Checkbox("Enable Debug Logging", state.config.debug or false)
				if changedDebug then
					state:updateConfigKey("debug", valDebug)
				end

				ImGui.EndTabItem()
			else
				ImGui.PopStyleColor(3)
			end

			ImGui.EndTabBar()
		end
	end
	ImGui.End()

	renderCursorQueryWindow(state)
end

-- Helper function to render a standalone window for the queried cursor item details
function renderCursorQueryWindow(state)
	if not state.showCursorQueryWindow or not state.cursorQueryResult then
		return
	end

	ImGui.SetNextWindowSize(380, 420, ImGuiCond.FirstUseEver)
	local open, shouldDraw = ImGui.Begin("Price Details: " .. state.cursorQueryResult.item, state.showCursorQueryWindow)
	if state.showCursorQueryWindow ~= open then
		state:setShowCursorQueryWindow(open)
	end

	if shouldDraw then
		local result = state.cursorQueryResult
		ImGui.TextColored(0.4, 0.8, 1.0, 1.0, "Item: " .. result.item)
		ImGui.Separator()

		if result.status == "Searching..." then
			ImGui.TextColored(1.0, 0.8, 0.2, 1.0, "Searching for pricing data...")
		elseif result.status == "Success" and result.data then
			local data = result.data
			ImGui.Text(string.format("Sellers Avg: %.1f pp (Samples: %d)", data.sellAverage or 0, data.sellSampleSize or 0))
			ImGui.Text(string.format("Buyers Avg: %.1f pp (Samples: %d)", data.buyAverage or 0, data.buySampleSize or 0))
			ImGui.Spacing()

			local function drawDetailsTable(title, logArray)
				ImGui.TextColored(0.4, 1.0, 0.4, 1.0, title)
				if not logArray or #logArray == 0 then
					ImGui.TextDisabled("   No recent transactions.")
					return
				end

				local tFlags = bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg)
				if ImGui.BeginTable(title .. "CursorTable", 4, tFlags, 0, 0) then
					ImGui.TableSetupColumn("Trader", ImGuiTableColumnFlags.WidthStretch)
					ImGui.TableSetupColumn("Plat", ImGuiTableColumnFlags.WidthFixed, 55)
					ImGui.TableSetupColumn("Krono", ImGuiTableColumnFlags.WidthFixed, 45)
					ImGui.TableSetupColumn("Age", ImGuiTableColumnFlags.WidthFixed, 70)
					ImGui.TableHeadersRow()

					local limit = math.min(#logArray, 5)
					for i = 1, limit do
						local log = logArray[i]
						ImGui.TableNextRow()
						ImGui.TableSetColumnIndex(0)
						ImGui.Text(log.auctioneer or "Unknown")
						ImGui.TableSetColumnIndex(1)
						ImGui.Text(tostring(math.floor(log.platPrice or 0)))
						ImGui.TableSetColumnIndex(2)
						ImGui.Text(tostring(log.kronoPrice or 0))
						ImGui.TableSetColumnIndex(3)
						ImGui.TextColored(0.7, 0.7, 0.7, 1.0, util.getRelativeTimeString(log.datetime))
					end
					ImGui.EndTable()
				end
			end

			drawDetailsTable("Recent Sell Offers (WTS)", data.recentSellSales)
			ImGui.Spacing()
			drawDetailsTable("Recent Buy Offers (WTB)", data.recentBuySales)
			ImGui.Spacing()
			ImGui.Separator()
			ImGui.Spacing()

			-- Check if already listed in Trade list
			local isAlreadyListed = false
			for _, hEntry in ipairs(state.priceHistory) do
				if hEntry.item:lower() == result.item:lower() then
					isAlreadyListed = true
					break
				end
			end

			if isAlreadyListed then
				ImGui.PushStyleVar(ImGuiStyleVar.Alpha, 0.5)
			end
			if ImGui.Button(isAlreadyListed and "Already Listed in Trade" or "Add to Trade List", -1, 30) and not isAlreadyListed then
				queueSearch(state, result.item)
			end
			if isAlreadyListed then
				ImGui.PopStyleVar()
			end

		else
			ImGui.TextColored(1.0, 0.3, 0.3, 1.0, "Status: " .. tostring(result.status or "Error"))
			ImGui.Spacing()

			-- Allow adding even if search failed (with default price)
			local isAlreadyListed = false
			for _, hEntry in ipairs(state.priceHistory) do
				if hEntry.item:lower() == result.item:lower() then
					isAlreadyListed = true
					break
				end
			end

			if isAlreadyListed then
				ImGui.PushStyleVar(ImGuiStyleVar.Alpha, 0.5)
			end
			if ImGui.Button(isAlreadyListed and "Already Listed in Trade" or "Add with Default Price", -1, 30) and not isAlreadyListed then
				local defaultPrice = (state.config and state.config.defaultPlatPrice) or 1000
				state:addHistoryEntryWithDefaultPrice(result.item, defaultPrice, dto)
			end
			if isAlreadyListed then
				ImGui.PopStyleVar()
			end
		end
	end
	ImGui.End()
end

return ui
