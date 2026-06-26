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

			state:addReceivedTell(sender, message, dto)
		end
	end)
end

local nextBroadcastTime = 0
local recentMessageTimes = {}

-- Processes the broadcast command queue with hardcoded delay and rate-limiting (non-blocking)
function chat.processBroadcastQueue(state)
	local currentClock = mq.gettime()
	if currentClock < nextBroadcastTime then
		return false
	end

	-- Clean up timestamps older than 60,000 milliseconds (60 seconds)
	while #recentMessageTimes > 0 and (currentClock - recentMessageTimes[1] > 60000) do
		table.remove(recentMessageTimes, 1)
	end

	-- Limit the messages to a maximum of 5 per minute
	if #recentMessageTimes >= 5 then
		local nextAllowedTime = recentMessageTimes[1] + 60000
		if currentClock < nextAllowedTime then
			return false
		end
	end

	if #state.broadcastQueue > 0 then
		local commandLine = state:popBroadcastQueue()
		mq.cmdf(commandLine)
		
		-- Record this send time
		table.insert(recentMessageTimes, currentClock)
		
		-- Hardcoded limit of 1000ms (1 second) between consecutive messages
		nextBroadcastTime = currentClock + 1000
		return true
	end
	return false
end

-- Executes an arbitrary MacroQuest command immediately
function chat.executeCommand(commandLine)
	if commandLine and commandLine ~= "" then
		mq.cmdf(commandLine)
	end
end

return chat
