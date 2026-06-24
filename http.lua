local PackageMan = require("mq/PackageMan")
local mq = require("mq")
local json = PackageMan.Require("lua-cjson", "cjson")
local ltn12 = require("ltn12")

local ssl_ok, https = pcall(require, "ssl.https")

local http = {}

-- Helper function to properly percent-encode URL parameters
function http.urlEncode(str)
	if not str then
		return ""
	end
	str = str:gsub("([^%w%.%-%_])", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
	return str
end

function http.performSearch(itemName, onComplete)
	if not ssl_ok or not https then
		if onComplete then
			onComplete(false, nil, "SSL Library Missing")
		end
		return
	end

	if not itemName or itemName == "" then
		if onComplete then
			onComplete(false, nil, "Invalid Name")
		end
		return
	end

	local encodedName = http.urlEncode(itemName)
	local url = string.format(
		"https://tlp-auctions.com/api/prices/pricecheck?serverName=Frostreaver&searchTerm=%s",
		encodedName
	)

	local ok, res, code = pcall(https.request, url)

	if not ok or code ~= 200 or not res then
		local errCode = code and tostring(code) or "Request Failed"
		if onComplete then
			onComplete(false, nil, "Error (" .. errCode .. ")")
		end
		return
	end

	local status, result = pcall(json.decode, res)
	if not status or type(result) ~= "table" then
		if onComplete then
			onComplete(false, nil, "JSON Error")
		end
		return
	end

	local cleanData = result
	if result[1] and type(result[1]) == "table" then
		cleanData = result[1]
	end

	if cleanData and (cleanData.sellAverage or cleanData.buyAverage) then
		if onComplete then
			onComplete(true, cleanData, "Success")
		end
	else
		if onComplete then
			onComplete(false, nil, "No price found")
		end
	end
end

-- Function to execute bulk HTTP request (run only in main script loop)
function http.performBulkSearch(itemIds, onComplete)
	if not ssl_ok or not https then
		if onComplete then
			onComplete(nil, false, "SSL Library Missing")
		end
		return
	end

	if not itemIds or #itemIds == 0 then
		if onComplete then
			onComplete(nil, false, "No item IDs")
		end
		return
	end

	local aggregatedItems = {}
	local kronoRate = nil
	local lastUpdated = nil
	local serverName = "Frostreaver"
	local lastError = nil

	-- Process itemIds in chunks of 10
	for i = 1, #itemIds, 10 do
		local chunk = {}
		for j = i, math.min(i + 9, #itemIds) do
			table.insert(chunk, itemIds[j])
		end

		local payload = {
			serverName = serverName,
			itemIds = chunk,
		}

		local ok, body = pcall(json.encode, payload)
		if not ok then
			lastError = "JSON encoding error"
			break
		end

		local response_body = {}
		local ok_req, res, code, headers, status = pcall(https.request, {
			url = "https://tlp-auctions.com/api/prices/bulk",
			method = "POST",
			headers = {
				["Content-Type"] = "application/json",
				["Content-Length"] = tostring(#body),
			},
			source = ltn12.source.string(body),
			sink = ltn12.sink.table(response_body),
		})

		if not ok_req or code ~= 200 or not response_body then
			lastError = code and tostring(code) or "Request Failed"
			break
		end

		local resp_str = table.concat(response_body)
		local ok_dec, result = pcall(json.decode, resp_str)
		if not ok_dec or type(result) ~= "table" then
			lastError = "JSON decoding error"
			break
		end

		kronoRate = result.kronoRate or kronoRate
		lastUpdated = result.lastUpdated or lastUpdated
		if result.items then
			for _, item in ipairs(result.items) do
				table.insert(aggregatedItems, item)
			end
		end

		-- Yield to MacroQuest loop between calls if there are more chunks
		if i + 10 <= #itemIds then
			mq.doevents()
			mq.delay(50)
		end
	end

	if #aggregatedItems > 0 then
		local finalResult = {
			serverName = serverName,
			kronoRate = kronoRate,
			lastUpdated = lastUpdated,
			items = aggregatedItems,
		}
		if onComplete then
			onComplete(finalResult, true)
		end
	else
		if onComplete then
			onComplete(nil, false, lastError or "No data returned")
		end
	end
end

return http
