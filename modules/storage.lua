local mq = require("mq")

local storage = {}
local json

function storage.setup(jsonModule)
	json = jsonModule
end

function storage.loadConfig(defaultConfig)
	local savePath = string.format("%s/pricecheck_config.json", mq.configDir or ".")
	local file = io.open(savePath, "r")
	if not file then
		return defaultConfig
	end
	local content = file:read("*all")
	file:close()
	if not content or content == "" then
		return defaultConfig
	end
	local status, data = pcall(json.decode, content)
	if not status or type(data) ~= "table" then
		return defaultConfig
	end
	-- Merge defaults for missing keys
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
	local savePath = string.format("%s/pricecheck_config.json", mq.configDir or ".")
	local file = io.open(savePath, "w")
	if not file then
		return false, "Failed to open config file for writing"
	end
	local status, content = pcall(json.encode, config)
	if not status or not content then
		file:close()
		return false, "JSON encoding failed"
	end
	file:write(content)
	file:close()
	return true
end

function storage.loadHistory()
	local savePath = string.format("%s/pricecheck_history.json", mq.configDir or ".")
	local file = io.open(savePath, "r")
	if not file then
		return {}
	end
	local content = file:read("*all")
	file:close()
	if not content or content == "" then
		return {}
	end
	local status, data = pcall(json.decode, content)
	if not status then
		return {}
	end
	return data or {}
end

function storage.saveHistory(history)
	if not history then
		return false, "No history to save"
	end
	local savePath = string.format("%s/pricecheck_history.json", mq.configDir or ".")
	local file = io.open(savePath, "w")
	if not file then
		return false, "Failed to open history file for writing"
	end
	local status, content = pcall(json.encode, history)
	if not status or not content then
		file:close()
		return false, "JSON encoding failed"
	end
	file:write(content)
	file:close()
	return true
end

return storage
