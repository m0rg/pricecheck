local mq = require("mq")

math.randomseed(os.time())

-- Use dynamic module paths relative to script invocation to support standard loading
local myPath = ...
if myPath then
	-- Strip trailing .init if present
	myPath = myPath:gsub("%.init$", "")
	myPath = myPath .. "."
else
	myPath = "pricecheck."
end

local ui = require(myPath .. "ui")
local http = require(myPath .. "http")
local PackageMan = require("mq/PackageMan")
local json = PackageMan.Require("lua-cjson", "cjson")
local storage = require(myPath .. "storage")
local char = require(myPath .. "char")
local dto = require(myPath .. "dto")
local chat = require(myPath .. "chat")
local util = require(myPath .. "util")

-- Initialize UI and Chat modules with dependencies (SRP / DI)
ui.setup(char, dto, chat, util)
chat.setup(dto)

local state

-- Default configuration settings
local defaultConfig = {
	lowSampleSize = 5,
	debounceMin = 400,
	debounceMax = 600,
	replyMessage = "Sure, near Parcel",
}

local function saveConfig()
	if not state or not state.config then
		return
	end
	local success, err = storage.saveConfig(state.config)
	if not success then
		mq.print(string.format("\ar[PriceCheck] Error saving configuration: %s\ax", err or "unknown error"))
	end
end

local function saveHistory()
	if not state or not state.priceHistory then
		return
	end
	local success, err = storage.saveHistory(state.priceHistory)
	if not success then
		mq.print(string.format("\ar[PriceCheck] Error saving price history: %s\ax", err or "unknown error"))
	end
end

local loadedHistory = storage.loadHistory()
local loadedConfig = storage.loadConfig(defaultConfig)

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

	-- Non-blocking startup history filtering step (processes one entry per loop iteration)
	if needHistoryFilter then
		if filterIndex <= #state.priceHistory then
			local entry = state.priceHistory[filterIndex]
			if type(entry) == "table" and type(entry.item) == "string" then
				if not entry.id or entry.id == "" then
					entry.id = string.format("%d_%d", os.time(), math.random(100000, 999999))
				end
				local count, bankCount = char.getItemCounts(entry.item)
				if count + bankCount == 0 then
					table.remove(state.priceHistory, filterIndex)
				else
					if entry.status == "Searching..." then
						entry.status = "Failed"
					end
					filterIndex = filterIndex + 1
				end
			else
				table.remove(state.priceHistory, filterIndex)
			end
		else
			needHistoryFilter = false
			saveHistory()
		end
	end
	if #state.searchQueue > 0 and not state.isSearching then
		local entry = table.remove(state.searchQueue, 1)
		state.isSearching = true
		local callbackCalled = false
		local ok, err = pcall(http.performSearch, entry.item, function(success, data, statusText)
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

		if not ok or not callbackCalled then
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
		local ok, err = pcall(http.performBulkSearch, ids, function(result, success, errMsg)
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

		if not ok or not callbackCalled then
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
