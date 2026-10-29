--[[
	Client entry point. The game runs here, on the player's device: flight, rocks,
	combat and UI all live on the client, and the server stays thin.
]]

local RunService = game:GetService("RunService")

-- Studio-only dev tools. Switch them on or off here; they never run in a live game.
local DEV_TOOLS = {
	EventLogger = true, -- prints every GameEvents event to Output
}

if RunService:IsStudio() then
	for name, enabled in DEV_TOOLS do
		local module = script.Dev:FindFirstChild(name)
		if enabled and module then
			task.spawn(require(module) :: () -> ())
		end
	end
end

require(script.Game)()
