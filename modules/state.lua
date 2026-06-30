local mq = require("mq")
local logger = require("modules.log")

local stateManager = {}

function stateManager.new(loadedHistory, loadedConfig, initialBulkHistory)
	local rawState = {
		openGUI = true,
		isSearching = false,
		priceHistory = loadedHistory,
		config = loadedConfig,
		receivedTells = {},
		activeDetailEntry = nil,
		searchQueue = {},
		timeline = nil,
		currentStepIndex = 1,
		stepEndTime = 0,
		nextBroadcastTime = 0,
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
		queryCache = {},
	}

	local self = {
		_data = rawState,
	}

	local mt = {
		__index = function(t, key)
			if stateManager[key] then
				return stateManager[key]
			end
			return rawState[key]
		end,
		__newindex = function(t, key, value)
			if rawState[key] ~= value then
				if key == "openGUI" then
					logger.log("\ar[PriceCheck State]\ax openGUI changed from %s to %s", tostring(rawState.openGUI), tostring(value))
				elseif key == "isSearching" then
					logger.log("\ar[PriceCheck State]\ax isSearching changed from %s to %s", tostring(rawState.isSearching), tostring(value))
				elseif key == "isBulkSearching" then
					logger.log("\ar[PriceCheck State]\ax isBulkSearching changed from %s to %s", tostring(rawState.isBulkSearching), tostring(value))
				elseif key == "isBroadcastingToggled" then
					logger.log("\ar[PriceCheck State]\ax isBroadcastingToggled changed from %s to %s", tostring(rawState.isBroadcastingToggled), tostring(value))
				elseif key == "nextToggleBroadcastTime" then
					logger.log("\ar[PriceCheck State]\ax nextToggleBroadcastTime changed from %s to %s", tostring(rawState.nextToggleBroadcastTime), tostring(value))
				elseif key == "activeDetailEntry" then
					local oldName = rawState.activeDetailEntry and rawState.activeDetailEntry.item or "nil"
					local newName = value and value.item or "nil"
					logger.log("\ar[PriceCheck State]\ax activeDetailEntry changed from %s to %s", oldName, newName)
				elseif key == "saveRequested" then
					if value then
						logger.log("\ar[PriceCheck State]\ax saveRequested set to true")
					else
						logger.log("\ar[PriceCheck State]\ax saveRequested cleared (false)")
					end
				elseif key == "configSaveRequested" then
					if value then
						logger.log("\ar[PriceCheck State]\ax configSaveRequested set to true")
					else
						logger.log("\ar[PriceCheck State]\ax configSaveRequested cleared (false)")
					end
				elseif key == "cursorQueryResult" then
					local oldName = rawState.cursorQueryResult and rawState.cursorQueryResult.item or "nil"
					local newName = value and value.item or "nil"
					logger.log("\ar[PriceCheck State]\ax cursorQueryResult changed from %s to %s (Status: %s)", oldName, newName, tostring(value and value.status))
				elseif key == "showCursorQueryWindow" then
					logger.log("\ar[PriceCheck State]\ax showCursorQueryWindow changed from %s to %s", tostring(rawState.showCursorQueryWindow), tostring(value))
				end
			end
			rawState[key] = value
		end,
	}
	return setmetatable(self, mt)
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
	self.saveRequested = true
end

