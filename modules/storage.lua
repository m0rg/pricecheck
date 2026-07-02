local mq = require("mq")

local storage = {}

function storage.loadConfig(defaultConfig)
	local savePath = string.format("%s/pricecheck_config.lua", mq.configDir)
	local data = mq.unpickle(savePath)
	if type(data) ~= "table" then
		return defaultConfig
	end
	for k, v in pairs(defaultConfig) do
		if data[k] == nil then
			data[k] = v
		end
	end
	return data
end

function storage.saveConfig(config)
	if not config then
		return false, "No config to save"
	end
	local savePath = string.format("%s/pricecheck_config.lua", mq.configDir)
	local success, err = pcall(mq.pickle, savePath, config)
	if not success then
		return false, err or "Pickle failed"
	end
	return true
end

function storage.loadHistory()
	local savePath = string.format("%s/pricecheck_history.lua", mq.configDir)
	local data = mq.unpickle(savePath)
	if type(data) ~= "table" then
		return {}
	end
	return data
end

function storage.saveHistory(history)
	if not history then
		return false, "No history to save"
	end
	local savePath = string.format("%s/pricecheck_history.lua", mq.configDir)
	local success, err = pcall(mq.pickle, savePath, history)
	if not success then
		return false, err or "Pickle failed"
	end
	return true
end

function storage.loadChangelog()
	local path = string.format("%s/pricecheck/CHANGELOG.md", mq.luaDir)
	local f = io.open(path, "r")
	if not f then
		f = io.open("CHANGELOG.md", "r")
	end
	if not f then
		f = io.open("pricecheck/CHANGELOG.md", "r")
	end
	if not f then
		return "Error: Could not load CHANGELOG.md"
	end
	local content = f:read("*a")
	f:close()
	return content
end

return storage
