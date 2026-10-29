--!strict
--[[
	GameEvents: the one place for game-wide events (milestone 1, contract 1, area 4).

	UI, audio and game flow listen here instead of reaching into another area's
	scripts. Gameplay code fires them and never needs to know who is listening.

	    local GameEvents = require(ReplicatedStorage.KngChak.GameEvents)
	    GameEvents.PlanetHit:Connect(function(rock, damagePercent) ... end)

	The game runs on the player's client, so these fire there. A script on the
	server gets its own separate copy that the game never fires.

	Each event lists its arguments, in order. Fire them in that order.
]]

local Signal = require("./Util/Signal")

local GameEvents = {
	-- (rock: Rock, cause: string)
	-- The player destroyed a rock. Fired by Rock:Break(). cause says how, e.g. "Ram".
	RockBroken = Signal.new(),

	-- (rock: Rock)
	-- A rock became primed (pushed by the flame). Fired by Rock:Prime(), only on the first prime.
	RockPrimed = Signal.new(),

	-- (rock: Rock, damagePercent: number)
	-- A rock reached the planet. Fired by the rock fall code (task 10).
	PlanetHit = Signal.new(),

	-- (wave: number)
	-- A wave began. Fired by the wave spawner (task 12).
	WaveStarted = Signal.new(),

	-- (wave: number)
	-- Every rock of the wave is gone and the planet survived. Fired by the wave spawner (task 12).
	WaveCleared = Signal.new(),

	-- (wave: number)
	-- Planet HP reached 0 during this wave. Fired by game flow (task 16).
	GameOver = Signal.new(),
}

return table.freeze(GameEvents)
