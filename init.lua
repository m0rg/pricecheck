local mq = require("mq")

local PackageMan = require("mq/PackageMan")
PackageMan.debug = true
local json = PackageMan.Require("lua-cjson", "cjson")
local luasocket = PackageMan.Require("luasocket", "socket")
local ssl_ok, https = pcall(PackageMan.Require, "luasec", "ssl.https")
if not ssl_ok then
	https = nil
end

math.randomseed(os.time())

local ui = require("pricecheck.modules.ui")
local http = require("pricecheck.modules.http")

local storage = require("pricecheck.modules.storage")
local char = require("pricecheck.modules.char")
local dto = require("pricecheck.modules.dto")
local chat = require("pricecheck.modules.chat")
local util = require("pricecheck.modules.util")

-- Initialize modules with dependencies (SRP / DI)
ui.setup(char, dto, chat, util)
chat.setup(dto)
http.setup(json, https)

local state

-- Default configuration settings
local defaultConfig = {
	lowSampleSize = 5,
	debounceMin = 400,
	debounceMax = 600,
	replyMessage = "Sure, near Parcel",
	broadcastInterval = 120,
}

local function saveConfig()
	if not state or not state.config then
		return
	end
	local success, err = storage.saveConfig(state.config)
	if not success then
		printf("\ar[PriceCheck] Error saving configuration: %s\ax", err or "unknown error")
	end
end

local function saveHistory()
	if not state or not state.priceHistory then
		return
	end
	local success, err = storage.saveHistory(state.priceHistory)
	if not success then
		printf("\ar[PriceCheck] Error saving price history: %s\ax", err or "unknown error")
	end
end

local loadedHistory = storage.loadHistory()
local loadedConfig = storage.loadConfig(defaultConfig)

-- Ensure every entry has a valid unique ID on boot
for i, entry in ipairs(loadedHistory) do
	if type(entry) == "table" and type(entry.item) == "string" then
		if not entry.id or entry.id == "" then
			entry.id = string.format("%d_%d", os.time(), math.random(100000, 999999) + i)
		end
	end
end

-- Build static snapshot queue of items to filter in background to avoid UI concurrent mutation race conditions
local itemsToFilter = {}
for _, entry in ipairs(loadedHistory) do
	if type(entry) == "table" and type(entry.item) == "string" then
		table.insert(itemsToFilter, { id = entry.id, item = entry.item })
	end
end

-- Populate bulk history on startup with names only
local initialBulkHistory = {}
local initItems = char.getUniqueInventoryItemTypes()
for _, item in ipairs(initItems) do
	table.insert(initialBulkHistory, dto.newBulkEntry(item.id, item.name))
end

-- Shared state context table (encapsulating all state without using globals)
state = {
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
	isBulkSearching = false,
}

-- Write back the config on boot

-- Register event listener for incoming tells
chat.registerTellEvent(state)

-- Helper function to clean and validate plain-text item names


-- Register the ImGui render loop callback with the shared state
mq.imgui.init("PriceCheckWindow", function()
	ui.render(state)
end)

local needHistoryFilter = true
local filterIndex = 1

-- Main script loop (running in the safe script coroutine thread)
while state.openGUI do
	mq.doevents()

	-- Handle toggled interval broadcasting
	if state.isBroadcastingToggled then
		local now = os.time()
		if not state.nextToggleBroadcastTime then
			state.nextToggleBroadcastTime = now + (state.config.broadcastInterval or 120)
		end
		if now >= state.nextToggleBroadcastTime then
			local realAuctionLines = ui.getAuctionLines(state, true)
			for _, commandLine in ipairs(realAuctionLines) do
				table.insert(state.broadcastQueue, commandLine)
			end
			state.nextToggleBroadcastTime = now + (state.config.broadcastInterval or 120)
		end
	else
		state.nextToggleBroadcastTime = nil
	end

	-- Non-blocking startup history filtering step (processes one entry from static queue per loop iteration)
	if needHistoryFilter then
		if filterIndex <= #itemsToFilter then
			local filterEntry = itemsToFilter[filterIndex]
			local count, bankCount = char.getItemCounts(filterEntry.item)
			if count + bankCount == 0 then
				-- Find and remove by unique ID to be immune to UI mutation index shifting
				for idx = 1, #state.priceHistory do
					if state.priceHistory[idx].id == filterEntry.id then
						table.remove(state.priceHistory, idx)
						break
					end
				end
			else
				-- Safe status validation
				for idx = 1, #state.priceHistory do
					if state.priceHistory[idx].id == filterEntry.id then
						if state.priceHistory[idx].status == "Searching..." then
							state.priceHistory[idx].status = "Failed"
						end
						break
					end
				end
			end
			filterIndex = filterIndex + 1
		else
			needHistoryFilter = false
			saveHistory()
		end
	end
	if #state.searchQueue > 0 and not state.isSearching then
		local entry = table.remove(state.searchQueue, 1)
		state.isSearching = true
		local callbackCalled = false
		http.performSearch(entry.item, function(success, data, statusText)
			callbackCalled = true
			state.isSearching = false
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
			end

			saveHistory()
		end)

		if not callbackCalled then
			state.isSearching = false
			entry.status = "Error"

			saveHistory()
		end
		mq.delay(100)
	elseif #state.bulkQueue > 0 then
		local ids = state.bulkQueue
		state.bulkQueue = {}
		state.isBulkSearching = true
		local callbackCalled = false
		http.performBulkSearch(ids, function(result, success, errMsg)
			callbackCalled = true
			if success and result then
				state.bulkLastUpdated = result.lastUpdated
				state.bulkKronoRate = result.kronoRate
				if result.items then
					for _, resItem in ipairs(result.items) do
						local found = false
						for _, existing in ipairs(state.bulkPriceHistory) do
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
							table.insert(state.bulkPriceHistory, dto.newBulkEntry(
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
					for _, existing in ipairs(state.bulkPriceHistory) do
						if existing.itemId == itemId and existing.status == "Searching..." then
							existing.status = "Success"
							existing.hasData = false
						end
					end

				end
			else
				-- Set error status for all items in the batch if request failed
				for _, itemId in ipairs(ids) do
					for _, existing in ipairs(state.bulkPriceHistory) do
						if existing.itemId == itemId and existing.status == "Searching..." then
							existing.status = errMsg or "Error"
						end
					end

				end
			end
			state.isBulkSearching = false
		end)

		if not callbackCalled then
			state.isBulkSearching = false
			for _, itemId in ipairs(ids) do
				for _, existing in ipairs(state.bulkPriceHistory) do
					if existing.itemId == itemId and existing.status == "Searching..." then
						existing.status = "Error"
					end
				end

			end
		end
		mq.delay(100)
	elseif chat.processBroadcastQueue(state) then
		-- Handled by chat module
	else
		mq.delay(100)
	end

	-- Check for save requests
	if state.saveRequested then
		saveHistory()
		state.saveRequested = false
	end
	if state.configSaveRequested then
		saveConfig()
		state.configSaveRequested = false
	end
end

-- Save on exit
saveHistory()
saveConfig()
