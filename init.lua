local mq = require("mq")

local PackageMan = require("mq/PackageMan")
local json = PackageMan.Require("lua-cjson", "cjson")
local curl_ok, curl = pcall(PackageMan.Require, "lua-curl", "lcurl")
if not curl_ok then
	curl = nil
end

math.randomseed(os.time())

local ui = require("pricecheck.modules.ui")
local http = require("pricecheck.modules.http")
local stateManager = require("pricecheck.modules.state")

local storage = require("pricecheck.modules.storage")
local char = require("pricecheck.modules.char")
local dto = require("pricecheck.modules.dto")
local chat = require("pricecheck.modules.chat")
local util = require("pricecheck.modules.util")

-- Initialize modules with dependencies (SRP / DI)
ui.setup(char, dto, chat, util)
chat.setup(dto)
http.setup(json, curl)

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
state = stateManager.new(loadedHistory, loadedConfig, initialBulkHistory)

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
	http.tick()

	-- Handle toggled interval broadcasting
	if state.isBroadcastingToggled then
		local now = os.time()
		if not state.nextToggleBroadcastTime then
			state:setNextToggleBroadcastTime(now + (state.config.broadcastInterval or 120))
		end
		if now >= state.nextToggleBroadcastTime then
			local realAuctionLines = ui.getAuctionLines(state, true)
			state:enqueueBroadcast(realAuctionLines)
			state:setNextToggleBroadcastTime(now + (state.config.broadcastInterval or 120))
		end
	else
		state:setNextToggleBroadcastTime(nil)
	end

	if needHistoryFilter then
		if filterIndex <= #itemsToFilter then
			local filterEntry = itemsToFilter[filterIndex]
			local count, bankCount = char.getItemCounts(filterEntry.item)
			if count + bankCount == 0 then
				state:removeHistoryEntryById(filterEntry.id)
			else
				state:failHistorySearchIfSearching(filterEntry.id)
			end
			filterIndex = filterIndex + 1
		else
			needHistoryFilter = false
			saveHistory()
		end
	end
	if #state.searchQueue > 0 and not state.isSearching then
		local entry = state:popSearchQueue()
		state:setSearching(true)
		http.performSearch(entry.item, function(success, data, statusText)
			state:setSearching(false)
			state:updateSearchFinished(entry, success, data, statusText)
		end)
		mq.delay(100)
	elseif #state.bulkQueue > 0 then
		local ids = state.bulkQueue
		state:setBulkQueue({})
		state:setBulkSearching(true)
		http.performBulkSearch(ids, function(result, success, errMsg)
			state:updateBulkSearchResults(ids, result, success, errMsg, dto)
		end)
		mq.delay(100)
	elseif chat.processBroadcastQueue(state) then
		-- Handled by chat module
	else
		mq.delay(100)
	end

	-- Check for save requests
	if state.saveRequested then
		saveHistory()
		state:clearSaveRequest()
	end
	if state.configSaveRequested then
		saveConfig()
		state:clearConfigSaveRequest()
	end
end

-- Save on exit
saveHistory()
saveConfig()
