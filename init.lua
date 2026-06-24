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
			local countObj = mq.TLO.FindItemCount(string.format('=%s', entry.item))
			local count = (countObj and countObj()) or 0
			local bankObj = mq.TLO.FindItemBankCount(string.format('=%s', entry.item))
			local bankCount = (bankObj and bankObj()) or 0
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
	auctionMonitor = {},
	recordAuctions = false,
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

-- Helper function to extract both item links and plain-text item names from an auction message
local function parseMessageItems(message)
	local items = {}
	if not message or message == "" then
		return items
	end

	-- 1. Extract and process actual item links
	local remaining = message
	for content in string.gmatch(message, "\x12([^\x12]+)\x12") do
		local hex, name = nil, nil
		-- Check 54-char hex prefix (Live/TLP)
		if #content > 54 then
			local h = content:sub(1, 54)
			if h:match("^%x+$") then
				hex = h
				name = content:sub(55)
			end
		end
		-- Check 9-char hex prefix (classic/emulator)
		if not hex and #content > 9 then
			local h = content:sub(1, 9)
			if h:match("^%x+$") then
				hex = h
				name = content:sub(10)
			end
		end
		-- Check 8-char hex prefix (used in test cases)
		if not hex and #content > 8 then
			local h = content:sub(1, 8)
			if h:match("^%x+$") then
				hex = h
				name = content:sub(9)
			end
		end
		-- Fallback
		if not hex then
			local h, n = content:match("^(%x+)(.*)$")
			if h and h ~= "" then
				hex = h
				name = n
			end
		end

		if hex and name and name ~= "" then
			table.insert(items, {
				name = name,
				link = "\x12" .. hex .. name .. "\x12",
				hex = hex,
				isLink = true
			})
			-- Remove the link from the remaining text to avoid duplicate parsing
			remaining = remaining:gsub("\x12" .. hex .. name .. "\x12", "")
		end
	end

	-- 2. Parse remaining plain text for item names
	-- Split by comma, semicolon, or newlines
	for part in string.gmatch(remaining, "([^,;\n\r]+)") do
		part = part:match("^%s*(.-)%s*$")
		
		-- Further split by " - " (hyphen with spaces) if present
		local subParts = {}
		if string.find(part, " - ", 1, true) then
			for sub in string.gmatch(part, "[^%-]+") do
				table.insert(subParts, sub)
			end
		else
			table.insert(subParts, part)
		end

		for _, sub in ipairs(subParts) do
			sub = sub:match("^%s*(.-)%s*$")
			if sub ~= "" then
				-- Strip leading command/verb words: wts, wtb, selling, sell, wtt, buy, buying
				local lowerSub = sub:lower()
				local clean = sub
				local prefixes = { "wts%s+", "wtb%s+", "selling%s+", "sell%s+", "wtt%s+", "buy%s+", "buying%s+" }
				for _, pref in ipairs(prefixes) do
					local startIdx, endIdx = lowerSub:find("^" .. pref)
					if startIdx then
						clean = sub:sub(endIdx + 1)
						break
					end
				end

				clean = clean:match("^%s*(.-)%s*$")

				-- Strip trailing prices and common suffixes (e.g. 75, 9k, 1500p, 10kr, pst, obo)
				clean = clean:gsub("%s+%d+%s*[kKpP]*%s*[lLrR]*%s*$", "")
				clean = clean:gsub("%s+%d+%s*[kK]*[rR]*%s*$", "")
				clean = clean:gsub("%s+%d+pp%s*$", "")
				clean = clean:gsub("%s+%d+p%s*$", "")
				clean = clean:gsub("%s+%d+kr%s*$", "")
				clean = clean:gsub("%s+pst%s*$", "")
				clean = clean:gsub("%s+obo%s*$", "")

				-- Strip trailing exclamation marks/spaces
				clean = clean:gsub("[%s!]+$", "")
				clean = clean:match("^%s*(.-)%s*$")

				-- Filter out noise words or very short strings
				local lowerClean = clean:lower()
				if #clean >= 3 and #clean <= 50 and 
				   lowerClean ~= "send tell" and 
				   lowerClean ~= "pst" and 
				   lowerClean ~= "obo" and
				   not lowerClean:match("^%s*$") then
					table.insert(items, {
						name = clean,
						link = nil,
						hex = nil,
						isLink = false
					})
				end
			end
		end
	end

	return items
