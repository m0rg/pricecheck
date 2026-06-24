local dto = {}

-- History entry DTO with type assertions
function dto.newHistoryEntry(itemName, status, id, data, listedPrice)
	assert(type(itemName) == "string", "itemName must be a string")
	return {
		id = id or string.format("%d_%d", os.time(), math.random(100000, 999999)),
		item = itemName,
		status = status or "Searching...",
		data = data or nil,
		listedPrice = listedPrice or 0
	}
end

-- Bulk inventory check item entry DTO with type assertions
function dto.newBulkEntry(itemId, itemName, status, medianPlatPrice, hasData, sampleSize)
	assert(type(itemId) == "number", "itemId must be a number")
	assert(type(itemName) == "string", "itemName must be a string")
	return {
		itemId = itemId,
		item = itemName,
		status = status or "Not Checked",
		medianPlatPrice = medianPlatPrice or nil,
		hasData = hasData or false,
		sampleSize = sampleSize or 0
	}
end

-- Received tell entry DTO with type assertions
function dto.newTellEntry(sender, message, timestamp)
	assert(type(sender) == "string", "sender must be a string")
	assert(type(message) == "string", "message must be a string")
	return {
		sender = sender,
		message = message,
		time = timestamp or os.time()
	}
end

return dto
