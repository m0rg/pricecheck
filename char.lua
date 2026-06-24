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

-- Returns the database link for an item by name
function char.getItemLink(itemName)
	if not itemName or itemName == "" then
		return nil
	end
	local eqLink = mq.TLO.LinkDB(string.format('=%s', itemName))()
	if eqLink and eqLink ~= "" then
		return eqLink
	end
	return nil
end

-- Returns the name of the item currently held on the cursor
function char.getCursorItemName()
	local cursorItem = mq.TLO.Cursor
	if cursorItem and cursorItem() then
		return cursorItem.Name()
	end
	return nil
end

-- Returns the vendor value (in copper) of an item by name
function char.getItemValue(itemName)
	if not itemName or itemName == "" then
		return 0
	end
	local itemObj = mq.TLO.FindItem(string.format('=%s', itemName))
	if itemObj and itemObj() then
		return itemObj.Value() or 0
	end
	return 0
end

return char