function stateManager:removeHistoryEntryById(id)
	for idx = 1, #self._data.priceHistory do
		if self._data.priceHistory[idx].id == id then
			local entry = table.remove(self._data.priceHistory, idx)
			logger.log("\ar[PriceCheck State]\ax removed history entry %q by ID", entry.item)
			self.saveRequested = true
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
				self.saveRequested = true
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
	self.saveRequested = true
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
		for _, itemId in ipairs(ids) do
			for _, existing in ipairs(self._data.bulkPriceHistory) do
				if existing.itemId == itemId and existing.status == "Searching..." then
					existing.status = "Success"
					existing.hasData = false
				end
			end
		end
	else
		for _, itemId in ipairs(ids) do
			for _, existing in ipairs(self._data.bulkPriceHistory) do
				if existing.itemId == itemId and existing.status == "Searching..." then
					existing.status = errMsg or "Error"
				end
			end
		end
	end
	self.isBulkSearching = false
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
	self.isBulkSearching = (#ids > 0)
end

function stateManager:sortBulkHistory(compareFunc)
	table.sort(self._data.bulkPriceHistory, compareFunc)
	logger.log("\ar[PriceCheck State]\ax bulkPriceHistory sorted")
end

function stateManager:sortPriceHistory(compareFunc)
	table.sort(self._data.priceHistory, compareFunc)
	logger.log("\ar[PriceCheck State]\ax priceHistory sorted")
	self.saveRequested = true
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
		self.saveRequested = true
	end
end

function stateManager:updateListedPrice(entry, val)
	if entry.listedPrice ~= val then
		logger.log("\ar[PriceCheck State]\ax listedPrice for %q changed from %s to %s", tostring(entry.item), tostring(entry.listedPrice), tostring(val))
		entry.listedPrice = val
		self.saveRequested = true
	end
end

function stateManager:removePendingItem()
	local itemToRemove = self._data.itemToRemove
	if not itemToRemove then
		return
	end

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
		self.saveRequested = true
	end
	self._data.itemToRemove = nil
end

function stateManager:updateConfigKey(key, value)
	if self._data.config[key] ~= value then
		logger.log("\ar[PriceCheck State]\ax config.%s changed from %s to %s", tostring(key), tostring(self._data.config[key]), tostring(value))
		self._data.config[key] = value
		self.configSaveRequested = true
	end
end

function stateManager:removePendingTell()
	local tellToRemove = self._data.tellToRemove
	if not tellToRemove then
		return
	end

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

function stateManager:queueSearch(itemName, dto)
	if not itemName or itemName == "" then
		return
	end

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
		if existingIndex > 1 then
			table.remove(self._data.priceHistory, existingIndex)
			table.insert(self._data.priceHistory, 1, existingEntry)
			self.saveRequested = true
		end

		if existingEntry.status ~= "Searching..." then
			existingEntry.status = "Searching..."
			existingEntry.data = nil
			table.insert(self._data.searchQueue, existingEntry)
			self.saveRequested = true
			logger.log("\ar[PriceCheck State]\ax search queued for existing entry %q", itemName)
		end
	else
		local entry = dto.newHistoryEntry(itemName, "Searching...")
		table.insert(self._data.priceHistory, 1, entry)
		table.insert(self._data.searchQueue, entry)
		self.saveRequested = true
		logger.log("\ar[PriceCheck State]\ax search queued for new entry %q", itemName)
	end
end

function stateManager:addHistoryEntryWithDefaultPrice(itemName, defaultPrice, dto)
	if not itemName or itemName == "" then
		return
	end

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
		if existingIndex > 1 then
			table.remove(self._data.priceHistory, existingIndex)
			table.insert(self._data.priceHistory, 1, existingEntry)
			self.saveRequested = true
		end

		if existingEntry.status ~= "Success" then
			existingEntry.status = "Success"
			existingEntry.listedPrice = defaultPrice
			self.saveRequested = true
			logger.log("\ar[PriceCheck State]\ax updated existing entry %q to success with default price %d", itemName, defaultPrice)
		end
	else
		local entry = dto.newHistoryEntry(itemName, "Success", nil, nil, defaultPrice)
		table.insert(self._data.priceHistory, 1, entry)
		self.saveRequested = true
		logger.log("\ar[PriceCheck State]\ax added new entry %q with default price %d", itemName, defaultPrice)
	end
end

function stateManager:requestCursorQuery(itemName)
	if not itemName or itemName == "" then
		return
	end

	local cached = self:getCachedQuery(itemName)
	if cached then
		self._data.cursorQueryResult = cached
		self._data.showCursorQueryWindow = true
		self._data.cursorQueryPending = false
		logger.log("\ar[PriceCheck State]\ax cursor query served from cache for %q", itemName)
		return
	end

	self._data.cursorQueryResult = { item = itemName, status = "Searching...", data = nil }
	self._data.showCursorQueryWindow = true
	self._data.cursorQueryPending = true
	logger.log("\ar[PriceCheck State]\ax cursor query requested for %q", itemName)
end

function stateManager:getCachedQuery(itemName)
	return self._data.queryCache[itemName:lower()]
end

function stateManager:setCachedQuery(itemName, result)
	self._data.queryCache[itemName:lower()] = result
end

function stateManager:addAllBulkItems(dto)
	logger.log("\ar[PriceCheck State]\ax adding all bulk items to trade history")
	local defaultPrice = (self._data.config and self._data.config.defaultPlatPrice) or 1000
	for _, entry in ipairs(self._data.bulkPriceHistory) do
		local alreadyListed = false
		for _, hEntry in ipairs(self._data.priceHistory) do
			if hEntry.item:lower() == entry.item:lower() then
				alreadyListed = true
				break
			end
		end

		if not alreadyListed then
			if entry.status == "Success" and entry.hasData and entry.medianPlatPrice then
				self:queueSearch(entry.item, dto)
			else
				self:addHistoryEntryWithDefaultPrice(entry.item, defaultPrice, dto)
			end
		end
	end
end

return stateManager
