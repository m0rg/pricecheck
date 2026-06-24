local util = {}

-- Calculate timezone bias once at load time (DST-safe for current execution session)
local now = os.time()
local timezoneBias = os.difftime(now, os.time(os.date("!*t", now)))

-- Parse ISO 8601 UTC date string into a local Unix timestamp
function util.parseISOTimestamp(str)
	if not str then
		return nil
	end
	-- Pattern matches: YYYY-MM-DDTHH:MM:SS
	local year, month, day, hour, min, sec = str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
	if not year then
		return nil
	end

	-- Create UTC time table (interpreted as local by os.time)
	local utcTime = os.time({ year = year, month = month, day = day, hour = hour, min = min, sec = sec })
	if not utcTime then
		return nil
	end

	return utcTime + timezoneBias
end

-- Format numbers with thousands separators
function util.formatNumber(amount)
	if not amount then
		return "N/A"
	end
	local formatted = tostring(amount)
	while true do
		local k
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
		if k == 0 then
			break
		end
	end
	return formatted
end

-- Format vendor price in gold/silver/copper
function util.formatVendorPrice(value)
	if not value or value <= 0 then
		return "-"
	end
	local plat = math.floor(value / 1000)
	local remainder = value % 1000
	local gold = math.floor(remainder / 100)
	remainder = remainder % 100
	local silver = math.floor(remainder / 10)
	local copper = remainder % 10

	local parts = {}
	if plat > 0 then table.insert(parts, plat .. "p") end
	if gold > 0 then table.insert(parts, gold .. "g") end
	if silver > 0 then table.insert(parts, silver .. "s") end
	if copper > 0 then table.insert(parts, copper .. "c") end

	return table.concat(parts, " ")
end

-- Format an ISO UTC timestamp to relative time string
function util.getRelativeTimeString(isoStr)
	local pastTime = util.parseISOTimestamp(isoStr)
	if not pastTime then
		return "Unknown time"
	end

	local diff = os.difftime(os.time(), pastTime)
	if diff < 0 then
		diff = 0
	end -- Clamp future time sync deviations

	if diff < 60 then
		return "Just now"
	elseif diff < 3600 then
		local mins = math.floor(diff / 60)
		return mins .. "m ago"
	elseif diff < 86400 then
		local hours = math.floor(diff / 3600)
		return hours .. "h ago"
	else
		local days = math.floor(diff / 86400)
		return days .. "d ago"
	end
end

return util
