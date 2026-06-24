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

-- Initialize UI module with its dependencies (SRP / DI)
ui.setup(char, dto)

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
	storage.saveConfig(state.config)
end

local function saveHistory()
	if not state or not state.priceHistory then
		return
	end
	storage.saveHistory(state.priceHistory)
end

local function filterZeroQtyHistory(history)
	if type(history) ~= "table" then
		return {}
	end
	local i = 1
	while i <= #history do
		local entry = history[i]
		if type(entry) == "table" and type(entry.item) == "string" then
			if not entry.id or entry.id == "" then
				entry.id = tostring(os.clock() + math.random() + i):gsub("%.", "")
			end
			local count, bankCount = char.getItemCounts(entry.item)
			if count + bankCount == 0 then
				table.remove(history, i)
			else
				if entry.status == "Searching..." then
					entry.status = "Failed"
				end
				i = i + 1
			end
		else
			table.remove(history, i)
		end
		-- Yield every frame to completely prevent startup freezing (KISS delay trap fix)
		mq.delay(1)
	end
	return history
end

local loadedHistory = filterZeroQtyHistory(storage.loadHistory())
local loadedConfig = storage.loadConfig(defaultConfig)

-- Populate bulk history on startup with names only
local initialBulkHistory = {}
local initItems = char.getInventoryItems()
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

-- Write back the filtered history and config
saveHistory()
saveConfig()

-- Register event listener for incoming tells
mq.event('TellEvent', '#1# tells you, \'#2#', function(line, sender, message)
	if sender and message then
		-- Filter out self-tells
		local myName = mq.TLO.Me.CleanName()
		if myName and sender:lower() == myName:lower() then
			return
		end

		-- Clean up the trailing single quote
		if message:sub(-1) == "'" then
			message = message:sub(1, -2)
		end

		table.insert(state.receivedTells, dto.newTellEntry(sender, message))
	end
end)

-- Helper function to clean and validate plain-text item names


-- Register the ImGui render loop callback with the shared state
mq.imgui.init("PriceCheckWindow", function()
	ui.render(state)
end)

-- Main script loop (running in the safe script coroutine thread)
while state.openGUI do
	mq.doevents()
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
	elseif #state.broadcastQueue > 0 then
		local commandLine = table.remove(state.broadcastQueue, 1)
		mq.cmd(commandLine)
		local min = (state.config and state.config.debounceMin) or 400
		local max = (state.config and state.config.debounceMax) or 600
		if min > max then
			min, max = max, min
		end
		local delayTime = math.random(min, max)
		mq.delay(delayTime)
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
