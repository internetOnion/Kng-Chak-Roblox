--!strict
--[[
	Run: one emergency call, as a headless simulation.

	    local run = Run.new({
	        Rocks = { { Type = RockTypes.Rock, Position = Vector2.new(0, 40) } },
	    })
	    run.Events.PlanetHit:Connect(function(rock, damagePercent) ... end)

	    -- every frame:
	    run:Step(input, dt)
	    local snapshot = run:Snapshot()

	The Run holds the game rules. It knows nothing about Parts, cameras or GUIs and
	creates no Instances: views read its snapshot and events and never change it.
	Step splits the frame's time into fixed sub-steps, so results don't depend on
	the frame rate. Every tuning value comes from the Run's tuning (see Run/Tuning).
]]

local Flight = require("../Ship/Flight")
local PlanetHealth = require("../Combat/PlanetHealth")
local Rock = require("../Rocks/Rock")
local RockTypes = require("../Data/RockTypes")
local RunEvents = require("./RunEvents")
local RunInput = require("./RunInput")
local Ship = require("../Ship/Ship")
local Tuning = require("./Tuning")

local STEP = 1 / 60 -- seconds per fixed sub-step
local MAX_FRAME = 0.25 -- a longer frame (a hitch) only advances this much, so nothing teleports
local EPSILON = 1e-9 -- absorbs float error, so 1/30 s always makes exactly two sub-steps

export type Input = RunInput.RunInput

export type RockSetup = {
	Type: RockTypes.RockType,
	Position: Vector2,
}

export type Setup = {
	Rocks: { RockSetup }?, -- rocks already in the arena when the run starts
	ShipStart: Vector2?, -- default: the arena data's ShipStart
	ShipHeading: number?, -- radians; default: nose straight down the screen
	Tuning: Tuning.Overrides?, -- changes to the data's tuning values for this run
}

-- What other code may read. Rebuilt on every Snapshot() call; changing it changes nothing.
export type Snapshot = {
	PlanetHp: number,
	PlanetMaxHp: number,
	Ship: Ship.Ship,
	FuelMax: number,
	Rocks: { Rock.Rock },
}

local Run = {}
Run.__index = Run

Run.IdleInput = RunInput.Idle

export type Run = typeof(setmetatable(
	{} :: {
		Events: RunEvents.RunEvents,
		_tuning: Tuning.Tuning,
		_planet: PlanetHealth.PlanetHealth,
		_ship: Ship.Ship,
		_rocks: { Rock.Rock },
		_nextRockId: number,
		_pending: number, -- frame time not simulated yet, less than one sub-step
		_boostQueued: boolean, -- a boost press waiting for the next sub-step
	},
	Run
))

local function addRock(self: Run, rockType: RockTypes.RockType, position: Vector2)
	table.insert(self._rocks, Rock.new(self._nextRockId, rockType, position))
	self._nextRockId += 1
end

local function stepRocks(self: Run, dt: number)
	local planetRadius = self._tuning.Arena.PlanetRadius
	local survivors = {}
	for _, rock in self._rocks do
		Rock.Fall(rock, dt)
		if Rock.TouchesPlanet(rock, planetRadius) then
			local damage = rock.Type.DamagePercent
			self.Events.PlanetHit:Fire(Rock.Snapshot(rock), damage)
			self._planet:TakeDamage(damage)
		else
			table.insert(survivors, rock)
		end
	end
	self._rocks = survivors
end

local function tick(self: Run, input: Input, dt: number)
	local boostPressed = self._boostQueued
	self._boostQueued = false
	Flight.Step(self._ship, self._tuning, input, boostPressed, dt)
	stepRocks(self, dt)
end

function Run.new(setup: Setup?): Run
	local tuning = Tuning.new(setup and setup.Tuning)
	local self = setmetatable({
		Events = RunEvents.new(),
		_tuning = tuning,
		_planet = PlanetHealth.new(tuning.Arena.PlanetMaxHp),
		_ship = Ship.new(
			setup and setup.ShipStart or tuning.Arena.ShipStart,
			tuning.Ship.FuelMax,
			setup and setup.ShipHeading
		),
		_rocks = {},
		_nextRockId = 1,
		_pending = 0,
		_boostQueued = false,
	}, Run)
	local rocks = setup and setup.Rocks
	if rocks then
		for _, rock in rocks do
			addRock(self, rock.Type, rock.Position)
		end
	end
	return self
end

-- Advances the run by dt seconds of play, with this frame's input.
function Run.Step(self: Run, input: Input, dt: number)
	if input.BoostPressed then
		-- kept until a sub-step takes it, so a press on a short frame isn't lost
		self._boostQueued = true
	end
	self._pending += math.clamp(dt, 0, MAX_FRAME)
	while self._pending >= STEP - EPSILON do
		self._pending = math.max(0, self._pending - STEP)
		tick(self, input, STEP)
	end
end

function Run.Snapshot(self: Run): Snapshot
	local rocks = table.create(#self._rocks)
	for _, rock in self._rocks do
		table.insert(rocks, Rock.Snapshot(rock))
	end
	return table.freeze({
		PlanetHp = self._planet.Hp,
		PlanetMaxHp = self._planet.MaxHp,
		Ship = Ship.Snapshot(self._ship),
		FuelMax = self._tuning.Ship.FuelMax,
		Rocks = table.freeze(rocks),
	})
end

-- The tuning values this run plays with.
function Run.GetTuning(self: Run): Tuning.Tuning
	return self._tuning
end

-- Replaces this run's tuning overrides (Studio tuning panel). The data modules don't change.
function Run.SetTuning(self: Run, overrides: Tuning.Overrides?)
	self._tuning = Tuning.new(overrides)
end

function Run.Destroy(self: Run)
	RunEvents.DisconnectAll(self.Events)
	self._planet:Destroy()
end

return Run
