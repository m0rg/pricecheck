local mq = require("mq")
local logger = require("pricecheck.modules.log")

local stateManager = {}

function stateManager.new(loadedHistory, loadedConfig, initialBulkHistory)
	local rawState = {
		openGUI = true,
		isSearching = false,
		broadcastCommand = "/auction",
		priceHistory = loadedHistory,
		config = loadedConfig,
		receivedTells = {},
		activeDetailEntry = nil,
		searchQueue = {},
		broadcastQueue = {},
		bulkPriceHistory = initialBulkHistory,
		bulkLastUpdated = nil,
		bulkKronoRate = nil,
		bulkQueue = {},
		isBroadcastingToggled = false,
		nextToggleBroadcastTime = nil,
		saveRequested = false,
		configSaveRequested = false,
		itemToRemove = nil,
		tellToRemove = nil,
		cursorQueryResult = nil,
		showCursorQueryWindow = false,
		cursorQueryPending = false,
	}

	local self = {
		_data = rawState
	}

	local mt = {
		__index = function(t, key)
			-- Check if the key is a method on stateManager
			if stateManager[key] then
				return stateManager[key]
			end
			-- Otherwise return from the rawState data
			return rawState[key]
		end,
		__newindex = function(t, key, value)
			error(string.format("Direct state mutation attempted: state.%s = %s\n%s", tostring(key), tostring(value), debug.traceback()))
		end
	}
	return setmetatable(self, mt)
end

function stateManager:setOpenGUI(open)
	if self._data.openGUI ~= open then
		logger.log("\ar[PriceCheck State]\ax openGUI changed from %s to %s", tostring(self._data.openGUI), tostring(open))
		self._data.openGUI = open
	end
end

function stateManager:setSearching(searching)
	if self._data.isSearching ~= searching then
		logger.log("\ar[PriceCheck State]\ax isSearching changed from %s to %s", tostring(self._data.isSearching), tostring(searching))
		self._data.isSearching = searching
	end
end

function stateManager:setBulkSearching(searching)
	if self._data.isBulkSearching ~= searching then
		logger.log("\ar[PriceCheck State]\ax isBulkSearching changed from %s to %s", tostring(self._data.isBulkSearching), tostring(searching))
		self._data.isBulkSearching = searching
	end
end

function stateManager:setBroadcastingToggled(toggled)
	if self._data.isBroadcastingToggled ~= toggled then
		logger.log("\ar[PriceCheck State]\ax isBroadcastingToggled changed from %s to %s", tostring(self._data.isBroadcastingToggled), tostring(toggled))
		self._data.isBroadcastingToggled = toggled
	end
end

function stateManager:setNextToggleBroadcastTime(t)
	if self._data.nextToggleBroadcastTime ~= t then
		logger.log("\ar[PriceCheck State]\ax nextToggleBroadcastTime changed from %s to %s", tostring(self._data.nextToggleBroadcastTime), tostring(t))
		self._data.nextToggleBroadcastTime = t
	end
end

function stateManager:setBroadcastCommand(cmd)
	if self._data.broadcastCommand ~= cmd then
		logger.log("\ar[PriceCheck State]\ax broadcastCommand changed from %q to %q", tostring(self._data.broadcastCommand), tostring(cmd))
		self._data.broadcastCommand = cmd
	end
end

function stateManager:setActiveDetailEntry(entry)
	if self._data.activeDetailEntry ~= entry then
		local oldName = self._data.activeDetailEntry and self._data.activeDetailEntry.item or "nil"
		local newName = entry and entry.item or "nil"
		logger.log("\ar[PriceCheck State]\ax activeDetailEntry changed from %s to %s", oldName, newName)
		self._data.activeDetailEntry = entry
	end
end

function stateManager:requestSave()
	if not self._data.saveRequested then
		logger.log("\ar[PriceCheck State]\ax saveRequested set to true")
		self._data.saveRequested = true
	end
end

function stateManager:clearSaveRequest()
	if self._data.saveRequested then
		logger.log("\ar[PriceCheck State]\ax saveRequested cleared (false)")
		self._data.saveRequested = false
	end
end

function stateManager:requestConfigSave()
	if not self._data.configSaveRequested then
		logger.log("\ar[PriceCheck State]\ax configSaveRequested set to true")
		self._data.configSaveRequested = true
	end
end

function stateManager:clearConfigSaveRequest()
	if self._data.configSaveRequested then
		logger.log("\ar[PriceCheck State]\ax configSaveRequested cleared (false)")
		self._data.configSaveRequested = false
	end
end

function stateManager:setItemToRemove(entry)
	if self._data.itemToRemove ~= entry then
		self._data.itemToRemove = entry
	end
