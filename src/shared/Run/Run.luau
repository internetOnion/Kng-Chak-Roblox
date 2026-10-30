--!strict
--[[
	Run: one emergency call, as a headless simulation.

	    local run = Run.new({ Seed = 7 })
	    run.Events.PlanetHit:Connect(function(rock, damagePercent) ... end)

	    -- every frame:
	    run:Step(input, dt)
	    local snapshot = run:Snapshot()

	    -- choices that aren't flight input are commands:
	    run:PickUpgrade(2)     -- when snapshot.Phase is "UpgradePick"
	    run:SetPaused(true)

	A call is waves 1 to WaveConfig.LastWave, an upgrade pick after each, then the
	Inferno (see Boss/Inferno). It's won when the Inferno's core cracks and lost
	when planet HP reaches 0; either way RunFinished fires with the run's summary.

	The Run holds the game rules. It knows nothing about Parts, cameras or GUIs and
	creates no Instances: views read its snapshot and events and never change it.
	Step splits the frame's time into fixed sub-steps, so results don't depend on
	the frame rate. Every tuning value comes from the Run's tuning (see Run/Tuning).
]]

local Combat = require("../Combat/Combat")
local Combo = require("../Combat/Combo")
local Context = require("./Context")
local Deck = require("../Upgrades/Deck")
local Flight = require("../Ship/Flight")
local Inferno = require("../Boss/Inferno")
local PlanetHealth = require("../Combat/PlanetHealth")
local Rng = require("../Util/Rng")
local Rock = require("../Rocks/Rock")
local RockTypes = require("../Data/RockTypes")
local RunEvents = require("./RunEvents")
local RunInput = require("./RunInput")
local Ship = require("../Ship/Ship")
local Threat = require("../Rocks/Threat")
local Tuning = require("./Tuning")
local Upgrades = require("../Data/Upgrades")
local WaveDirector = require("../Rocks/WaveDirector")

local STEP = 1 / 60 -- seconds per fixed sub-step
local MAX_FRAME = 0.25 -- a longer frame (a hitch) only advances this much, so nothing teleports
local EPSILON = 1e-9 -- absorbs float error, so 1/30 s always makes exactly two sub-steps
-- Each kind of random choice has its own RNG, seeded apart, so one never changes another's draws.
local COMBAT_SEED_OFFSET = 7919 -- where shards fly, what the Inferno sheds
local UPGRADE_SEED_OFFSET = 104729 -- which cards are offered
local BOSS_SEED_OFFSET = 1299709 -- where the Inferno comes in

export type Input = RunInput.RunInput

export type RockSetup = {
	Type: RockTypes.RockType,
	Position: Vector2,
}

export type WavePlan = WaveDirector.WavePlan

-- "Call": an emergency call (waves, then the Inferno).
export type Mode = "Call"

-- Playing a wave, between waves, picking an upgrade, fighting the Inferno, or finished.
export type Phase = "Playing" | "Breather" | "UpgradePick" | "Boss" | "Won" | "Over"

