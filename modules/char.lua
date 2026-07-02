local mq = require("mq")

local char = {}

-- Worn bag inventory slot ranges (pack1 through pack12)
local BAG_SLOT_START = 23
local BAG_SLOT_END = 34

local function isNoTradeItem(itemObj)
	if not itemObj or not itemObj() then
		return false
	end
	local success, result = pcall(function()
		return itemObj.NoTrade and itemObj.NoTrade()
	end)
	if success then
		return result
	end
	local success2, result2 = pcall(function()
		return itemObj.NoDrop and itemObj.NoDrop()
	end)
	if success2 then
		return result2
	end
	return false
end

function char.getUniqueInventoryItemTypes()
	local items = {}
	local seenIds = {}
	local me = mq.TLO.Me
	if not me or not me() then
		return items
	end

	for i = BAG_SLOT_START, BAG_SLOT_END do
		local bag = mq.TLO.Me.Inventory(i)
		if bag and bag() then
			if bag.Container() and bag.Container() > 0 then
				for slot = 1, bag.Container() do
					local item = bag.Item(slot)
					if item and item() and not isNoTradeItem(item) then
						local itemId = item.ID()
						local itemName = item.Name()
						if itemId and itemId > 0 and not seenIds[itemId] then
							seenIds[itemId] = true
							table.insert(items, { id = itemId, name = itemName })
						end
					end
				end
			else
				if not isNoTradeItem(bag) then
					local itemId = bag.ID()
					local itemName = bag.Name()
					if itemId and itemId > 0 and not seenIds[itemId] then
						seenIds[itemId] = true
						table.insert(items, { id = itemId, name = itemName })
					end
				end
			end
		end
	end
	return items
end

function char.getItemCounts(itemName)
	if not itemName or itemName == "" then
		return 0, 0
	end
	local countObj = mq.TLO.FindItemCount(string.format("=%s", itemName))
	local count = (countObj and countObj()) or 0
	local bankObj = mq.TLO.FindItemBankCount(string.format("=%s", itemName))
	local bankCount = (bankObj and bankObj()) or 0
	return count, bankCount
end

function char.getItemLink(itemName)
	if not itemName or itemName == "" then
		return nil
	end
	local eqLink = mq.TLO.LinkDB(string.format("=%s", itemName))()
	if eqLink and eqLink ~= "" then
		return eqLink
	end
	return nil
end

function char.getCursorItemName()
	local cursorItem = mq.TLO.Cursor
	if cursorItem and cursorItem() then
		return cursorItem.Name()
	end
	return nil
end

function char.getItemValue(itemName)
	if not itemName or itemName == "" then
		return 0
	end
	local itemObj = mq.TLO.FindItem(string.format("=%s", itemName))
	if itemObj and itemObj() then
		return itemObj.Value() or 0
	end
	return 0
end

return char
