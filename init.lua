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

local state

-- Default configuration settings
local defaultConfig = {
	lowSampleSize = 5,
	debounceMin = 400,
	debounceMax = 600,
	replyMessage = "Sure, near Parcel",
}

-- Helper functions for persisting configuration
local function loadConfig()
	local savePath = string.format("%s/pricecheck_config.json", mq.configDir or ".")
	local file = io.open(savePath, "r")
	if not file then
		return defaultConfig
	end
	local content = file:read("*all")
	file:close()
	if not content or content == "" then
		return defaultConfig
	end
	local status, data = pcall(json.decode, content)
	if not status or type(data) ~= "table" then
		return defaultConfig
	end
	-- Merge defaults for missing keys
	for k, v in pairs(defaultConfig) do
		if data[k] == nil then
			data[k] = v
		end
	end
	return data
end

local function saveConfig()
	if not state or not state.config then
		return
	end
	local savePath = string.format("%s/pricecheck_config.json", mq.configDir or ".")
	local file = io.open(savePath, "w")
	if file then
		local status, content = pcall(json.encode, state.config)
		if status and content then
			file:write(content)
		end
		file:close()
	end
end

-- Helper functions for persisting price history
local function loadHistory()
	local savePath = string.format("%s/pricecheck_history.json", mq.configDir or ".")
	local file = io.open(savePath, "r")
	if not file then
		return {}
	end
	local content = file:read("*all")
	file:close()
	if not content or content == "" then
		return {}
	end
	local status, data = pcall(json.decode, content)
	if not status then
		return {}
	end
	return data or {}
end

local function saveHistory()
	if not state or not state.priceHistory then
		return
	end
	local savePath = string.format("%s/pricecheck_history.json", mq.configDir or ".")
	local file = io.open(savePath, "w")
	if file then
		local status, content = pcall(json.encode, state.priceHistory)
		if status and content then
			file:write(content)
		end
		file:close()
	end
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
			local count, bankCount = ui.getItemCounts(entry.item)
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

local loadedHistory = filterZeroQtyHistory(loadHistory())
local loadedConfig = loadConfig()

-- Populate bulk history on startup with names only
local initialBulkHistory = {}
local initItems = ui.getInventoryItems()
for _, item in ipairs(initItems) do
	table.insert(initialBulkHistory, {
		itemId = item.id,
		item = item.name,
		medianPlatPrice = nil,
		hasData = false,
		status = "Not Checked",
	})
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

		table.insert(state.receivedTells, {
			sender = sender,
			message = message,
			time = os.time(),
		})
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
							table.insert(state.bulkPriceHistory, {
								itemId = resItem.itemId,
								item = resItem.item or "Unknown Item",
								medianPlatPrice = resItem.medianPlatPrice,
								hasData = resItem.hasData,
								sampleSize = resItem.sampleSize,
								status = "Success",
							})
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
