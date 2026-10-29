--!strict
--[[
	Context: what the Run hands its inner modules (flight, orbit, combat) each sub-step.

	The Run builds one per Run and keeps `rocks` pointing at the rocks alive right
	now. The inner modules read the tuning, change the ship, rocks, combo and
	planet they're given and fire the Run's events; they never keep the context
	between steps (the guided call keeps its event connections, which die with the Run).
]]

local Combo = require("../Combat/Combo")
local PlanetHealth = require("../Combat/PlanetHealth")
local Rng = require("../Util/Rng")
local Rock = require("../Rocks/Rock")
local RockTypes = require("../Data/RockTypes")
local RunEvents = require("./RunEvents")
local Tuning = require("./Tuning")

export type Context = {
	tuning: Tuning.Tuning,
	events: RunEvents.RunEvents,
	rocks: { Rock.Rock },
	combo: Combo.Combo,
	planet: PlanetHealth.PlanetHealth,
	rng: Rng.Rng, -- for combat's random choices (where shards fly); seeded from the Run's seed
	-- A new rock with the next id, not yet in the arena: the caller adds it to the rocks it returns.
	newRock: (
		rockType: RockTypes.RockType,
		position: Vector2,
		speedMult: number?,
		velocity: Vector2?,
		grace: number?
	) -> Rock.Rock,
}

return table.freeze({})
