local ImGui = require("ImGui")
local mq = require("mq")
local theme = require("modules.theme")

local ui = {}

local char
local dto
local chat
local util

local function textColored(color, text)
	ImGui.TextColored(color[1], color[2], color[3], color[4], text)
end

local function pushStyleColor(col, color)
	ImGui.PushStyleColor(col, color[1], color[2], color[3], color[4])
end

function ui.setup(charModule, dtoModule, chatModule, utilModule)
	char = charModule
	dto = dtoModule
	chat = chatModule
	util = utilModule
end

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

function ui.getAuctionLines(state, useLinks)
	local segments = generateItemSegments(state, useLinks)
	if #segments == 0 then
		return {}
	end

	local lines = {}
	local currentLineItems = {}
	local prefix = (state.config.broadcastCommand and state.config.broadcastCommand ~= "") and state.config.broadcastCommand or "/auction"

	for i, segment in ipairs(segments) do
		table.insert(currentLineItems, segment)
		if #currentLineItems == 4 or i == #segments then
			table.insert(lines, string.format("%s WTS %s", prefix, table.concat(currentLineItems, ", ")))
			currentLineItems = {}
		end
	end

	return lines
end

local function queueSearch(state, itemName)
	state:queueSearch(itemName, dto)
end

local function drawTransactionTable(tableNameSuffix, title, logArray)
	textColored(theme.text.success, title)
	if not logArray or #logArray == 0 then
		ImGui.TextDisabled("   No recent transactions.")
		return
	end

	local tFlags = bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg)
	if ImGui.BeginTable(title .. tableNameSuffix, 4, tFlags, 0, 0) then
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
			textColored(theme.text.muted, util.getRelativeTimeString(log.datetime))
		end
		ImGui.EndTable()
	end
end

local function renderDetailsTooltip(entry)
	if not entry or not entry.data then
		return
	end
	local data = entry.data

	if ImGui.BeginTooltip() then
		textColored(theme.text.info, string.format("Market Details: %s", data.item or "Unknown"))
		ImGui.Separator()
		ImGui.Text(string.format("Sellers Avg: %.1f pp (Samples: %d)", data.sellAverage or 0, data.sellSampleSize or 0))
		ImGui.Text(string.format("Buyers Avg: %.1f pp (Samples: %d)", data.buyAverage or 0, data.buySampleSize or 0))
		ImGui.Spacing()

		drawTransactionTable("TooltipTable", "Recent Sell Offers (WTS)", data.recentSellSales)
		ImGui.Spacing()
		drawTransactionTable("TooltipTable", "Recent Buy Offers (WTB)", data.recentBuySales)
		ImGui.EndTooltip()
	end
end

local function renderCursorQueryWindow(state)
	if not state.showCursorQueryWindow or not state.cursorQueryResult then
		return
	end

	ImGui.SetNextWindowSize(380, 420, ImGuiCond.FirstUseEver)
	local open, shouldDraw = ImGui.Begin("Price Details: " .. state.cursorQueryResult.item, state.showCursorQueryWindow)
	if state.showCursorQueryWindow ~= open then
		state.showCursorQueryWindow = open
	end

	if shouldDraw then
		local result = state.cursorQueryResult

		local isAlreadyListed = false
		for _, hEntry in ipairs(state.priceHistory) do
			if hEntry.item:lower() == result.item:lower() then
				isAlreadyListed = true
				break
			end
		end

		textColored(theme.text.info, "Item: " .. result.item)
		ImGui.Separator()

		if result.status == "Searching..." then
			textColored(theme.text.warning, "Searching for pricing data...")
		elseif result.status == "Success" and result.data then
			local data = result.data
			ImGui.Text(string.format("Sellers Avg: %.1f pp (Samples: %d)", data.sellAverage or 0, data.sellSampleSize or 0))
			ImGui.Text(string.format("Buyers Avg: %.1f pp (Samples: %d)", data.buyAverage or 0, data.buySampleSize or 0))
			ImGui.Spacing()

			drawTransactionTable("CursorTable", "Recent Sell Offers (WTS)", data.recentSellSales)
			ImGui.Spacing()
			drawTransactionTable("CursorTable", "Recent Buy Offers (WTB)", data.recentBuySales)
			ImGui.Spacing()
			ImGui.Separator()
			ImGui.Spacing()

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
			textColored(theme.text.error, "Status: " .. tostring(result.status or "Error"))
			ImGui.Spacing()

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

