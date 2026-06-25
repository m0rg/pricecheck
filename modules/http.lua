local mq = require("mq")

local http = {}
local json
local curl
local curl_ok = false

function http.setup(jsonModule, curlModule)
	json = jsonModule
	curl = curlModule
	curl_ok = (curl ~= nil)
end

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
	if not curl_ok or not curl then
		if onComplete then
			onComplete(false, nil, "curl Library Missing")
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
	local serverName = (mq.TLO.EverQuest.Server and mq.TLO.EverQuest.Server()) or "Frostreaver"
	local url = string.format(
		"https://tlp-auctions.com/api/prices/pricecheck?serverName=%s&searchTerm=%s",
		http.urlEncode(serverName),
		encodedName
	)

	local response_body = {}
	local ok, result = pcall(function()
		local c = curl.easy{
			url = url,
			writefunction = function(data)
				table.insert(response_body, data)
			end
		}
		c:perform()
		local code = c:getinfo(curl.INFO_RESPONSE_CODE)
		c:close()
		return { body = table.concat(response_body), code = code }
	end)

	if not ok or not result or result.code ~= 200 then
		local errCode = (result and result.code) and tostring(result.code) or "Request Failed"
		if onComplete then
			onComplete(false, nil, "Error (" .. errCode .. ")")
		end
		return
	end

	local status, decoded = pcall(json.decode, result.body)
	if not status or type(decoded) ~= "table" then
		if onComplete then
			onComplete(false, nil, "JSON Error")
		end
		return
	end

	local cleanData = decoded
	if decoded[1] and type(decoded[1]) == "table" then
		cleanData = decoded[1]
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
	if not curl_ok or not curl then
		if onComplete then
			onComplete(nil, false, "curl Library Missing")
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
	local serverName = (mq.TLO.EverQuest.Server and mq.TLO.EverQuest.Server()) or "Frostreaver"
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
		local ok_req, result = pcall(function()
			local c = curl.easy{
				url = "https://tlp-auctions.com/api/prices/bulk",
				post = true,
				postfields = body,
				httpheader = {
					"Content-Type: application/json",
					"Content-Length: " .. tostring(#body),
				},
				writefunction = function(data)
					table.insert(response_body, data)
				end
			}
			c:perform()
			local code = c:getinfo(curl.INFO_RESPONSE_CODE)
			c:close()
			return { body = table.concat(response_body), code = code }
		end)

		if not ok_req or not result or result.code ~= 200 then
			lastError = (result and result.code) and tostring(result.code) or "Request Failed"
			break
		end

		local ok_dec, decoded = pcall(json.decode, result.body)
		if not ok_dec or type(decoded) ~= "table" then
			lastError = "JSON decoding error"
			break
		end

		kronoRate = decoded.kronoRate or kronoRate
		lastUpdated = decoded.lastUpdated or lastUpdated
		if decoded.items then
			for _, item in ipairs(decoded.items) do
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
