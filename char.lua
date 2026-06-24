local mq = require("mq")

local char = {}

-- Scans character inventory and returns all unique items in worn bag slots (23 to 34)
function char.getInventoryItems()
	local items = {}
	local seenIds = {}
	for i = 23, 34 do
		local bag = mq.TLO.Me.Inventory(i)
		if bag and bag() then
			if bag.Container() and bag.Container() > 0 then
				for slot = 1, bag.Container() do
					local item = bag.Item(slot)
					if item and item() then
						local itemId = item.ID()
						local itemName = item.Name()
						if itemId and itemId > 0 and not seenIds[itemId] then
							seenIds[itemId] = true
							table.insert(items, { id = itemId, name = itemName })
						end
					end
				end
			else
				local itemId = bag.ID()
				local itemName = bag.Name()
				if itemId and itemId > 0 and not seenIds[itemId] then
					seenIds[itemId] = true
					table.insert(items, { id = itemId, name = itemName })
				end
			end
		end
	end
	return items
end

-- Returns inventory and bank counts of an item
function char.getItemCounts(itemName)
	if not itemName or itemName == "" then
		return 0, 0
	end
	local countObj = mq.TLO.FindItemCount(string.format('=%s', itemName))
	local count = (countObj and countObj()) or 0
	local bankObj = mq.TLO.FindItemBankCount(string.format('=%s', itemName))
	local bankCount = (bankObj and bankObj()) or 0
	return count, bankCount
end

return char