end

-- Register event listener for incoming auctions
local function processAuction(sender, message)
	-- Print a debug message to the MQ console so the user can verify if the event triggers
	print(string.format("[PriceCheck Debug] Auction event triggered: sender=%s, message=%s, recordAuctions=%s", tostring(sender), tostring(message), tostring(state.recordAuctions)))

	if not state.recordAuctions then
		return
	end

	if sender and message then
		-- Clean up leading/trailing single quotes if present
		if message:sub(1, 1) == "'" then
			message = message:sub(2)
		end
		if message:sub(-1) == "'" then
			message = message:sub(1, -2)
		end

		-- Parse both links and plain-text item names from the message
		local parsedItems = parseMessageItems(message)
		for _, parsed in ipairs(parsedItems) do
			local itemId = nil
			if parsed.hex and #parsed.hex >= 8 then
				local idHex = parsed.hex:sub(3, 8)
				itemId = tonumber(idHex, 16)
			end

			table.insert(state.auctionMonitor, 1, {
				time = os.time(),
				sender = sender,
				item = parsed.name,
				link = parsed.link,
				itemId = itemId,
				status = "Not Checked",
				raw = message
			})
		end

		-- Limit to last 100 entries to prevent infinite memory growth
		while #state.auctionMonitor > 100 do
			table.remove(state.auctionMonitor)
		end
	end
end

mq.event('AuctionEvent1', '#1# auctions, #2#', function(line, sender, message)
	processAuction(sender, message)
end)

mq.event('AuctionEvent2', 'You auction, #1#', function(line, message)
	local myName = mq.TLO.Me.CleanName() or "You"
	processAuction(myName, message)
end)

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
		local ok, err = pcall(http.performSearch, entry, function(completedEntry, success)
			callbackCalled = true
			state.isSearching = false
			if success and completedEntry.data then
				local avgSell = completedEntry.data.sellAverage or completedEntry.data.buyAverage or 0
				local listedPrice = 0
				if avgSell <= 100 then
					listedPrice = math.ceil(avgSell / 10) * 10
				elseif avgSell <= 1000 then
					listedPrice = math.ceil(avgSell / 50) * 50
				else
					listedPrice = math.ceil(avgSell / 100) * 100
				end
				completedEntry.listedPrice = listedPrice
			end

			-- Update matching entries in the auction monitor
			for _, aucEntry in ipairs(state.auctionMonitor) do
				if aucEntry.item:lower() == completedEntry.item:lower() then
					if success and completedEntry.data then
						aucEntry.medianPrice = completedEntry.listedPrice
						aucEntry.hasData = true
						aucEntry.status = "Success"
					else
						aucEntry.status = "Failed"
					end
				end
			end

			saveHistory()
		end)

		if not ok or not callbackCalled then
			state.isSearching = false
			entry.status = "Error"
			for _, aucEntry in ipairs(state.auctionMonitor) do
				if aucEntry.item:lower() == entry.item:lower() then
					aucEntry.status = "Error"
				end
			end
			saveHistory()
		end
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

						-- Update auctionMonitor entries
						for _, entry in ipairs(state.auctionMonitor) do
							if entry.itemId == resItem.itemId then
								entry.medianPrice = resItem.medianPlatPrice
								entry.hasData = resItem.hasData
								entry.status = "Success"
							end
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
					for _, entry in ipairs(state.auctionMonitor) do
						if entry.itemId == itemId and entry.status == "Searching..." then
							entry.status = "Success"
							entry.hasData = false
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
					for _, entry in ipairs(state.auctionMonitor) do
						if entry.itemId == itemId and entry.status == "Searching..." then
							entry.status = errMsg or "Error"
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
				for _, entry in ipairs(state.auctionMonitor) do
					if entry.itemId == itemId and entry.status == "Searching..." then
						entry.status = "Error"
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
