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

local Combat = require("../Combat/Combat")
local Combo = require("../Combat/Combo")
local Context = require("./Context")
local Flight = require("../Ship/Flight")
local PlanetHealth = require("../Combat/PlanetHealth")
local Rng = require("../Util/Rng")
local Rock = require("../Rocks/Rock")
local RockTypes = require("../Data/RockTypes")
local RunEvents = require("./RunEvents")
local RunInput = require("./RunInput")
local Ship = require("../Ship/Ship")
local Tuning = require("./Tuning")
local WaveDirector = require("../Rocks/WaveDirector")

local STEP = 1 / 60 -- seconds per fixed sub-step
local MAX_FRAME = 0.25 -- a longer frame (a hitch) only advances this much, so nothing teleports
local EPSILON = 1e-9 -- absorbs float error, so 1/30 s always makes exactly two sub-steps

export type Input = RunInput.RunInput

export type RockSetup = {
	Type: RockTypes.RockType,
	Position: Vector2,
}

export type WavePlan = WaveDirector.WavePlan

-- Playing a wave, between waves, or over (planet HP reached 0).
export type Phase = WaveDirector.Phase | "Over"

export type Setup = {
	Seed: number?, -- seeds every random choice the run makes (default 1)
	Waves: { WavePlan }?, -- fixed waves instead of the wave data's; {} plays none
	Rocks: { RockSetup }?, -- rocks already in the arena when the run starts
	ShipStart: Vector2?, -- default: the arena data's ShipStart
	ShipHeading: number?, -- radians; default: nose straight down the screen
	Tuning: Tuning.Overrides?, -- changes to the data's tuning values for this run
}

-- What other code may read. Rebuilt on every Snapshot() call; changing it changes nothing.
export type Snapshot = {
	Wave: number, -- 0 before the first wave starts
	Phase: Phase,
	Score: number,
	Combo: number, -- the current chain (0 when there's none)
	BestCombo: number, -- the highest the combo reached this run
	Multiplier: number, -- score multiplier at the current combo
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
		_ctx: Context.Context, -- handed to flight and combat; its rocks are kept in step with _rocks
		_combo: Combo.Combo,
		_nextRockId: number,
		_director: WaveDirector.WaveDirector,
		_score: number,
		_over: boolean,
		_pending: number, -- frame time not simulated yet, less than one sub-step
		_boostQueued: boolean, -- a boost press waiting for the next sub-step
	},
	Run
))

local function addRock(self: Run, rockType: RockTypes.RockType, position: Vector2, speedMult: number?)
	table.insert(self._rocks, Rock.new(self._nextRockId, rockType, position, speedMult))
	self._nextRockId += 1
end

local function stepRocks(self: Run, dt: number)
	local planetRadius = self._tuning.Arena.PlanetRadius
	local survivors = {}
	for _, rock in self._rocks do
		Rock.Fall(rock, self._tuning, dt)
		if Rock.TouchesPlanet(rock, planetRadius) then
			local damage = rock.Type.DamagePercent
			self.Events.PlanetHit:Fire(Rock.Snapshot(rock), damage)
			self._planet:TakeDamage(damage)
			Combo.Lose(self._combo, self.Events, "Impact")
			if self._planet:IsDepleted() and not self._over then
				self._over = true
				self.Events.GameOver:Fire(self._director.Wave)
			end
		else
			table.insert(survivors, rock)
		end
	end
	self._rocks = survivors
	self._ctx.rocks = survivors
end

local function tick(self: Run, input: Input, dt: number)
	local boostPressed = self._boostQueued
	self._boostQueued = false
	Flight.Step(self._ship, self._ctx, input, boostPressed, dt)
	stepRocks(self, dt)
	if self._over then
		return
	end
	local combat = Combat.Step(self._ship, self._ctx)
	self._rocks = combat.survivors
	self._ctx.rocks = combat.survivors
	self._score += combat.score
	Combo.Step(self._combo, self.Events, #self._rocks > 0, dt)
	self._director:Step(dt, {
		tuning = self._tuning,
		events = self.Events,
		rockCount = #self._rocks,
		shipPosition = self._ship.Position,
		spawn = function(rockType: RockTypes.RockType, position: Vector2, speedMult: number)
			addRock(self, rockType, position, speedMult)
		end,
	})
end

function Run.new(setup: Setup?): Run
	local tuning = Tuning.new(setup and setup.Tuning)
	local events = RunEvents.new()
	local rocks = {}
	local planet = PlanetHealth.new(tuning.Arena.PlanetMaxHp)
	local combo = Combo.new()
	local self = setmetatable({
		Events = events,
		_tuning = tuning,
		_planet = planet,
		_ship = Ship.new(
			setup and setup.ShipStart or tuning.Arena.ShipStart,
			tuning.Ship.FuelMax,
			setup and setup.ShipHeading
		),
		_rocks = rocks,
		_ctx = { tuning = tuning, events = events, rocks = rocks, combo = combo, planet = planet },
		_combo = combo,
		_nextRockId = 1,
		_director = WaveDirector.new(Rng.new(setup and setup.Seed or 1), setup and setup.Waves),
		_score = 0,
		_over = false,
		_pending = 0,
		_boostQueued = false,
	}, Run)
	local startRocks = setup and setup.Rocks
	if startRocks then
		for _, rock in startRocks do
			addRock(self, rock.Type, rock.Position)
		end
	end
	return self
end

-- Advances the run by dt seconds of play, with this frame's input. Once the run is over, does nothing.
function Run.Step(self: Run, input: Input, dt: number)
	if self._over then
		return
	end
	if input.BoostPressed then
		-- kept until a sub-step takes it, so a press on a short frame isn't lost
		self._boostQueued = true
	end
	self._pending += math.clamp(dt, 0, MAX_FRAME)
	while self._pending >= STEP - EPSILON and not self._over do
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
		Wave = self._director.Wave,
		Phase = (if self._over then "Over" else self._director.Phase) :: Phase,
		Score = self._score,
		Combo = self._combo.Count,
		BestCombo = self._combo.Best,
		Multiplier = Combo.Multiplier(self._combo, self._tuning),
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
	self._ctx.tuning = self._tuning
end

function Run.Destroy(self: Run)
	RunEvents.DisconnectAll(self.Events)
	self._planet:Destroy()
end

return Run
