local mq = require("mq")

local REQUIRED_PLUGINS = {
	{
		name = "MQ2LinkDB",
	},
}

local function ensurePlugins()
	for _, p in ipairs(REQUIRED_PLUGINS) do
		local loaded = mq.TLO.Plugin(p.name).IsLoaded()

		if not loaded then
			printf("\ar[PriceCheck] Required plugin %s is not loaded. Attempting to load...\ax", p.name)
			mq.cmdf("/plugin %s", p.name)
			mq.delay(500)

			loaded = mq.TLO.Plugin(p.name).IsLoaded()
		end

		if not loaded then
			printf("\ar[PriceCheck] Critical Error: Required plugin %s could not be loaded. Exiting script.\ax", p.name)
			mq.exit()
		end
	end
end

ensurePlugins()

local PackageMan = require("mq/PackageMan")
local json = PackageMan.Require("lua-cjson", "cjson")
local curl_ok, curl = pcall(PackageMan.Require, "lua-curl", "lcurl")
if not curl_ok then
	curl = nil
end

math.randomseed(os.time())

local ui = require("modules.ui")
local http = require("modules.http")
local stateManager = require("modules.state")
local logger = require("modules.log")
local storage = require("modules.storage")
local char = require("modules.char")
local dto = require("modules.dto")
local chat = require("modules.chat")
local util = require("modules.util")

ui.setup(char, dto, chat, util)
chat.setup(dto)
http.setup(json, curl)

local state

local defaultConfig = {
	lowSampleSize = 5,
	debounceMin = 400,
	debounceMax = 600,
	replyMessage = "Sure, near Parcel",
	broadcastInterval = 120,
	debug = true,
	defaultPlatPrice = 1000,
	broadcastCommand = "/auction",
	themeName = "Default",
}

local function saveConfig()
	if not state or not state.config then
		return
	end
	local success, err = storage.saveConfig(state.config)
	if not success then
		logger.log("\ar[PriceCheck] Error saving configuration: %s\ax", err or "unknown error")
	end
end

local function saveHistory()
	if not state or not state.priceHistory then
		return
	end
	local success, err = storage.saveHistory(state.priceHistory)
	if not success then
		logger.log("\ar[PriceCheck] Error saving price history: %s\ax", err or "unknown error")
	end
end

local loadedHistory = storage.loadHistory()
local loadedConfig = storage.loadConfig(defaultConfig)

local itemsToFilter = {}
for i, entry in ipairs(loadedHistory) do
	if type(entry) == "table" and type(entry.item) == "string" then
		if not entry.id or entry.id == "" then
			entry.id = string.format("%d_%d", os.time(), math.random(100000, 999999) + i)
		end
		table.insert(itemsToFilter, { id = entry.id, item = entry.item })
	end
end

local initialBulkHistory = {}
local initItems = char.getUniqueInventoryItemTypes()
for _, item in ipairs(initItems) do
	table.insert(initialBulkHistory, dto.newBulkEntry(item.id, item.name))
end

state = stateManager.new(loadedHistory, loadedConfig, initialBulkHistory)
logger.setup(state)

chat.registerTellEvent(state)

mq.bind("/pricecheck", function(...)
	local args = { ... }
	local itemName
	if #args > 0 then
		itemName = table.concat(args, " ")
	else
		itemName = char.getCursorItemName()
	end

	if itemName and itemName ~= "" then
		state:requestCursorQuery(itemName)
	else
		printf("\ar[PriceCheck] No item found on your cursor to check.\ax")
	end
end)

mq.imgui.init("PriceCheckWindow", function()
	ui.render(state)
end)

local lastSingleQueryTime = 0
local needHistoryFilter = true
local filterIndex = 1

while state.openGUI do
	mq.doevents()
	http.tick()

	if state.cursorQueryPending then
		local nowMs = mq.gettime()
		if nowMs - lastSingleQueryTime >= 1000 then
			local itemName = state.cursorQueryResult.item
			state.cursorQueryPending = false
			lastSingleQueryTime = nowMs
			http.performSearch(itemName, function(success, data, statusText)
				if state.cursorQueryResult and state.cursorQueryResult.item == itemName then
					local result = { item = itemName, status = statusText, data = data }
					state.cursorQueryResult = result
					state:setCachedQuery(itemName, result)
				end
			end)
		end
	end

	-- Broadcast timeline is evaluated and played asynchronously via chat.processBroadcastQueue(state) in the block below.

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

	local nowMs = mq.gettime()
	if #state.searchQueue > 0 and not state.isSearching and (nowMs - lastSingleQueryTime >= 1000) then
		local entry = state:popSearchQueue()
		state.isSearching = true
		lastSingleQueryTime = nowMs
		http.performSearch(entry.item, function(success, data, statusText)
			state.isSearching = false
			state:updateSearchFinished(entry, success, data, statusText)
		end)
		mq.delay(100)
	elseif #state.bulkQueue > 0 then
		local ids = state.bulkQueue
		state.bulkQueue = {}
		state.isBulkSearching = true
		http.performBulkSearch(ids, function(result, success, errMsg)
			state:updateBulkSearchResults(ids, result, success, errMsg, dto)
		end)
		mq.delay(100)
	elseif chat.processBroadcastQueue(state) then
		-- Handled by chat module
	else
		mq.delay(100)
	end

	if state.saveRequested then
		saveHistory()
		state.saveRequested = false
	end
	if state.configSaveRequested then
		saveConfig()
		state.configSaveRequested = false
	end
end

saveHistory()
saveConfig()
