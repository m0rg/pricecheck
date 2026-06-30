local logger = require("modules.log")

local dto = {}

function dto.newHistoryEntry(itemName, status, id, data, listedPrice)
	if type(itemName) ~= "string" then
		logger.log("Warning: newHistoryEntry received itemName of type %s, expected string. Coercing to string.", type(itemName))
		itemName = tostring(itemName or "")
	end
	return {
		id = id or string.format("%d_%d", os.time(), math.random(100000, 999999)),
		item = itemName,
		status = status or "Searching...",
		data = data or nil,
		listedPrice = listedPrice or 0,
	}
end

function dto.newBulkEntry(itemId, itemName, status, medianPlatPrice, hasData, sampleSize)
	if type(itemId) ~= "number" then
		logger.log("Warning: newBulkEntry received itemId of type %s, expected number. Coercing to number.", type(itemId))
		itemId = tonumber(itemId) or 0
	end
	if type(itemName) ~= "string" then
		logger.log("Warning: newBulkEntry received itemName of type %s, expected string. Coercing to string.", type(itemName))
		itemName = tostring(itemName or "")
	end
	return {
		itemId = itemId,
		item = itemName,
		status = status or "Not Checked",
		medianPlatPrice = medianPlatPrice or nil,
		hasData = hasData or false,
		sampleSize = sampleSize or 0,
	}
end

function dto.newTellEntry(sender, message, timestamp)
	if type(sender) ~= "string" then
		logger.log("Warning: newTellEntry received sender of type %s, expected string. Coercing to string.", type(sender))
		sender = tostring(sender or "Unknown")
	end
	if type(message) ~= "string" then
		logger.log("Warning: newTellEntry received message of type %s, expected string. Coercing to string.", type(message))
		message = tostring(message or "")
	end
	return {
		sender = sender,
		message = message,
		time = timestamp or os.time(),
	}
end

return dto
