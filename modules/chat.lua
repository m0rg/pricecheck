local mq = require("mq")

local chat = {}
local dto

-- Injects data transfer dependency (SRP)
function chat.setup(dtoModule)
	dto = dtoModule
end

-- Registers event listener for incoming tells
function chat.registerTellEvent(state)
	mq.event('TellEvent', '#1# tells you, \'#2#', function(line, sender, message)
		if sender and message then
			-- Filter out self-tells
			local me = mq.TLO.Me
			local myName = me and me() and me.CleanName()
			if myName and sender:lower() == myName:lower() then
				return
			end

			-- Clean up the trailing single quote
			if message:sub(-1) == "'" then
				message = message:sub(1, -2)
			end

			table.insert(state.receivedTells, dto.newTellEntry(sender, message))
		end
	end)
end

local nextBroadcastTime = 0

-- Processes the broadcast command queue with configurable random debounced delay (non-blocking)
function chat.processBroadcastQueue(state)
	local currentClock = os.clock()
	if currentClock < nextBroadcastTime then
		return false
	end

	if #state.broadcastQueue > 0 then
		local commandLine = table.remove(state.broadcastQueue, 1)
		mq.cmd(commandLine)
		local min = (state.config and state.config.debounceMin) or 400
		local max = (state.config and state.config.debounceMax) or 600
		if min > max then
			min, max = max, min
		end
		local delayMs = math.random(min, max)
		nextBroadcastTime = currentClock + (delayMs / 1000)
		return true
	end
	return false
end

-- Executes an arbitrary MacroQuest command immediately
function chat.executeCommand(commandLine)
	if commandLine and commandLine ~= "" then
		mq.cmd(commandLine)
	end
end

return chat
