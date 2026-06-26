local log = {}

local stateRef = nil

-- setup registers a reference to the shared state containing the config
function log.setup(state)
	stateRef = state
end

-- Check if debugging is enabled (defaults to true if state is not yet initialized)
local function isDebugEnabled()
	if not stateRef or not stateRef.config then
		return true
	end
	if stateRef.config.debug == nil then
		return true
	end
	return stateRef.config.debug == true
end

-- log writes formatted messages stating the source file and calling function
function log.log(fmt, ...)
	if not isDebugEnabled() then
		return
	end

	-- Look up the stack info of the caller (level 2)
	local info = debug.getinfo(2, "nS")
	local filename = "unknown"
	local funcname = "main chunk"

	if info then
		if info.short_src then
			filename = info.short_src:match("[^/\\]+$") or info.short_src
		end
		if info.name and info.name ~= "" then
			funcname = info.name
		end
	end

	-- Format the message
	local ok, message = pcall(string.format, fmt, ...)
	if not ok then
		message = "Formatting error: " .. tostring(fmt)
	end

	-- maybe file logging later, but for now just print to MQ console
	local printFunc = printf
	printFunc("[%s:%s] %s", filename, funcname, message)
end

return log
