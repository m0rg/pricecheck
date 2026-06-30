local log = {}

local stateRef = nil

function log.setup(state)
	stateRef = state
end

local function isDebugEnabled()
	if not stateRef or not stateRef.config then
		return true
	end
	if stateRef.config.debug == nil then
		return true
	end
	return stateRef.config.debug == true
end

function log.log(fmt, ...)
	if not isDebugEnabled() then
		return
	end

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

	local ok, message = pcall(string.format, fmt, ...)
	if not ok then
		message = "Formatting error: " .. tostring(fmt)
	end

	local printFunc = printf
	printFunc("[%s:%s] %s", filename, funcname, message)
end

return log
