--!strict
--[[
	WaveDirector: plays the waves of an emergency call, ported from the web prototype.

	Each wave plays from a plan: how many rocks, which types and how likely each
	is, the in-flight cap, the time between groups and the fall speed. Plans come
	from the wave data (PlanFor), or a test hands the Run fixed plans instead.
	Waves 3, 5 and 7 introduce comets, iron and clusters: the new threat comes
	first and the wave's banner carries its tip. From RemixStart to RemixEnd each
	wave gets a modifier (see Data/WaveModifiers), never one the wave before had,
	and a surge wave gets two.

	Rocks arrive in small groups just outside the arena edge, at random angles from
	the Run's seeded RNG, never more than the cap in the air at once. When every
	rock of a wave is gone it fires WaveCleared and waits (phase Cleared) until the
	Run calls Continue, once the player has picked an upgrade. Continue announces
	the next wave (WaveAnnounced, with its intro and modifiers) and, after the
	breather, starts it (WaveStarted). After the last wave, Continue finishes the
	waves (phase Done) and the Run brings on the Inferno.

	The Run owns the director and calls Step once per sub-step.
]]

local Rng = require("../Util/Rng")
local RockTypes = require("../Data/RockTypes")
local RunEvents = require("../Run/RunEvents")
local Tuning = require("../Run/Tuning")
local WaveModifiers = require("../Data/WaveModifiers")

export type MixEntry = {
	Type: RockTypes.RockType,
	Weight: number,
}

export type WavePlan = {
	Wave: number,
	Total: number, -- rocks in the wave
	Mix: { MixEntry }, -- types to draw from, with relative weights
	First: RockTypes.RockType?, -- the wave's first rock (a new threat's intro)
	InFlightCap: number, -- most rocks in the air at once
	FirstGroupDelay: number, -- seconds from the start to the first group
	GroupInterval: number, -- seconds between groups (varied ±20%)
	SpeedMult: number, -- fall speed multiplier
	Intro: string?, -- the rock type id this wave introduces (its tip goes on the banner)
	Modifiers: { string }?, -- modifier ids (see Data/WaveModifiers)
	Gold: number?, -- golden rocks slipped in among the others
	Pincer: boolean?, -- groups land on both sides of the planet at once
}

-- Playing a wave; between waves; a wave just cleared, waiting for the Run; or every wave played.
export type Phase = "Playing" | "Breather" | "Cleared" | "Done"

-- What the director needs from the Run each step.
export type Context = {
	tuning: Tuning.Tuning,
	events: RunEvents.RunEvents,
	rockCount: number,
	shipPosition: Vector2,
	spawn: (rockType: RockTypes.RockType, position: Vector2, speedMult: number) -> (),
}

local WaveDirector = {}
WaveDirector.__index = WaveDirector

export type WaveDirector = typeof(setmetatable(
	{} :: {
		Wave: number,
		Phase: Phase,
		Plan: WavePlan?, -- the wave playing, or the one announced next
		_rng: Rng.Rng,
		_plans: { WavePlan }?, -- fixed plans, or nil to build them from the data
		_lastWave: number?, -- with data plans: the last wave to play
		_toSpawn: number,
		_first: RockTypes.RockType?,
		_gold: number,
		_spawnTimer: number,
		_breatherTimer: number,
	},
	WaveDirector
))

local NO_MODIFIERS = table.freeze({}) :: { string }

-- When each special first appears (its intro wave).
local function introWave(tuning: Tuning.Tuning, rockType: RockTypes.RockType): number
	local config = tuning.Waves
	if rockType == RockTypes.Comet then
		return config.CometFrom
	elseif rockType == RockTypes.Iron then
		return config.IronFrom
	end
	return config.ClusterFrom
end

-- The specials (types other than plain rock) that wave `wave` can draw, with their weights.
local function specials(tuning: Tuning.Tuning, wave: number): { MixEntry }
	local config = tuning.Waves
	local out = {}
	if wave >= config.CometFrom then
		table.insert(out, { Type = RockTypes.Comet, Weight = config.CometWeight })
	end
	if wave >= config.IronFrom then
		table.insert(out, { Type = RockTypes.Iron, Weight = config.IronWeight })
	end
	if wave >= config.ClusterFrom then
		table.insert(out, { Type = RockTypes.Cluster, Weight = config.ClusterWeight })
	end
	return out
end

-- True when wave `wave` is a surge: two modifiers, and surviving it heals.
function WaveDirector.IsSurge(tuning: Tuning.Tuning, wave: number): boolean
	local config = tuning.Waves
	return wave >= config.RemixStart and wave <= config.RemixEnd and wave % config.SurgeEvery == 0
end

