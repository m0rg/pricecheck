local PackageMan = require("mq/PackageMan")
local https = require("ssl.https")
local json = PackageMan.Require("lua-cjson", "cjson")

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

-- Function to execute the HTTP request (run only in the main script loop)
function http.performSearch(entry, onComplete)
	if not entry then
		return
	end

	local encodedName = http.urlEncode(entry.item)
	local url = string.format(
		"https://tlp-auctions.com/api/prices/pricecheck?serverName=Frostreaver&searchTerm=%s",
		encodedName
	)

	local ok, res, code = pcall(https.request, url)

	if not ok or code ~= 200 or not res then
		local errCode = code and tostring(code) or "Request Failed"
		entry.status = "Error (" .. errCode .. ")"
		if onComplete then
			onComplete(entry, false)
		end
		return
	end

	local status, result = pcall(json.decode, res)
	if not status or type(result) ~= "table" then
		entry.status = "JSON Error"
		if onComplete then
			onComplete(entry, false)
		end
		return
	end

	local cleanData = result
	if result[1] and type(result[1]) == "table" then
		cleanData = result[1]
	end

	if cleanData and (cleanData.sellAverage or cleanData.buyAverage) then
		entry.status = "Success"
		entry.data = cleanData
		if onComplete then
			onComplete(entry, true)
		end
	else
		entry.status = "No price found"
		if onComplete then
			onComplete(entry, false)
		end
	end
end

return http
