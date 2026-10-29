--!strict
--[[
	Context: what the Run hands its inner modules (flight, orbit, combat) each sub-step.

	The Run builds one per Run and keeps `rocks` pointing at the rocks alive right
	now. The inner modules read the tuning, change the ship, rocks, combo and
	planet they're given and fire the Run's events; they never keep the context
	between steps.
]]

local Combo = require("../Combat/Combo")
local PlanetHealth = require("../Combat/PlanetHealth")
local Rock = require("../Rocks/Rock")
local RunEvents = require("./RunEvents")
local Tuning = require("./Tuning")

export type Context = {
	tuning: Tuning.Tuning,
	events: RunEvents.RunEvents,
	rocks: { Rock.Rock },
	combo: Combo.Combo,
	planet: PlanetHealth.PlanetHealth,
}

return table.freeze({})
