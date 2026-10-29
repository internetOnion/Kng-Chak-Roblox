--!strict
--[[
	RunEvents: the event hub of one Run.

	Each Run owns one hub. UI, audio and game flow listen to the active Run's hub
	(or to GameEvents, which forwards it) instead of reaching into the simulation.

	    run.Events.PlanetHit:Connect(function(rock, damagePercent) ... end)

	Each event lists its arguments, in order. Rocks passed to handlers are frozen
	copies of the rock's state (see Rocks/Rock) at the moment the event fired.
]]

local Signal = require("../Util/Signal")

export type RunEvents = {
	-- (rock: Rock, cause: string)
	-- The player destroyed a rock. cause says how: "Ram" (boosted spear) or "Dive" (slingshot).
	RockBroken: Signal.Signal,

	-- (rock: Rock)
	-- A rock became primed (pushed by the flame), on the first prime only.
	RockPrimed: Signal.Signal,

	-- (rock: Rock, damagePercent: number)
	-- A rock reached the planet. Planet HP drops by damagePercent right after.
	PlanetHit: Signal.Signal,

	-- (rock: Rock, knock: Vector2)
	-- A rock hit the ship's back half, or its soft nose. knock is the velocity the ship is knocked away with.
	ShipBumped: Signal.Signal,

	-- ()
	-- The ship flew into the orbit band and locked onto the orbit track.
	OrbitLocked: Signal.Signal,

	-- ()
	-- The ship left the orbit.
	OrbitLeft: Signal.Signal,

	-- ()
	-- The ship stayed in orbit past the capture time: from now on, leaving costs a boost.
	OrbitCaptured: Signal.Signal,

	-- (target: Rock?)
	-- The ship launched a slingshot dive out of orbit, locked onto target (nil when nothing was ahead).
	Slingshot: Signal.Signal,

	-- (wave: number)
	-- A wave began.
	WaveStarted: Signal.Signal,

	-- (wave: number)
	-- Every rock of the wave is gone and the planet survived.
	WaveCleared: Signal.Signal,

	-- (wave: number)
	-- Planet HP reached 0 during this wave.
	GameOver: Signal.Signal,
}

local RunEvents = {}

-- Every event name, in a fixed order. Code that handles all events loops over this.
RunEvents.Names = table.freeze({
	"RockBroken",
	"RockPrimed",
	"PlanetHit",
	"ShipBumped",
	"OrbitLocked",
	"OrbitLeft",
	"OrbitCaptured",
	"Slingshot",
	"WaveStarted",
	"WaveCleared",
	"GameOver",
})

function RunEvents.new(): RunEvents
	local events = {}
	for _, name in RunEvents.Names do
		events[name] = Signal.new()
	end
	return table.freeze(events) :: any
end

-- The signal for an event name, for code that loops over RunEvents.Names.
function RunEvents.Get(events: RunEvents, name: string): Signal.Signal
	return (events :: any)[name]
end

-- Disconnects every handler, for when the Run is destroyed.
function RunEvents.DisconnectAll(events: RunEvents)
	for _, name in RunEvents.Names do
		RunEvents.Get(events, name):DisconnectAll()
	end
end

return table.freeze(RunEvents)
