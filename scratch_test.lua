-- Mock the MacroQuest environment
package.preload["mq"] = function()
	local mockMq = {
		configDir = ".",
		TLO = {
			Me = {
				Inventory = function(slot)
					return function() return false end
				end
			},
			FindItemCount = function(query)
				return function() return 1 end
			end,
			FindItemBankCount = function(query)
				return function() return 0 end
			end,
			FindItem = function(query)
				return function() return { Value = function() return 1000 end } end
			end,
			LinkDB = function(query)
				return function() return "[Link]" end
			end,
			Cursor = function()
				return nil
			end
		},
		cmd = function(cmdStr)
			print("[MOCK COMMAND EXECUTED]: " .. cmdStr)
		end,
		delay = function(ms)
			-- No-op in mock
		end,
		doevents = function()
			-- No-op in mock
		end,
		event = function(name, pattern, callback)
			-- No-op in mock
		end,
		imgui = {
			init = function(name, callback)
				print("[MOCK IMGUI INITIALIZED]: " .. name)
			end
		},
		PackageMan = {
			Require = function(pkg, name)
				return require(name)
			end
		}
	}
	return mockMq
end

package.preload["mq/PackageMan"] = function()
	return {
		Require = function(pkg, name)
			return require(name)
		end
	}
end

-- Load the modules
local http = require("http")

print("--- Testing Single API Search ---")
local testEntry = { item = "Krono", status = "Searching..." }
http.performSearch(testEntry, function(entry, success)
	print("Success: ", success)
	print("Status: ", entry.status)
	if success and entry.data then
		print("Average Sell Price: ", entry.data.sellAverage)
	end
end)

print("\n--- Testing Bulk API Search ---")
local bulkIds = { 1001, 2301 } -- Krono and Blue Diamond IDs
http.performBulkSearch(bulkIds, function(result, success, errMsg)
	print("Success: ", success)
	if success and result then
		print("Krono Rate: ", result.kronoRate)
		print("Last Updated: ", result.lastUpdated)
		if result.items then
			for _, item in ipairs(result.items) do
				print(string.format("  Item: %s (ID: %d), Median Price: %s", item.item, item.itemId, tostring(item.medianPlatPrice)))
			end
		end
	else
		print("Error: ", errMsg)
	end
end)
