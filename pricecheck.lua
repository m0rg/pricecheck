-- Backward compatibility wrapper pointing to the refactored entrypoint init.lua
local myPath = ...
if myPath then
	require(myPath .. ".init")
else
	require("pricecheck.init")
end
