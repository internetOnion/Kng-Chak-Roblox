--!strict
--[[
	GameEvents: the active Run's events, in one place that outlives every Run.

	Each Run owns its own event hub (see Run/RunEvents). GameEvents has the same
	events and re-fires whatever the Run it follows fires, so a listener connected
	here keeps working across restarts without knowing which Run is active.

	    local GameEvents = require(ReplicatedStorage.KngChak.GameEvents)
	    GameEvents.PlanetHit:Connect(function(rock, damagePercent) ... end)

	    GameEvents.Follow(run.Events) -- whoever starts a Run points GameEvents at it
	    GameEvents.Follow(nil)        -- stop forwarding

	The events and their arguments are listed in Run/RunEvents. Only the Run fires
	them; never fire GameEvents directly. The game runs on the player's client, so
	these fire there. A script on the server gets its own copy that never fires.
]]

local RunEvents = require("./Run/RunEvents")
local Signal = require("./Util/Signal")

export type GameEvents = RunEvents.RunEvents & {
	Follow: (events: RunEvents.RunEvents?) -> (),
}

local forwarded = RunEvents.new()
local links: { Signal.Connection } = {}

local function follow(events: RunEvents.RunEvents?)
	for _, link in links do
		link:Disconnect()
	end
	table.clear(links)
	if not events then
		return
	end
	for _, name in RunEvents.Names do
		local target = RunEvents.Get(forwarded, name)
		table.insert(
			links,
			RunEvents.Get(events, name):Connect(function(...)
				target:Fire(...)
			end)
		)
	end
end

local GameEvents = setmetatable({ Follow = follow }, { __index = forwarded })

return (table.freeze(GameEvents) :: any) :: GameEvents