-- How many modifiers wave `wave` gets.
function WaveDirector.ModifierCount(tuning: Tuning.Tuning, wave: number): number
	local config = tuning.Waves
	if wave < config.RemixStart or wave > config.RemixEnd then
		return 0
	end
	return if WaveDirector.IsSurge(tuning, wave) then 2 else 1
end

-- Picks wave `wave`'s modifiers with `rng`, leaving out any the wave before had (`last`).
function WaveDirector.PickModifiers(tuning: Tuning.Tuning, rng: Rng.Rng, wave: number, last: { string }): { string }
	local pool = {}
	for _, modifier in WaveModifiers.List do
		if not table.find(last, modifier.Id) then
			table.insert(pool, modifier.Id)
		end
	end
	local out = {}
	for _ = 1, math.min(WaveDirector.ModifierCount(tuning, wave), #pool) do
		local index = math.clamp(math.floor(rng:Next() * #pool) + 1, 1, #pool)
		table.insert(out, table.remove(pool, index) :: string)
	end
	return table.freeze(out)
end

-- The plan for wave `wave`, built from the wave data in `tuning`, with `modifiers` (ids) applied.
function WaveDirector.PlanFor(tuning: Tuning.Tuning, wave: number, modifiers: { string }?): WavePlan
	local config = tuning.Waves
	local mods = modifiers or NO_MODIFIERS
	local plain = math.clamp(1 - (wave - 1) * config.PlainShareDrop, config.PlainShareMin, 1)
	local extra = specials(tuning, wave)
	local gold, pincer = 0, false
	for _, id in mods do
		local modifier = WaveModifiers.ById[id]
		if modifier.PlainShare then
			plain *= modifier.PlainShare
		end
		local weights = modifier.Weights
		if weights then
			for _, entry in extra do
				entry.Weight *= weights[entry.Type.Id] or 1
			end
		end
		gold += modifier.Gold or 0
		pincer = pincer or modifier.Pincer == true
	end

	local mix: { MixEntry }
	if #extra == 0 then
		mix = { { Type = RockTypes.Rock, Weight = 1 } }
	else
		local total = 0
		for _, entry in extra do
			total += entry.Weight
		end
		mix = { { Type = RockTypes.Rock, Weight = plain } }
		for _, entry in extra do
			table.insert(mix, { Type = entry.Type, Weight = (1 - plain) * entry.Weight / total })
		end
	end

	-- A wave that introduces a threat sends it first
	local first: RockTypes.RockType? = RockTypes.Rock
	local intro: string? = if wave == 1 then RockTypes.Rock.Id else nil
	for _, entry in extra do
		if introWave(tuning, entry.Type) == wave then
			first = entry.Type
			intro = entry.Type.Id
		end
	end

	return {
		Wave = wave,
		Total = config.WaveBase + wave * config.WavePerLevel,
		Mix = mix,
		First = first,
		InFlightCap = math.min(config.InFlightMax, config.InFlightStart + math.floor((wave - 1) / 2)),
		FirstGroupDelay = config.FirstGroupDelay,
		GroupInterval = math.max(config.GroupIntervalMin, config.GroupInterval - wave * config.GroupIntervalDrop),
		SpeedMult = math.min(config.SpeedMaxMult, 1 + math.max(0, wave - 1) * config.SpeedPerWave),
		Intro = intro,
		Modifiers = mods,
		Gold = gold,
		Pincer = pincer,
	}
end

--[[
	A director about to announce wave 1. `plans` replaces the data's waves (an empty
	list plays none); with the data's waves, it plays up to `lastWave`.
]]
function WaveDirector.new(rng: Rng.Rng, plans: { WavePlan }?, lastWave: number?): WaveDirector
	return setmetatable({
		Wave = 0,
		Phase = "Cleared" :: Phase, -- wave "0" is cleared: the first step announces wave 1
		Plan = nil :: WavePlan?,
		_rng = rng,
		_plans = plans,
		_lastWave = lastWave,
		_toSpawn = 0,
		_first = nil,
		_gold = 0,
		_spawnTimer = 0,
		_breatherTimer = 0,
	}, WaveDirector)
end

-- The plan for the wave after the current one, or nil when there's none.
local function nextPlan(self: WaveDirector, tuning: Tuning.Tuning): WavePlan?
	local wave = self.Wave + 1
	local plans = self._plans
	if plans then
		return plans[wave]
	end
	if self._lastWave and wave > self._lastWave then
		return nil
	end
	local last = if self.Plan and self.Plan.Modifiers then self.Plan.Modifiers else NO_MODIFIERS
	return WaveDirector.PlanFor(tuning, wave, WaveDirector.PickModifiers(tuning, self._rng, wave, last))
end

--[[
	After a cleared wave: announces the next one, which starts after `breather` seconds
	(default: the data's breather), or finishes the waves when there's no next one.
]]
function WaveDirector.Continue(self: WaveDirector, ctx: Context, breather: number?)
	assert(self.Phase == "Cleared", "a wave was cleared")
	local plan = nextPlan(self, ctx.tuning)
	if not plan then
		self.Phase = "Done"
		return
	end
	self.Plan = plan
	self.Phase = "Breather"
	self._breatherTimer = breather or ctx.tuning.Waves.Breather
	ctx.events.WaveAnnounced:Fire(plan.Wave, plan.Intro, plan.Modifiers or NO_MODIFIERS)
end

local function startWave(self: WaveDirector, ctx: Context)
	local plan = self.Plan
	assert(plan, "a wave was announced")
	self.Wave = plan.Wave
	self.Phase = "Playing"
	self._toSpawn = plan.Total
	self._first = plan.First
	self._gold = plan.Gold or 0
	self._spawnTimer = plan.FirstGroupDelay
	ctx.events.WaveStarted:Fire(plan.Wave)
end

-- The type of the next rock to spawn, `left` rocks before the wave's last.
local function pickType(self: WaveDirector, plan: WavePlan, left: number, ctx: Context): RockTypes.RockType
	local first = self._first
	if first then
		self._first = nil
		return first
	end
	if self._gold > 0 and (left <= 2 or self._rng:Chance(ctx.tuning.Waves.GoldChance)) then
		self._gold -= 1
		return RockTypes.Gold
	end
	local total = 0
	for _, entry in plan.Mix do
		total += entry.Weight
	end
	local roll = self._rng:Next() * total
	for _, entry in plan.Mix do
		roll -= entry.Weight
		if roll <= 0 then
			return entry.Type
		end
	end
	return plan.Mix[#plan.Mix].Type
end

local function spawnGroup(self: WaveDirector, plan: WavePlan, room: number, ctx: Context)
	local config = ctx.tuning.Waves
	local rng = self._rng
	local size = 1 + (if rng:Chance(0.65) then 1 else 0) + (if plan.Wave >= 3 and rng:Chance(0.45) then 1 else 0)
	if plan.Pincer then
		size = math.max(2, size)
	end
	local count = math.min(self._toSpawn, room, size)

	local centre = rng:Next() * 2 * math.pi
	local shipAngle = math.atan2(ctx.shipPosition.Y, ctx.shipPosition.X)
	local fromShip = (centre - shipAngle + math.pi) % (2 * math.pi) - math.pi
	if math.abs(fromShip) < 0.35 then
		centre += math.pi -- not right on top of the ship
	end
	local spread = math.rad(config.GroupSpreadDeg)
	local arena = ctx.tuning.Arena
	for i = 1, count do
		local angle
		if plan.Pincer then
			-- alternate rocks land on the far side of the planet
			local pair = math.floor((i - 1) / 2) - (math.ceil(count / 2) - 1) / 2
			angle = centre + ((i - 1) % 2) * math.pi + pair * spread + rng:Range(-0.05, 0.05)
		else
			angle = centre + (i - 1 - (count - 1) / 2) * spread + rng:Range(-0.05, 0.05)
		end
		local radius = arena.ArenaRadius + config.SpawnBeyondEdge + rng:Range(0, config.SpawnDepth)
		local rockType = pickType(self, plan, self._toSpawn - i + 1, ctx)
		ctx.spawn(rockType, Vector2.new(math.cos(angle), math.sin(angle)) * radius, plan.SpeedMult)
	end
	self._toSpawn -= count
	self._spawnTimer = plan.GroupInterval * rng:Range(0.8, 1.2)
end

function WaveDirector.Step(self: WaveDirector, dt: number, ctx: Context)
	if self.Phase == "Cleared" and self.Wave == 0 then
		self:Continue(ctx, 0) -- the call opens straight onto wave 1
	end
	if self.Phase == "Breather" then
		self._breatherTimer -= dt
		if self._breatherTimer <= 0 then
			startWave(self, ctx)
		end
		return
	elseif self.Phase ~= "Playing" then
		return
	end

	local plan = self.Plan
	assert(plan, "a wave is playing")
	if self._toSpawn > 0 then
		self._spawnTimer -= dt
		if self._spawnTimer <= 0 then
			local room = plan.InFlightCap - ctx.rockCount
			if room <= 0 then
				self._spawnTimer = ctx.tuning.Waves.FullWaitRetry
			else
				spawnGroup(self, plan, room, ctx)
			end
		end
	elseif ctx.rockCount == 0 then
		self.Phase = "Cleared"
		ctx.events.WaveCleared:Fire(self.Wave)
	end
end

return WaveDirector