export type Setup = {
	Seed: number?, -- seeds every random choice the run makes (default 1)
	Mode: Mode?, -- default "Call"
	Waves: { WavePlan }?, -- fixed waves instead of the wave data's; {} plays none
	StartWave: number?, -- with the wave data's waves: start the call at this wave (default 1)
	Boss: boolean?, -- the Inferno comes after the last wave (default: with the data's waves only)
	BossAngle: number?, -- radians: where the Inferno comes in from (default: random)
	Offers: boolean?, -- offer upgrade cards after each wave (default true)
	Upgrades: { [string]: number }?, -- upgrades already picked at the start: id -> stacks
	Rocks: { RockSetup }?, -- rocks already in the arena when the run starts
	ShipStart: Vector2?, -- default: the arena data's ShipStart
	ShipHeading: number?, -- radians; default: nose straight down the screen
	Tuning: Tuning.Overrides?, -- changes to the data's tuning values for this run
}

-- How a call went: what the results screen shows, and what RunFinished carries.
export type Summary = {
	Mode: Mode,
	Won: boolean,
	Wave: number, -- the wave reached (LastWave + 1 once the Inferno came)
	Score: number,
	BestCombo: number,
	Perfects: number,
	Time: number, -- seconds of play
}

-- The Inferno as other code may read it.
export type BossSnapshot = {
	Phase: number, -- 1 armour, 2 burn-off, 3 core
	Position: Vector2,
	Radius: number, -- the body's
	PlatesLeft: number,
	Plates: number,
	CoreHitsLeft: number,
	CoreHits: number,
	IsHolding: boolean,
	TimeToImpact: number, -- seconds, at this phase's speed
}

-- What other code may read. Rebuilt on every Snapshot() call; changing it changes nothing.
export type Snapshot = {
	Mode: Mode,
	Wave: number, -- 0 before the first wave starts
	LastWave: number, -- the last wave before the Inferno (0 with no waves)
	Phase: Phase,
	IsPaused: boolean,
	WaveIntro: string?, -- the rock type id the current (or announced) wave introduces
	WaveModifiers: { string }, -- the current (or announced) wave's modifier ids
	IsSurge: boolean,
	Score: number,
	Combo: number, -- the current chain (0 when there's none)
	BestCombo: number, -- the highest the combo reached this run
	Multiplier: number, -- score multiplier at the current combo
	PlanetHp: number,
	PlanetMaxHp: number,
	PlanetShield: number, -- % on top of HP, soaked before HP
	PlanetMaxShield: number,
	Ship: Ship.Ship,
	FuelMax: number,
	Rocks: { Rock.Rock },
	ThreatId: number?, -- the rock that will hit the planet soonest (see Rocks/Threat), if any
	Offer: { string }?, -- upgrade ids on offer, while Phase is "UpgradePick"
	Upgrades: { [string]: number }, -- upgrades picked so far: id -> stacks
	Boss: BossSnapshot?,
	Time: number, -- seconds of play
}

local Run = {}
Run.__index = Run

Run.IdleInput = RunInput.Idle

export type Run = typeof(setmetatable(
	{} :: {
		Events: RunEvents.RunEvents,
		_mode: Mode,
		_tuning: Tuning.Tuning,
		_overrides: Tuning.Overrides?,
		_upgrades: { [string]: number },
		_modifiers: { string }, -- the modifiers the tuning was last built with
		_tunedWave: number, -- the wave the tuning was last built for
		_planet: PlanetHealth.PlanetHealth,
		_ship: Ship.Ship,
		_rocks: { Rock.Rock },
		_ctx: Context.Context, -- handed to inner modules; its rocks are kept in step with _rocks
		_combo: Combo.Combo,
		_nextRockId: number,
		_director: WaveDirector.WaveDirector,
		_lastWave: number,
		_bossEnabled: boolean,
		_boss: Inferno.Inferno?,
		_bossRng: Rng.Rng,
		_bossAngle: number?,
		_offers: boolean,
		_offerRng: Rng.Rng,
		_offer: { string }?,
		_handledWave: number, -- the last cleared wave whose surge heal and offer are dealt with
		_score: number,
		_perfects: number,
		_time: number,
		_finished: ("Won" | "Over")?,
		_paused: boolean,
		_pending: number, -- frame time not simulated yet, less than one sub-step
		_boostQueued: boolean, -- a boost press waiting for the next sub-step
	},
	Run
))

local NO_MODIFIERS = table.freeze({}) :: { string }

local function newRock(
	self: Run,
	rockType: RockTypes.RockType,
	position: Vector2,
	speedMult: number?,
	velocity: Vector2?,
	grace: number?
): Rock.Rock
	local rock = Rock.new(self._nextRockId, rockType, position, speedMult, velocity, grace)
	self._nextRockId += 1
	return rock
end

local function setRocks(self: Run, rocks: { Rock.Rock })
	self._rocks = rocks
	self._ctx.rocks = rocks
end

local function addRock(self: Run, rock: Rock.Rock)
	table.insert(self._rocks, rock)
end

-- Rebuilds the tuning from the data, the overrides, the current wave's modifiers and the upgrades.
local function retune(self: Run)
	local fuelMax = if self._tuning then self._tuning.Ship.FuelMax else nil
	self._tuning = Tuning.new(self._overrides, { Upgrades = self._upgrades, Modifiers = self._modifiers })
	self._ctx.tuning = self._tuning
	self._planet:SetMaxShield(self._tuning.Arena.PlanetMaxShield)
	local ship = self._ship
	local newMax = self._tuning.Ship.FuelMax
	if fuelMax and newMax > fuelMax then
		ship.Fuel += newMax - fuelMax -- a bigger tank comes full
	end
	ship.Fuel = math.min(ship.Fuel, newMax)
end

local function summary(self: Run): Summary
	local boss = self._boss
	return table.freeze({
		Mode = self._mode,
		Won = self._finished == "Won",
		Wave = if boss then self._lastWave + 1 else self._director.Wave,
		Score = self._score,
		BestCombo = self._combo.Best,
		Perfects = self._perfects,
		Time = self._time,
	})
end

local function finish(self: Run, how: "Won" | "Over")
	if self._finished then
		return
	end
	self._finished = how
	if how == "Over" then
		self.Events.GameOver:Fire(self._director.Wave)
	end
	self.Events.RunFinished:Fire(summary(self))
end

local function damagePlanet(self: Run, amount: number)
	self._planet:TakeDamage(amount)
	Combo.Lose(self._combo, self.Events, "Impact")
	if self._planet:IsDepleted() then
		finish(self, "Over")
	end
end

local function stepRocks(self: Run, dt: number)
	local planetRadius = self._tuning.Arena.PlanetRadius
	local survivors = {}
	for _, rock in self._rocks do
		Rock.Fall(rock, self._tuning, dt)
		if Rock.TouchesPlanet(rock, planetRadius) then
			local damage = rock.Type.DamagePercent
			self.Events.PlanetHit:Fire(Rock.Snapshot(rock), damage)
			damagePlanet(self, damage)
		else
			table.insert(survivors, rock)
		end
	end
	setRocks(self, survivors)
end

local function stepBoss(self: Run, dt: number)
	local boss = self._boss
	if not boss then
		if self._bossEnabled and self._director.Phase == "Done" then
			self._modifiers = NO_MODIFIERS
			retune(self)
			local angle = self._bossAngle or self._bossRng:Next() * 2 * math.pi
			local spawned, plates = Inferno.new(self._ctx, angle)
			self._boss = spawned
			for _, plate in plates do
				addRock(self, plate)
			end
		end
		return
	end
	local result = Inferno.Step(boss, self._ctx, dt)
	for _, rock in result.added do
		addRock(self, rock)
	end
	if result.contactDamage > 0 then
		self.Events.BossHit:Fire(result.contactDamage)
		damagePlanet(self, result.contactDamage)
	end
	if boss.IsDefeated then
		finish(self, "Won")
	end
end

-- After a wave clears: the surge heal, then the upgrade offer (or straight on to the next wave).
local function afterWave(self: Run)
	local director = self._director
	if director.Phase ~= "Cleared" or director.Wave == 0 or self._handledWave == director.Wave then
		return
	end
	self._handledWave = director.Wave
	if WaveDirector.IsSurge(self._tuning, director.Wave) then
		local heal = self._tuning.Waves.SurgeHeal
		self._planet:Heal(heal)
		self.Events.Healed:Fire(heal, "Surge")
	end
	local cards = if self._offers then Deck.Draw(self._offerRng, self._upgrades, Upgrades.OfferSize) else {}
	if #cards > 0 then
		self._offer = cards
		self.Events.UpgradeOffered:Fire(cards)
	end
end

local function directorContext(self: Run): WaveDirector.Context
	return {
		tuning = self._tuning,
		events = self.Events,
		rockCount = #self._rocks,
		shipPosition = self._ship.Position,
		spawn = function(rockType: RockTypes.RockType, position: Vector2, speedMult: number)
			addRock(self, newRock(self, rockType, position, speedMult))
		end,
	}
end

local function tick(self: Run, input: Input, dt: number)
	local boostPressed = self._boostQueued
	self._boostQueued = false
	self._time += dt
	Flight.Step(self._ship, self._ctx, input, boostPressed, dt)
	stepRocks(self, dt)
	if self._finished then
		return
	end
	stepBoss(self, dt)
	if self._finished then
		return
	end
	local combat = Combat.Step(self._ship, self._ctx)
	setRocks(self, combat.survivors)
	self._score += combat.score
	Combo.Step(self._combo, self.Events, #self._rocks > 0, dt)

	local director = self._director
	if director.Phase == "Cleared" and director.Wave > 0 and not self._offer then
		director:Continue(directorContext(self)) -- no upgrade left to offer
	end
	director:Step(dt, directorContext(self))
	if director.Wave ~= self._tunedWave then
		self._tunedWave = director.Wave
		local plan = director.Plan
		self._modifiers = if plan and plan.Modifiers then plan.Modifiers else NO_MODIFIERS
		retune(self)
	end
	afterWave(self)
end

function Run.new(setup: Setup?): Run
	local seed = setup and setup.Seed or 1
	local mode: Mode = setup and setup.Mode or "Call"
	local overrides = setup and setup.Tuning
	local upgrades = table.clone(setup and setup.Upgrades or {})
	local tuning = Tuning.new(overrides, { Upgrades = upgrades })
	local events = RunEvents.new()
	local rocks = {}
	local planet = PlanetHealth.new(tuning.Arena.PlanetMaxHp, tuning.Arena.PlanetMaxShield)
	planet.ShieldChanged:Connect(function(shield: number, delta: number)
		events.ShieldChanged:Fire(shield, delta)
	end)

	-- With the data's waves the call runs to LastWave, from StartWave; fixed waves play as given.
	local fixed = setup and setup.Waves
	local lastWave = if fixed then #fixed else tuning.Waves.LastWave
	local director = WaveDirector.new(Rng.new(seed), fixed, if fixed then nil else lastWave)
	if not fixed and setup and setup.StartWave then
		director.Wave = setup.StartWave - 1
	end
	local bossEnabled = if setup and setup.Boss ~= nil then setup.Boss else fixed == nil

	local combo = Combo.new()
	local self = setmetatable({
		Events = events,
		_mode = mode,
		_tuning = tuning,
		_overrides = overrides,
		_upgrades = upgrades,
		_modifiers = NO_MODIFIERS,
		_tunedWave = director.Wave,
		_planet = planet,
		_ship = Ship.new(
			setup and setup.ShipStart or tuning.Arena.ShipStart,
			tuning.Ship.FuelMax,
			setup and setup.ShipHeading
		),
		_rocks = rocks,
		_ctx = nil :: any, -- set just below: it needs the Run
		_combo = combo,
		_nextRockId = 1,
		_director = director,
		_lastWave = lastWave,
		_bossEnabled = bossEnabled,
		_boss = nil :: Inferno.Inferno?,
		_bossRng = Rng.new(seed + BOSS_SEED_OFFSET),
		_bossAngle = setup and setup.BossAngle,
		_offers = setup == nil or setup.Offers ~= false,
		_offerRng = Rng.new(seed + UPGRADE_SEED_OFFSET),
		_offer = nil :: { string }?,
		_handledWave = director.Wave,
		_score = 0,
		_perfects = 0,
		_time = 0,
		_finished = nil :: ("Won" | "Over")?,
		_paused = false,
		_pending = 0,
		_boostQueued = false,
	}, Run)
	self._ctx = {
		tuning = tuning,
		events = events,
		rocks = rocks,
		combo = combo,
		planet = planet,
		rng = Rng.new(seed + COMBAT_SEED_OFFSET),
		newRock = function(
			rockType: RockTypes.RockType,
			position: Vector2,
			speedMult: number?,
			velocity: Vector2?,
			grace: number?
		): Rock.Rock
			return newRock(self, rockType, position, speedMult, velocity, grace)
		end,
	}
	events.Perfect:Connect(function()
		self._perfects += 1
	end)
	local startRocks = setup and setup.Rocks
	if startRocks then
		for _, rock in startRocks do
			addRock(self, newRock(self, rock.Type, rock.Position))
		end
	end
	return self
end

-- True while nothing moves: paused, picking an upgrade, or finished.
local function frozen(self: Run): boolean
	return self._paused or self._offer ~= nil or self._finished ~= nil
end

-- Advances the run by dt seconds of play, with this frame's input. Does nothing while frozen (see Snapshot).
function Run.Step(self: Run, input: Input, dt: number)
	if frozen(self) then
		return
	end
	if input.BoostPressed then
		-- kept until a sub-step takes it, so a press on a short frame isn't lost
		self._boostQueued = true
	end
	self._pending += math.clamp(dt, 0, MAX_FRAME)
	while self._pending >= STEP - EPSILON and not frozen(self) do
		self._pending = math.max(0, self._pending - STEP)
		tick(self, input, STEP)
	end
end

--[[
	Picks card `index` (1-based) of the upgrade offer, while Phase is "UpgradePick".
	The upgrade applies straight away and the next wave is announced. Returns
	whether there was such a card.
]]
function Run.PickUpgrade(self: Run, index: number): boolean
	local offer = self._offer
	local id = offer and offer[index]
	if not id then
		return false
	end
	self._offer = nil
	self._upgrades[id] = (self._upgrades[id] or 0) + 1
	retune(self)
	self.Events.UpgradePicked:Fire(id, self._upgrades[id])
	self._director:Continue(directorContext(self))
	return true
end

-- Pauses or resumes the run. While paused, Step does nothing, so it resumes exactly where it was.
function Run.SetPaused(self: Run, paused: boolean)
	self._paused = paused
end

-- How the run has gone so far (final once it's finished).
function Run.Summary(self: Run): Summary
	return summary(self)
end

local function phase(self: Run): Phase
	if self._finished then
		return self._finished :: Phase
	elseif self._offer then
		return "UpgradePick"
	elseif self._boss then
		return "Boss"
	elseif self._director.Phase == "Playing" then
		return "Playing"
	end
	return "Breather"
end

local function bossSnapshot(self: Run): BossSnapshot?
	local boss = self._boss
	if not boss then
		return nil
	end
	local config = self._tuning.Inferno
	return table.freeze({
		Phase = boss.Phase,
		Position = boss.Position,
		Radius = config.BodyRadius,
		PlatesLeft = Inferno.PlatesLeft(boss, self._ctx),
		Plates = #boss.PlateIds,
		CoreHitsLeft = boss.CoreHitsLeft,
		CoreHits = config.CoreHits,
		IsHolding = boss.IsHolding,
		TimeToImpact = Inferno.TimeToImpact(boss, self._ctx),
	})
end

function Run.Snapshot(self: Run): Snapshot
	local rocks = table.create(#self._rocks)
	for _, rock in self._rocks do
		table.insert(rocks, Rock.Snapshot(rock))
	end
	local threat = Threat.Soonest(self._rocks, self._tuning.Arena.PlanetRadius)
	local plan = self._director.Plan
	local wave = if plan then plan.Wave else self._director.Wave
	return table.freeze({
		Mode = self._mode,
		Wave = self._director.Wave,
		LastWave = self._lastWave,
		Phase = phase(self),
		IsPaused = self._paused,
		WaveIntro = if plan then plan.Intro else nil,
		WaveModifiers = if plan and plan.Modifiers then plan.Modifiers else NO_MODIFIERS,
		IsSurge = WaveDirector.IsSurge(self._tuning, wave),
		Score = self._score,
		Combo = self._combo.Count,
		BestCombo = self._combo.Best,
		Multiplier = Combo.Multiplier(self._combo, self._tuning),
		PlanetHp = self._planet.Hp,
		PlanetMaxHp = self._planet.MaxHp,
		PlanetShield = self._planet.Shield,
		PlanetMaxShield = self._planet.MaxShield,
		Ship = Ship.Snapshot(self._ship),
		FuelMax = self._tuning.Ship.FuelMax,
		Rocks = table.freeze(rocks),
		ThreatId = if threat then threat.Id else nil,
		Offer = self._offer,
		Upgrades = table.freeze(table.clone(self._upgrades)),
		Boss = bossSnapshot(self),
		Time = self._time,
	})
end

-- The tuning values this run plays with.
function Run.GetTuning(self: Run): Tuning.Tuning
	return self._tuning
end

-- Replaces this run's tuning overrides (Studio tuning panel). The data modules don't change.
function Run.SetTuning(self: Run, overrides: Tuning.Overrides?)
	self._overrides = overrides
	retune(self)
end

function Run.Destroy(self: Run)
	RunEvents.DisconnectAll(self.Events)
	self._planet:Destroy()
end

return Run