function ui.render(state)
	if not state.openGUI then
		return
	end

	theme.apply(state)

	ImGui.SetNextWindowSize(550, 520, ImGuiCond.FirstUseEver)

	local open, shouldDraw = ImGui.Begin("Frostreaver Trade Tools", state.openGUI)
	if state.openGUI ~= open then
		state.openGUI = open
	end

	if shouldDraw then
		if ImGui.BeginTabBar("PriceCheckTabBar") then
			if ImGui.BeginTabItem("Your Items") then
				ImGui.BeginDisabled(state.isBroadcastingToggled)
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
						textColored(theme.text.info, "Last Updated: " .. readableTime)
					end
					if state.bulkKronoRate then
						local kronoInt = math.floor(state.bulkKronoRate + 0.5)
						textColored(theme.text.gold, "Current Krono Price: " .. util.formatNumber(kronoInt) .. " pp")
					end
					ImGui.Spacing()
				end

				ImGui.Separator()
				ImGui.Text("BULK Price History:")
				ImGui.SameLine(ImGui.GetWindowWidth() - 95)
				local hasBulkPerformed = (state.bulkLastUpdated ~= nil)
				local itemsToSearchCount = 0
				if hasBulkPerformed then
					for _, entry in ipairs(state.bulkPriceHistory) do
						local alreadyListed = false
						for _, hEntry in ipairs(state.priceHistory) do
							if hEntry.item:lower() == entry.item:lower() then
								alreadyListed = true
								break
							end
						end
						if not alreadyListed then
							if entry.status == "Success" and entry.hasData and entry.medianPlatPrice then
								itemsToSearchCount = itemsToSearchCount + 1
							end
						end
					end
				end

				if not hasBulkPerformed then
					ImGui.PushStyleVar(ImGuiStyleVar.Alpha, 0.5)
				end
				if ImGui.Button("Add All##Bulk", 80, 0) and hasBulkPerformed then
					state:addAllBulkItems(dto)
				end
				if ImGui.IsItemHovered() then
					if ImGui.BeginTooltip() then
						if hasBulkPerformed then
							local estTime = itemsToSearchCount
							ImGui.Text(string.format("Add all remaining items to the trade list.\nEstimated query time: %d seconds (%d items to search)", estTime, itemsToSearchCount))
						else
							ImGui.Text("Please perform a bulk price check first.")
						end
						ImGui.EndTooltip()
					end
				end
				if not hasBulkPerformed then
					ImGui.PopStyleVar()
				end

				local flags = bit32.bor(
					ImGuiTableFlags.Borders,
					ImGuiTableFlags.RowBg,
					ImGuiTableFlags.Resizable,
					ImGuiTableFlags.ScrollY,
					ImGuiTableFlags.Sortable
				)

				if ImGui.BeginTable("BulkHistoryTable", 5, flags, 0, 0) then
					ImGui.TableSetupColumn("Item Name", ImGuiTableColumnFlags.WidthStretch)
					ImGui.TableSetupColumn("Qty (Bank)", ImGuiTableColumnFlags.WidthFixed, 70)
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
									local countA, bankA = char.getItemCounts(a.item)
									local countB, bankB = char.getItemCounts(b.item)
									valA = countA + bankA
									valB = countB + bankB
								elseif spec.ColumnIndex == 2 then
									valA = (a.status == "Success" and a.hasData and a.medianPlatPrice) or -1
									valB = (b.status == "Success" and b.hasData and b.medianPlatPrice) or -1
								elseif spec.ColumnIndex == 3 then
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

						local vValue = char.getItemValue(entry.item)
						local isVendorBetter = false
						if entry.status == "Success" and entry.hasData and entry.medianPlatPrice then
							local vendorPlatPrice = vValue / 1000
							if vendorPlatPrice >= entry.medianPlatPrice then
								isVendorBetter = true
							end
						end

						ImGui.TableSetColumnIndex(0)
						if isVendorBetter then
							textColored(theme.text.gold, entry.item)
							if ImGui.IsItemHovered() then
								if ImGui.BeginTooltip() then
									ImGui.Text("Vendor sell price is higher or equal to market median price!")
									ImGui.EndTooltip()
								end
							end
						else
							ImGui.Text(entry.item)
						end

						ImGui.TableSetColumnIndex(1)
						local count, bankCount = char.getItemCounts(entry.item)
						ImGui.Text(string.format("%d (%d)", count, bankCount))

						ImGui.TableSetColumnIndex(2)
						if entry.status == "Searching..." then
							textColored(theme.text.warning, entry.status)
						elseif entry.status == "Success" then
							if entry.hasData and entry.medianPlatPrice then
								textColored(theme.text.success, string.format("%s pp", util.formatNumber(math.floor(entry.medianPlatPrice))))
							else
								textColored(theme.text.error, "No price found")
							end
						elseif entry.status == "Not Checked" then
							textColored(theme.text.disabled, "-")
						else
							textColored(theme.text.error, entry.status or "N/A")
						end

						ImGui.TableSetColumnIndex(3)
						if vValue > 0 then
							if isVendorBetter then
								textColored(theme.text.success, util.formatVendorPrice(vValue))
							else
								textColored(theme.text.muted, util.formatVendorPrice(vValue))
							end
						else
							ImGui.Text("-")
						end

						ImGui.TableSetColumnIndex(4)
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
							pushStyleColor(ImGuiCol.Button, theme.style.buttonDanger.bg)
							pushStyleColor(ImGuiCol.ButtonHovered, theme.style.buttonDanger.hovered)
							pushStyleColor(ImGuiCol.ButtonActive, theme.style.buttonDanger.active)

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
					ImGui.EndTable()
				end

				ImGui.EndDisabled()
				ImGui.EndTabItem()
			end

			if ImGui.BeginTabItem("Trade") then
				ImGui.BeginDisabled(state.isBroadcastingToggled)
				ImGui.Text("Pricing & Sales Tool:")

				-- Channel command configured in settings now

				local previewLines = ui.getAuctionLines(state, false)
				local numSaleItems = 0
				for _, entry in ipairs(state.priceHistory) do
					if entry.status == "Success" then
						numSaleItems = numSaleItems + 1
					end
				end

				ImGui.TextColored(theme.text.info[1], theme.text.info[2], theme.text.info[3], theme.text.info[4], "Broadcast Status & Checklist:")

				local interval = state.config.broadcastInterval or 120

				local checklistHeight = state.isBroadcastingToggled and 100 or 200
				ImGui.BeginChild("TimelineChecklist", -1, checklistHeight, true)
				if numSaleItems == 0 then
					ImGui.TextDisabled("   No items in your Sale List. Add items to start broadcasting.")
				elseif not state.isBroadcastingToggled then
					textColored(theme.text.muted, "   Broadcasting is turned off. Press 'Broadcast' below to begin.")
					local cmd = (state.config.broadcastCommand and state.config.broadcastCommand ~= "") and state.config.broadcastCommand or "/auction"
					local previewTimeline = util.buildBroadcastTimeline(previewLines, interval, cmd)
					if #previewTimeline > 0 then
						ImGui.Spacing()
						textColored(theme.text.info, "   Queue Preview:")
						for _, step in ipairs(previewTimeline) do
							if step.type == "send" then
								ImGui.TextDisabled("     " .. step.description)
							elseif step.type == "pause" then
								if step.reason == "Anti-Spam Pause" then
									textColored(theme.text.warning, "     " .. step.description)
								else
									textColored(theme.text.gold, "     " .. step.description)
								end
							end
						end
					end
				else
					if state.timeline and #state.timeline > 0 then
						local currentIdx = state.currentStepIndex or 1
						local step = state.timeline[currentIdx]
						if step then
							local remaining = math.max(0, (state.nextBroadcastTime or 0) - mq.gettime()) / 1000
							local duration = (step.type == "send") and 1.0 or step.duration
							local progress = math.max(0.0, math.min(1.0, (duration - remaining) / duration))

							local overlay
							if step.type == "send" then
								overlay = string.format("Step %d/%d: %s", currentIdx, #state.timeline, step.description)
							else
								overlay = string.format("Step %d/%d: %s (%ds remaining)", currentIdx, #state.timeline, step.description, math.ceil(remaining))
							end

							local barColor
							if step.type == "send" then
								barColor = theme.text.success
							elseif step.reason == "Anti-Spam Pause" then
								barColor = theme.text.warning
							else
								barColor = theme.text.info
							end

							ImGui.Spacing()
							local barWidth = ImGui.GetContentRegionAvail()
							local startY = ImGui.GetCursorPosY()

							pushStyleColor(ImGuiCol.PlotHistogram, barColor)
							ImGui.ProgressBar(progress, ImVec2(-1, 26), "")
							ImGui.PopStyleColor()

							local endY = ImGui.GetCursorPosY()

							-- Overlay high-contrast centered text on top of the bar
							local textWidth = ImGui.CalcTextSize(overlay)
							local posX = (barWidth - textWidth) / 2
							if posX < 0 then posX = 0 end

							ImGui.SetCursorPosY(startY + 4)
							ImGui.SetCursorPosX(posX)
							textColored(theme.text.gold, overlay)

							ImGui.SetCursorPosY(endY)

							-- Now calculate and render the second progress bar (Total Cycle Progress)
							local totalCycleTime = 0
							local elapsedCycleTime = 0
							for i, tStep in ipairs(state.timeline) do
								local stepDuration = (tStep.type == "send") and 1.0 or tStep.duration
								totalCycleTime = totalCycleTime + stepDuration

								if i < currentIdx then
									elapsedCycleTime = elapsedCycleTime + stepDuration
								elseif i == currentIdx then
									elapsedCycleTime = elapsedCycleTime + (progress * stepDuration)
								end
							end

							local totalProgress = totalCycleTime > 0 and (elapsedCycleTime / totalCycleTime) or 0.0
							local totalOverlay = string.format("Total Progress: %d%% (%d/%ds)", math.floor(totalProgress * 100), math.floor(elapsedCycleTime), math.floor(totalCycleTime))

							ImGui.Spacing()
							local startY2 = ImGui.GetCursorPosY()

							pushStyleColor(ImGuiCol.PlotHistogram, theme.text.muted)
							ImGui.ProgressBar(totalProgress, ImVec2(-1, 22), "")
							ImGui.PopStyleColor()

							local endY2 = ImGui.GetCursorPosY()

							local textWidth2 = ImGui.CalcTextSize(totalOverlay)
							local posX2 = (barWidth - textWidth2) / 2
							if posX2 < 0 then posX2 = 0 end

							ImGui.SetCursorPosY(startY2 + 2)
							ImGui.SetCursorPosX(posX2)
							textColored(theme.text.muted, totalOverlay)

							ImGui.SetCursorPosY(endY2)
							ImGui.Dummy(ImVec2(1, 1))
						else
							textColored(theme.text.muted, "   Preparing next broadcast cycle...")
						end
					else
						textColored(theme.text.muted, "   Preparing next broadcast cycle...")
					end
				end
				ImGui.EndChild()
				ImGui.Spacing()

				ImGui.EndDisabled() -- Stop disabling for broadcast button

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
					buttonLabel = "Stop Broadcast"
					pushStyleColor(ImGuiCol.Button, theme.style.buttonDanger.bg)
					pushStyleColor(ImGuiCol.ButtonHovered, theme.style.buttonDanger.hovered)
					pushStyleColor(ImGuiCol.ButtonActive, theme.style.buttonDanger.active)
				else
					buttonLabel = string.format("Broadcast via %s", (state.config.broadcastCommand and state.config.broadcastCommand ~= "" and state.config.broadcastCommand or "/auction"))
				end

				if ImGui.Button(buttonLabel, buttonWidth, 30) and canBroadcast then
					if isToggled then
						state.isBroadcastingToggled = false
						state.timeline = nil
					else
						state.isBroadcastingToggled = true
						state.timeline = nil
						state.currentStepIndex = 1
						state.nextBroadcastTime = 0
					end
				end

				if isToggled then
					ImGui.PopStyleColor(3)
				end

				if not canBroadcast then
					ImGui.PopStyleVar()
				end

				ImGui.SameLine()

				ImGui.BeginDisabled(state.isBroadcastingToggled) -- Resume disabling for list/recheck actions
				if ImGui.Button("Recheck Qty", buttonWidth, 30) then
					state:recheckQty(char.getItemCounts)
				end

				-- Status details are handled above in the timeline legend block.

				ImGui.Separator()

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

						ImGui.TableSetColumnIndex(0)
						pushStyleColor(ImGuiCol.Button, theme.style.buttonRemove.bg)
						pushStyleColor(ImGuiCol.ButtonHovered, theme.style.buttonRemove.hovered)
						pushStyleColor(ImGuiCol.ButtonActive, theme.style.buttonRemove.active)
						if ImGui.Button("X##rem_" .. entry.id, 18, 18) then
							state.itemToRemove = entry
						end
						ImGui.PopStyleColor(3)

						ImGui.TableSetColumnIndex(1)
						if entry.status == "Success" and entry.data then
							local sellSamples = entry.data.sellSampleSize or 0
							local limit = (state.config and state.config.lowSampleSize) or 5
							if sellSamples <= limit then
								textColored(theme.text.error, "[!] ")
								if ImGui.IsItemHovered() then
									if ImGui.BeginTooltip() then
										ImGui.Text(string.format("Small sample size: only %d sample(s) available", sellSamples))
										ImGui.EndTooltip()
									end
								end
								ImGui.SameLine()
							end
						end
						local displayName = (entry.data and entry.data.item) or entry.item
						textColored(theme.text.info, displayName)
						if ImGui.IsItemHovered() then
							if ImGui.BeginTooltip() then
								ImGui.Text("Right-click to pick up item to cursor")
								ImGui.EndTooltip()
							end
						end
						if ImGui.IsItemClicked(1) then
							chat.executeCommand(string.format('/nomodkey /itemnotify "%s" leftmouseup', entry.item))
						end

						ImGui.TableSetColumnIndex(2)
						local count, bankCount = char.getItemCounts(entry.item)
						ImGui.Text(string.format("%d (%d)", count, bankCount))

						ImGui.TableSetColumnIndex(3)
						if entry.status ~= "Success" then
							if entry.status == "Searching..." then
								textColored(theme.text.warning, entry.status)
							else
								textColored(theme.text.error, entry.status)
							end
						else
							local sellPrice = (entry.data and entry.data.sellAverage) or 0
							textColored(theme.text.success, string.format("%.1f pp", sellPrice))
						end

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

						local highestWTS, lowestWTS, highestWTB = getPriceStats(entry)

						ImGui.TableSetColumnIndex(5)
						if entry.status == "Success" and highestWTS then
							textColored(theme.text.green, string.format("%d pp", math.floor(highestWTS)))
						else
							ImGui.Text("-")
						end

						ImGui.TableSetColumnIndex(6)
						if entry.status == "Success" and lowestWTS then
							textColored(theme.text.green, string.format("%d pp", math.floor(lowestWTS)))
						else
							ImGui.Text("-")
						end

						ImGui.TableSetColumnIndex(7)
						if entry.status == "Success" then
							local buyPrice = (entry.data and entry.data.buyAverage) or 0
							textColored(theme.text.orange, string.format("%.1f pp", buyPrice))
						else
							ImGui.Text("-")
						end

						ImGui.TableSetColumnIndex(8)
						if entry.status == "Success" and highestWTB then
							textColored(theme.text.orange, string.format("%d pp", math.floor(highestWTB)))
						else
							ImGui.Text("-")
						end

						ImGui.TableSetColumnIndex(9)
						if entry.status == "Success" then
							textColored(theme.text.info, "Hover")
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
				ImGui.EndDisabled()

				ImGui.EndTabItem()
			end

			if ImGui.BeginTabItem("Communication") then
				textColored(theme.text.info, "Tells Received Log:")
				ImGui.Separator()
				ImGui.Spacing()

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

						ImGui.TableSetColumnIndex(0)
						ImGui.Text(tell.sender or "Unknown")

						ImGui.TableSetColumnIndex(1)
						ImGui.TextWrapped(tell.message or "")

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
							pushStyleColor(ImGuiCol.Text, theme.text.success)
							ImGui.TextWrapped(string.format(" (interested in %s, expect a total of %d pp in the Trade Window!)", table.concat(matched, ", "), totalPrice))
							ImGui.PopStyleColor()
						end

						ImGui.TableSetColumnIndex(2)

						pushStyleColor(ImGuiCol.Button, theme.style.buttonDone.bg)
						pushStyleColor(ImGuiCol.ButtonHovered, theme.style.buttonDone.hovered)
						pushStyleColor(ImGuiCol.ButtonActive, theme.style.buttonDone.active)
						if ImGui.Button("V##done_" .. index, 30, 18) then
							state.tellToRemove = tell
						end
						ImGui.PopStyleColor(3)

						ImGui.SameLine()

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

			pushStyleColor(ImGuiCol.Tab, theme.style.tabConfig.bg)
			pushStyleColor(ImGuiCol.TabHovered, theme.style.tabConfig.hovered)
			pushStyleColor(ImGuiCol.TabActive, theme.style.tabConfig.active)

			if ImGui.BeginTabItem("Configuration") then
				ImGui.BeginDisabled(state.isBroadcastingToggled)
				ImGui.PopStyleColor(3)

				textColored(theme.text.info, "Configuration Settings:")
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
				ImGui.Text("Chat Channel / Command:")
				ImGui.PushItemWidth(-1)
				local valCmd, changedCmd = ImGui.InputText("##chat_command", state.config.broadcastCommand or "/auction")
				if changedCmd and valCmd ~= "" then
					state:updateConfigKey("broadcastCommand", valCmd)
				end
				ImGui.PopItemWidth()

				ImGui.Spacing()
				ImGui.Text("UI Color Theme Preset:")
				ImGui.PushItemWidth(-1)
				local themeNames = { "Default", "Solarized Dark", "Nord", "Pastel", "Solarized Light", "Windows 95" }
				local currentThemeName = state.config.themeName or "Default"
				local currentIdx = 1
				for idx, name in ipairs(themeNames) do
					if name == currentThemeName then
						currentIdx = idx
						break
					end
				end
				local newIdx = ImGui.Combo("##theme_preset", currentIdx, themeNames)
				if newIdx ~= currentIdx then
					state:updateConfigKey("themeName", themeNames[newIdx])
				end
				ImGui.PopItemWidth()

				ImGui.Spacing()
				local valDebug, changedDebug = ImGui.Checkbox("Enable Debug Logging", state.config.debug or false)
				if changedDebug then
					state:updateConfigKey("debug", valDebug)
				end

				ImGui.EndDisabled()
				ImGui.EndTabItem()
			else
				ImGui.PopStyleColor(3)
			end

			if ImGui.BeginTabItem("Changelog") then
				textColored(theme.text.info, "Changelog:")
				ImGui.Separator()
				ImGui.Spacing()

				if ImGui.BeginChild("ChangelogScroll", 0, 0, true) then
					local text = state.changelog or "No changelog available."
					for line in string.gmatch(text .. "\n", "(.-)\r?\n") do
						if line == "" then
							ImGui.Spacing()
						elseif line:sub(1, 3) == "###" then
							textColored(theme.text.info, line)
						elseif line:sub(1, 2) == "##" then
							textColored(theme.text.success, line)
						elseif line:sub(1, 1) == "#" then
							textColored(theme.text.gold, line)
						else
							ImGui.TextUnformatted(line)
						end
					end
					ImGui.EndChild()
				end
				ImGui.EndTabItem()
			end

			ImGui.EndTabBar()
		end
	end
	ImGui.End()

	renderCursorQueryWindow(state)

	theme.pop()
end

return ui
