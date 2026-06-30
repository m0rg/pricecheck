local mq = require("mq")

local chat = {}
local dto

function chat.setup(dtoModule)
	dto = dtoModule
end

function chat.registerTellEvent(state)
	mq.event("TellEvent", "#1# tells you, '#2#", function(line, sender, message)
		if sender and message then
			local me = mq.TLO.Me
			local myName = me and me() and me.CleanName()
			if myName and sender:lower() == myName:lower() then
				return
			end

			if message:sub(-1) == "'" then
				message = message:sub(1, -2)
			end

			state:addReceivedTell(sender, message, dto)
		end
	end)
end

function chat.processBroadcastQueue(state)
	if not state.isBroadcastingToggled then
		return false
	end

	local nowMs = mq.gettime()
	local nowSec = os.time()

	if nowMs < (state.nextBroadcastTime or 0) then
		return false
	end

	-- Initialize timeline if it doesn't exist
	if not state.timeline or #state.timeline == 0 then
		local ui = require("modules.ui")
		local util = require("modules.util")
		local realAuctionLines = ui.getAuctionLines(state, true)
		if #realAuctionLines == 0 then
			state.isBroadcastingToggled = false
			return false
		end
		local cmd = (state.config.broadcastCommand and state.config.broadcastCommand ~= "") and state.config.broadcastCommand or "/auction"
		local interval = state.config.broadcastInterval or 120
		local timeline = util.buildBroadcastTimeline(realAuctionLines, interval, cmd)
		state.timeline = timeline
		state.currentStepIndex = 1
		state.nextBroadcastTime = 0
	end

	local idx = state.currentStepIndex or 1

	-- If the last executed step's timer has expired, we advance the index
	if state.nextBroadcastTime > 0 then
		idx = idx + 1
		state.currentStepIndex = idx
	end

	if idx > #state.timeline then
		-- Cycle complete, rebuild for next cycle
		local ui = require("modules.ui")
		local util = require("modules.util")
		local realAuctionLines = ui.getAuctionLines(state, true)
		if #realAuctionLines == 0 then
			state.isBroadcastingToggled = false
			state.timeline = nil
			return false
		end
		local cmd = (state.config.broadcastCommand and state.config.broadcastCommand ~= "") and state.config.broadcastCommand or "/auction"
		local interval = state.config.broadcastInterval or 120
		local timeline = util.buildBroadcastTimeline(realAuctionLines, interval, cmd)
		state.timeline = timeline
		state.currentStepIndex = 1
		state.nextBroadcastTime = 0
		idx = 1
	end

	local step = state.timeline[idx]
	if not step then
		return false
	end

	-- Execute current step
	if step.type == "send" then
		mq.cmdf(step.message)
		state.stepEndTime = nowSec + 1
		state.nextBroadcastTime = nowMs + 1000
	elseif step.type == "pause" then
		state.stepEndTime = nowSec + step.duration
		state.nextBroadcastTime = nowMs + step.duration * 1000
	end

	return true
end

function chat.getRateLimitRemaining(state)
	if not state or not state.isBroadcastingToggled or not state.timeline or not state.currentStepIndex then
		return 0
	end
	local idx = state.currentStepIndex
	local step = state.timeline[idx]
	if step and step.type == "pause" then
		return math.max(0, (state.stepEndTime or 0) - os.time())
	end
	return 0
end

function chat.executeCommand(commandLine)
	if commandLine and commandLine ~= "" then
		mq.cmdf(commandLine)
	end
end

return chat