end

function stateManager:setTellToRemove(tell)
	if self._data.tellToRemove ~= tell then
		self._data.tellToRemove = tell
	end
end

function stateManager:clearBulkHistory()
	logger.log("\ar[PriceCheck State]\ax bulkPriceHistory cleared")
	self._data.bulkPriceHistory = {}
	self._data.bulkLastUpdated = nil
	self._data.bulkKronoRate = nil
end

function stateManager:setBulkQueue(ids)
	logger.log("\ar[PriceCheck State]\ax bulkQueue set to %d IDs", #ids)
	self._data.bulkQueue = ids
end

function stateManager:setBulkPriceHistory(history)
	self._data.bulkPriceHistory = history
end

function stateManager:setBulkResults(kronoRate, lastUpdated)
	logger.log("\ar[PriceCheck State]\ax bulk results received - Krono Rate: %s, Last Updated: %s", tostring(kronoRate), tostring(lastUpdated))
	self._data.bulkKronoRate = kronoRate or self._data.bulkKronoRate
	self._data.bulkLastUpdated = lastUpdated or self._data.bulkLastUpdated
end

function stateManager:enqueueSearch(entry)
	logger.log("\ar[PriceCheck State]\ax search queued for %q", entry.item)
	table.insert(self._data.searchQueue, entry)
end

function stateManager:enqueueBroadcast(lines)
	logger.log("\ar[PriceCheck State]\ax enqueuing %d lines to broadcastQueue", #lines)
	for _, line in ipairs(lines) do
		table.insert(self._data.broadcastQueue, line)
	end
end

function stateManager:clearBroadcastQueue()
	if #self._data.broadcastQueue > 0 then
		logger.log("\ar[PriceCheck State]\ax broadcastQueue cleared")
		self._data.broadcastQueue = {}
	end
end

function stateManager:clearSearchQueue()
	if #self._data.searchQueue > 0 then
		logger.log("\ar[PriceCheck State]\ax searchQueue cleared")
		self._data.searchQueue = {}
	end
end

function stateManager:clearHistory()
	logger.log("\ar[PriceCheck State]\ax priceHistory cleared")
	self._data.priceHistory = {}
	self._data.searchQueue = {}
	self._data.activeDetailEntry = nil
	self:requestSave()
end

-- Advanced Mutators for collection-based operations

function stateManager:removeHistoryEntryById(id)
	for idx = 1, #self._data.priceHistory do
		if self._data.priceHistory[idx].id == id then
			local entry = table.remove(self._data.priceHistory, idx)
			logger.log("\ar[PriceCheck State]\ax removed history entry %q by ID", entry.item)
			self:requestSave()
			break
		end
	end
end

function stateManager:failHistorySearchIfSearching(id)
	for idx = 1, #self._data.priceHistory do
		if self._data.priceHistory[idx].id == id then
			if self._data.priceHistory[idx].status == "Searching..." then
				self._data.priceHistory[idx].status = "Failed"
				logger.log("\ar[PriceCheck State]\ax failed searching status for %q", self._data.priceHistory[idx].item)
				self:requestSave()
			end
			break
		end
	end
end

function stateManager:popSearchQueue()
	if #self._data.searchQueue > 0 then
		local entry = table.remove(self._data.searchQueue, 1)
		logger.log("\ar[PriceCheck State]\ax popped %q from searchQueue", entry.item)
		return entry
	end
	return nil
end

function stateManager:updateSearchFinished(entry, success, data, statusText)
	entry.status = statusText
	if success and data then
		entry.data = data
		local avgSell = data.sellAverage or data.buyAverage or 0
		local listedPrice = 0
		if avgSell <= 100 then
			listedPrice = math.ceil(avgSell / 10) * 10
		elseif avgSell <= 1000 then
			listedPrice = math.ceil(avgSell / 50) * 50
		else
			listedPrice = math.ceil(avgSell / 100) * 100
		end
		entry.listedPrice = listedPrice
		logger.log("\ar[PriceCheck State]\ax search finished for %q (Success: %s, Listed Price: %d)", entry.item, tostring(success), listedPrice)
	else
		logger.log("\ar[PriceCheck State]\ax search finished for %q (Failed: %s)", entry.item, tostring(statusText))
	end
	self:requestSave()
end

function stateManager:updateBulkSearchResults(ids, result, success, errMsg, dto)
	if success and result then
		self:setBulkResults(result.kronoRate, result.lastUpdated)
		if result.items then
			for _, resItem in ipairs(result.items) do
				local found = false
				for _, existing in ipairs(self._data.bulkPriceHistory) do
					if existing.itemId == resItem.itemId then
						existing.medianPlatPrice = resItem.medianPlatPrice
						existing.hasData = resItem.hasData
						existing.sampleSize = resItem.sampleSize
						existing.status = "Success"
						found = true
						break
					end
				end
				if not found then
					table.insert(self._data.bulkPriceHistory, dto.newBulkEntry(
						resItem.itemId,
						resItem.item or "Unknown Item",
						"Success",
						resItem.medianPlatPrice,
						resItem.hasData,
						resItem.sampleSize
					))
				end
			end
		end
		-- Update status for any items that were in this batch but had no data returned
		for _, itemId in ipairs(ids) do
			for _, existing in ipairs(self._data.bulkPriceHistory) do
				if existing.itemId == itemId and existing.status == "Searching..." then
					existing.status = "Success"
					existing.hasData = false
				end
			end
		end
	else
		-- Set error status for all items in the batch if request failed
		for _, itemId in ipairs(ids) do
			for _, existing in ipairs(self._data.bulkPriceHistory) do
				if existing.itemId == itemId and existing.status == "Searching..." then
					existing.status = errMsg or "Error"
				end
			end
		end
	end
	self:setBulkSearching(false)
end

function stateManager:startBulkSearch(items)
	logger.log("\ar[PriceCheck State]\ax starting bulk search for %d items", #items)
	self._data.bulkPriceHistory = {}
	local ids = {}
	for _, item in ipairs(items) do
		table.insert(ids, item.id)
		table.insert(self._data.bulkPriceHistory, {
			itemId = item.id,
			item = item.name,
			medianPlatPrice = nil,
			hasData = false,
			status = "Searching...",
		})
	end
	self._data.bulkQueue = ids
	self._data.isBulkSearching = (#ids > 0)
end

function stateManager:sortBulkHistory(compareFunc)
	table.sort(self._data.bulkPriceHistory, compareFunc)
	logger.log("\ar[PriceCheck State]\ax bulkPriceHistory sorted")
end

function stateManager:sortPriceHistory(compareFunc)
	table.sort(self._data.priceHistory, compareFunc)
	logger.log("\ar[PriceCheck State]\ax priceHistory sorted")
	self:requestSave()
end

function stateManager:recheckQty(getItemCounts)
	local removedAny = false
	local i = 1
	while i <= #self._data.priceHistory do
		local entry = self._data.priceHistory[i]
		local count, bankCount = getItemCounts(entry.item)
		if count + bankCount == 0 then
			if self._data.activeDetailEntry == entry then
				self._data.activeDetailEntry = nil
			end
			for sqIdx, sqEntry in ipairs(self._data.searchQueue) do
				if sqEntry == entry then
					table.remove(self._data.searchQueue, sqIdx)
					break
				end
			end
			table.remove(self._data.priceHistory, i)
			removedAny = true
			logger.log("\ar[PriceCheck State]\ax removed entry %q due to 0 quantity", entry.item)
		else
			i = i + 1
		end
	end
	if removedAny then
		self:requestSave()
	end
end

function stateManager:updateListedPrice(entry, val)
	if entry.listedPrice ~= val then
		logger.log("\ar[PriceCheck State]\ax listedPrice for %q changed from %s to %s", tostring(entry.item), tostring(entry.listedPrice), tostring(val))
		entry.listedPrice = val
		self:requestSave()
	end
end

function stateManager:removePendingItem()
	local itemToRemove = self._data.itemToRemove
	if not itemToRemove then return end

	local foundIdx = nil
	for i, hEntry in ipairs(self._data.priceHistory) do
		if hEntry == itemToRemove then
			foundIdx = i
			break
		end
	end
	if foundIdx then
		local entry = self._data.priceHistory[foundIdx]
		logger.log("\ar[PriceCheck State]\ax removing item %q from history", entry.item)
		if self._data.activeDetailEntry == entry then
			self._data.activeDetailEntry = nil
		end
		for sqIdx, sqEntry in ipairs(self._data.searchQueue) do
			if sqEntry == entry then
				table.remove(self._data.searchQueue, sqIdx)
				break
			end
		end
		table.remove(self._data.priceHistory, foundIdx)
		self:requestSave()
	end
	self._data.itemToRemove = nil
end

function stateManager:updateConfigKey(key, value)
	if self._data.config[key] ~= value then
		logger.log("\ar[PriceCheck State]\ax config.%s changed from %s to %s", tostring(key), tostring(self._data.config[key]), tostring(value))
		self._data.config[key] = value
		self:requestConfigSave()
	end
end

function stateManager:removePendingTell()
	local tellToRemove = self._data.tellToRemove
	if not tellToRemove then return end

	for i, t in ipairs(self._data.receivedTells) do
		if t == tellToRemove then
			table.remove(self._data.receivedTells, i)
			logger.log("\ar[PriceCheck State]\ax removed tell from %s", tostring(t.sender))
			break
		end
	end
	self._data.tellToRemove = nil
end

function stateManager:addReceivedTell(sender, message, dto)
	local entry = dto.newTellEntry(sender, message)
	table.insert(self._data.receivedTells, entry)
	logger.log("\ar[PriceCheck State]\ax tell received from %s: %s", sender, message)
end

function stateManager:popBroadcastQueue()
	if #self._data.broadcastQueue > 0 then
		local line = table.remove(self._data.broadcastQueue, 1)
		logger.log("\ar[PriceCheck State]\ax popped line from broadcastQueue: %q", line)
		return line
	end
	return nil
end

function stateManager:queueSearch(itemName, dto)
	if not itemName or itemName == "" then
		return
	end

	-- Check if the item already exists in history (case-insensitive lookup)
	local existingEntry = nil
	local existingIndex = nil
	for i, entry in ipairs(self._data.priceHistory) do
		if entry.item:lower() == itemName:lower() then
			existingEntry = entry
			existingIndex = i
			break
		end
	end

	if existingEntry then
		-- Move existing entry to the top of the history list for visibility
		if existingIndex > 1 then
			table.remove(self._data.priceHistory, existingIndex)
			table.insert(self._data.priceHistory, 1, existingEntry)
			self:requestSave()
		end

		if existingEntry.status ~= "Searching..." then
			existingEntry.status = "Searching..."
			existingEntry.data = nil
			table.insert(self._data.searchQueue, existingEntry)
			self:requestSave()
			logger.log("\ar[PriceCheck State]\ax search queued for existing entry %q", itemName)
		end
	else
		local entry = dto.newHistoryEntry(itemName, "Searching...")
		table.insert(self._data.priceHistory, 1, entry)
		table.insert(self._data.searchQueue, entry)
		self:requestSave()
		logger.log("\ar[PriceCheck State]\ax search queued for new entry %q", itemName)
	end
end

function stateManager:addHistoryEntryWithDefaultPrice(itemName, defaultPrice, dto)
	if not itemName or itemName == "" then
		return
	end

	-- Check if the item already exists in history (case-insensitive lookup)
	local existingEntry = nil
	local existingIndex = nil
	for i, entry in ipairs(self._data.priceHistory) do
		if entry.item:lower() == itemName:lower() then
			existingEntry = entry
			existingIndex = i
			break
		end
	end

	if existingEntry then
		-- Move existing entry to the top of the history list for visibility
		if existingIndex > 1 then
			table.remove(self._data.priceHistory, existingIndex)
			table.insert(self._data.priceHistory, 1, existingEntry)
			self:requestSave()
		end

		if existingEntry.status ~= "Success" then
			existingEntry.status = "Success"
			existingEntry.listedPrice = defaultPrice
			self:requestSave()
			logger.log("\ar[PriceCheck State]\ax updated existing entry %q to success with default price %d", itemName, defaultPrice)
		end
	else
		-- Create a new history entry with status "Success" and the default price
		local entry = dto.newHistoryEntry(itemName, "Success", nil, nil, defaultPrice)
		table.insert(self._data.priceHistory, 1, entry)
		self:requestSave()
		logger.log("\ar[PriceCheck State]\ax added new entry %q with default price %d", itemName, defaultPrice)
	end
end

function stateManager:setCursorQueryResult(result)
	local oldName = self._data.cursorQueryResult and self._data.cursorQueryResult.item or "nil"
	local newName = result and result.item or "nil"
	logger.log("\ar[PriceCheck State]\ax cursorQueryResult changed from %s to %s (Status: %s)", oldName, newName, tostring(result and result.status))
	self._data.cursorQueryResult = result
end

function stateManager:setShowCursorQueryWindow(show)
	if self._data.showCursorQueryWindow ~= show then
		logger.log("\ar[PriceCheck State]\ax showCursorQueryWindow changed from %s to %s", tostring(self._data.showCursorQueryWindow), tostring(show))
		self._data.showCursorQueryWindow = show
	end
end

function stateManager:requestCursorQuery(itemName)
	if not itemName or itemName == "" then return end
	self._data.cursorQueryResult = { item = itemName, status = "Searching...", data = nil }
	self._data.showCursorQueryWindow = true
	self._data.cursorQueryPending = true
	logger.log("\ar[PriceCheck State]\ax cursor query requested for %q", itemName)
end

function stateManager:clearCursorQueryPending()
	self._data.cursorQueryPending = false
end

return stateManager
