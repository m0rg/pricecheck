local mq = require("mq")

-- Use dynamic module paths relative to script invocation to support standard loading
local myPath = ...
if myPath then
	-- Strip trailing .init if present
	myPath = myPath:gsub("%.init$", "")
	myPath = myPath .. "."
else
	myPath = "pricecheck."
end

local ui = require(myPath .. "ui")
local http = require(myPath .. "http")

-- Shared state context table (encapsulating all state without using globals)
local state = {
	openGUI = true,
	isSearching = false,
	priceModifier = 5,
	broadcastCommand = "/auction",
	priceHistory = {},
	activeDetailEntry = nil,
	pendingSearch = nil,
	broadcastQueue = {},
}

-- Register the ImGui render loop callback with the shared state
mq.imgui.init("PriceCheckWindow", function()
	ui.render(state)
end)

-- Main script loop (running in the safe script coroutine thread)
while state.openGUI do
	if state.pendingSearch then
		local entry = state.pendingSearch
		state.pendingSearch = nil
		http.performSearch(entry, function(completedEntry, success)
			state.isSearching = false
		end)
	elseif #state.broadcastQueue > 0 then
		local commandLine = table.remove(state.broadcastQueue, 1)
		mq.cmd(commandLine)
		mq.delay(200)
	else
		mq.delay(100)
	end
end
