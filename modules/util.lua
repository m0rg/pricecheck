local util = {}

local function getTimezoneBias()
	local now = os.time()
	return os.difftime(now, os.time(os.date("!*t", now)))
end

function util.parseISOTimestamp(str)
	if not str then
		return nil
	end
	local year, month, day, hour, min, sec = str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
	if not year then
		return nil
	end

	local utcTime = os.time({ year = year, month = month, day = day, hour = hour, min = min, sec = sec })
	if not utcTime then
		return nil
	end

	return utcTime + getTimezoneBias()
end

function util.formatNumber(amount)
	if not amount then
		return "N/A"
	end
	local formatted = tostring(amount)
	while true do
		local k
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return formatted
end

function util.formatVendorPrice(value)
	if not value or value <= 0 then
		return "-"
	end

	local parts = {}
	for _, unit in ipairs({ { 1000, "p" }, { 100, "g" }, { 10, "s" }, { 1, "c" } }) do
		local amt = math.floor(value / unit[1])
		if amt > 0 then
			table.insert(parts, amt .. unit[2])
			value = value % unit[1]
		end
	end
	return table.concat(parts, " ")
end

function util.getRelativeTimeString(isoStr)
	local pastTime = util.parseISOTimestamp(isoStr)
	if not pastTime then
		return "Unknown time"
	end

	local diff = os.difftime(os.time(), pastTime)
	if diff < 0 then
		diff = 0
	end

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

function util.buildBroadcastTimeline(realAuctionLines, interval, cmd)
	local timeline = {}
	if not realAuctionLines or #realAuctionLines == 0 then
		return timeline
	end

	for i, lineText in ipairs(realAuctionLines) do
		local _, commaCount = lineText:gsub(",", "")
		local count = commaCount + 1

		table.insert(timeline, {
			type = "send",
			message = lineText,
			count = count,
			cmd = cmd,
			duration = 1,
			description = string.format("sending %d items to %q, 1s pause", count, cmd)
		})

		if i % 5 == 0 and i < #realAuctionLines then
			table.insert(timeline, {
				type = "pause",
				duration = 60,
				reason = "Anti-Spam Pause",
				description = "Pause 1 Minute (Anti-Spam Pause)"
			})
		end
	end

	table.insert(timeline, {
		type = "pause",
		duration = interval,
		reason = "Broadcast Interval",
		description = string.format("Pause %d Seconds (Broadcast Interval before repeat)", interval)
	})

	return timeline
end

return util
