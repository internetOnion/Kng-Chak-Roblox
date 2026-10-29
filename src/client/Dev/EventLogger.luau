--!strict
--[[
	EventLogger (Studio only): prints every GameEvents event to Output, so you can
	check an event fires without writing a listener.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameEvents = require(ReplicatedStorage.KngChak.GameEvents)
local RunEvents = require(ReplicatedStorage.KngChak.Run.RunEvents)

local function describe(value: any): string
	if type(value) == "table" and type(value.Type) == "table" and value.Type.Id then
		return `{value.Type.Id} rock`
	end
	return tostring(value)
end

return function()
	for _, name in RunEvents.Names do
		RunEvents.Get(GameEvents, name):Connect(function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				table.insert(parts, describe((select(i, ...))))
			end
			print(`[GameEvents] {name}({table.concat(parts, ", ")})`)
		end)
	end
end
