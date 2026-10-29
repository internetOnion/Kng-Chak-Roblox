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
	-- The player destroyed a rock. cause says how: "Ram" (a plain boosted ram), "PushBreak"
	-- (primed, then rammed), "Dive" (a slingshot into an unprimed rock) or "Perfect"
	-- (primed, then slingshot).
	RockBroken: Signal.Signal,

	-- (rock: Rock, shards: { Rock })
	-- A broken rock split into shards (a cluster). RockBroken fires for it first.
	RockSplit: Signal.Signal,

	-- (rock: Rock)
	-- A rock became primed (pushed by the flame), on the first prime only.
	RockPrimed: Signal.Signal,

	-- (rock: Rock)
	-- The orbit flare caught a rock: it pops up and hangs nearly still (it's primed too).
	RockFlared: Signal.Signal,

	-- (rock: Rock, damagePercent: number)
	-- A rock reached the planet. Right after, damagePercent comes off the shield first, then HP.
	PlanetHit: Signal.Signal,

	-- (rock: Rock, knock: Vector2)
	-- The spear hit a rock it can't break yet (see RockTypes' BreaksBy): an unpushed comet,
	-- unprimed iron hit by a plain ram, gold without a PERFECT. The ship is knocked back
	-- by knock and briefly stunned; the rock is deflected.
	RockClanged: Signal.Signal,

	-- (rock: Rock, knock: Vector2)
	-- A rock hit the ship's back half, or its soft nose. knock is the velocity the ship is knocked away with.
	ShipBumped: Signal.Signal,

	-- ()
	-- A boost burst started (it cost a boost's fuel).
	Boosted: Signal.Signal,

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

	-- (combo: number, move: string)
	-- The combo changed. move is what changed it: a move that added to it ("Push", "Flare",
	-- "Slingshot", or a RockBroken cause), or why it was lost ("Bump", "Impact", "Timeout"; combo is 0).
	ComboChanged: Signal.Signal,

	-- (rock: Rock)
	-- A PERFECT: a primed rock broken by a slingshot. RockBroken fires for it too, just before.
	Perfect: Signal.Signal,

	-- (amount: number, cause: string)
	-- A combo move repaired the planet by amount % (cause is the RockBroken cause).
	Healed: Signal.Signal,

	-- (shield: number, delta: number)
	-- The planet's shield changed: heals past full HP build it, impacts take it first.
	ShieldChanged: Signal.Signal,

	-- (amount: number)
	-- Breaking a primed rock gave fuel back.
	FuelRefunded: Signal.Signal,

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
	"RockSplit",
	"RockPrimed",
	"RockFlared",
	"PlanetHit",
	"RockClanged",
	"ShipBumped",
	"Boosted",
	"OrbitLocked",
	"OrbitLeft",
	"OrbitCaptured",
	"Slingshot",
	"ComboChanged",
	"Perfect",
	"Healed",
	"ShieldChanged",
	"FuelRefunded",
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
