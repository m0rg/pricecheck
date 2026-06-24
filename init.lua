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

-- Shared state context table (encapsulating all state without using globals)
state = {
	openGUI = true,
	isSearching = false,
	broadcastCommand = "/auction",
	priceHistory = loadedHistory,
	activeDetailEntry = nil,
	searchQueue = {},
	broadcastQueue = {},
	bulkPriceHistory = {},
	bulkLastUpdated = nil,
	bulkKronoRate = nil,
	bulkQueue = {},
	isBulkSearching = false,
}

-- Write back the filtered history
saveHistory()

-- Register the ImGui render loop callback with the shared state
mq.imgui.init("PriceCheckWindow", function()
	ui.render(state)
end)

-- Main script loop (running in the safe script coroutine thread)
while state.openGUI do
	if #state.searchQueue > 0 and not state.isSearching then
		local entry = table.remove(state.searchQueue, 1)
		state.isSearching = true
		http.performSearch(entry, function(completedEntry, success)
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
			saveHistory()
		end)
	elseif #state.bulkQueue > 0 then
		local ids = state.bulkQueue
		state.bulkQueue = {}
		state.isBulkSearching = true
		http.performBulkSearch(ids, function(result, success, errMsg)
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
		mq.delay(100)
	elseif #state.broadcastQueue > 0 then
		local commandLine = table.remove(state.broadcastQueue, 1)
		mq.cmd(commandLine)
		local delayTime = math.random(400, 800)
		mq.delay(delayTime)
	else
		mq.delay(100)
	end

	-- Check for save request from UI
	if state.saveRequested then
		saveHistory()
		state.saveRequested = false
	end
end

-- Save on exit
saveHistory()
