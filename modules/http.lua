local mq = require("mq")

local http = {}
local json
local curl
local curl_ok = false
local multi
local activeRequests = {}

function http.setup(jsonModule, curlModule)
	json = jsonModule
	curl = curlModule
	curl_ok = (curl ~= nil)
	if curl_ok and not multi then
		multi = curl.multi()
	end
end

function http.tick()
	if not curl_ok or not multi then
		return
	end

	local status, running = pcall(multi.perform, multi)
	if not status then
		return
	end

	while true do
		local easy, ok, err = multi:info_read()
		if not easy or easy == 0 then
			break
		end

		local req = activeRequests[easy]
		if req then
			activeRequests[easy] = nil
			multi:remove_handle(easy)

			local code = easy:getinfo(curl.INFO_RESPONSE_CODE)
			easy:close()

			local responseText = table.concat(req.body)
			if not err and code == 200 then
				req.onComplete(true, responseText)
			else
				local errMsg = err and tostring(err) or ("HTTP " .. tostring(code))
				req.onComplete(false, nil, errMsg)
			end
		else
			multi:remove_handle(easy)
			easy:close()
		end
	end
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
	local c
	local ok, err = pcall(function()
		c = curl.easy{
			url = url,
			writefunction = function(data)
				table.insert(response_body, data)
			end
		}
	end)

	if not ok or not c then
		if onComplete then
			onComplete(false, nil, "Failed to create curl handle: " .. tostring(err))
		end
		return
	end

	activeRequests[c] = {
		body = response_body,
		onComplete = function(success, body, errMsg)
			if not success then
				if onComplete then
					onComplete(false, nil, errMsg or "Request Failed")
				end
				return
			end

			local status, decoded = pcall(json.decode, body)
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
	}

	multi:add_handle(c)
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

	local serverName = (mq.TLO.EverQuest.Server and mq.TLO.EverQuest.Server()) or "Frostreaver"
	local chunks = {}
	for i = 1, #itemIds, 10 do
		local chunk = {}
		for j = i, math.min(i + 9, #itemIds) do
			table.insert(chunk, itemIds[j])
		end
		table.insert(chunks, chunk)
	end

	local bulkState = {
		total = #chunks,
		completed = 0,
		aggregatedItems = {},
		kronoRate = nil,
		lastUpdated = nil,
		lastError = nil,
		onComplete = onComplete,
		serverName = serverName
	}

	for _, chunk in ipairs(chunks) do
		local payload = {
			serverName = serverName,
			itemIds = chunk,
		}

		local ok, body = pcall(json.encode, payload)
		if not ok then
			bulkState.completed = bulkState.completed + 1
			bulkState.lastError = "JSON encoding error"
			if bulkState.completed == bulkState.total then
				if onComplete then
					onComplete(nil, false, "JSON encoding error")
				end
			end
		else
			local response_body = {}
			local c
			local ok_create, err = pcall(function()
				c = curl.easy{
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
			end)

			if not ok_create or not c then
				bulkState.completed = bulkState.completed + 1
				bulkState.lastError = "Failed to create curl handle: " .. tostring(err)
				if bulkState.completed == bulkState.total then
					if onComplete then
						onComplete(nil, false, bulkState.lastError)
					end
				end
			else
				activeRequests[c] = {
					body = response_body,
					onComplete = function(success, respBody, errMsg)
						bulkState.completed = bulkState.completed + 1
						if success then
							local ok_dec, decoded = pcall(json.decode, respBody)
							if ok_dec and type(decoded) == "table" then
								bulkState.kronoRate = decoded.kronoRate or bulkState.kronoRate
								bulkState.lastUpdated = decoded.lastUpdated or bulkState.lastUpdated
								if decoded.items then
									for _, item in ipairs(decoded.items) do
										table.insert(bulkState.aggregatedItems, item)
									end
								end
							else
								bulkState.lastError = "JSON decoding error"
							end
						else
							bulkState.lastError = errMsg or "Request Failed"
						end

						if bulkState.completed == bulkState.total then
							if #bulkState.aggregatedItems > 0 then
								local finalResult = {
									serverName = bulkState.serverName,
									kronoRate = bulkState.kronoRate,
									lastUpdated = bulkState.lastUpdated,
									items = bulkState.aggregatedItems,
								}
								if bulkState.onComplete then
									bulkState.onComplete(finalResult, true)
								end
							else
								if bulkState.onComplete then
									bulkState.onComplete(nil, false, bulkState.lastError or "No data returned")
								end
							end
						end
					end
				}
				multi:add_handle(c)
			end
		end
	end
end

return http
