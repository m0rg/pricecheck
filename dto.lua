local dto = {}

-- History entry DTO
function dto.newHistoryEntry(itemName, status, id, data, listedPrice)
	return {
		id = id or tostring(os.clock() + math.random()):gsub("%.", ""),
		item = itemName,
		status = status or "Searching...",
		data = data or nil,
		listedPrice = listedPrice or 0
	}
end

-- Bulk inventory check item entry DTO
function dto.newBulkEntry(itemId, itemName, status, medianPlatPrice, hasData, sampleSize)
	return {
		itemId = itemId,
		item = itemName,
		status = status or "Not Checked",
		medianPlatPrice = medianPlatPrice or nil,
		hasData = hasData or false,
		sampleSize = sampleSize or 0
	}
end

-- Received tell entry DTO
function dto.newTellEntry(sender, message, timestamp)
	return {
		sender = sender,
		message = message,
		time = timestamp or os.time()
	}
end

return dto
