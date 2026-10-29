--!strict
--[[
	WaveDirector: plays waves of rocks, ported from the web prototype.

	Each wave plays from a plan: how many rocks, which types and how likely each
	is, the in-flight cap, the time between groups and the fall speed. Plans come
	from the wave data (PlanFor), or a test hands the Run fixed plans instead.
	Rocks arrive in small groups just outside the arena edge, at random angles from
	the Run's seeded RNG, never more than the cap in the air at once. When every
	rock of a wave is gone, it fires WaveCleared, waits out the breather and starts
	the next wave (with fixed plans, it stops after the last one).

	The Run owns the director and calls Step once per sub-step.
]]

local Rng = require("../Util/Rng")
local RockTypes = require("../Data/RockTypes")
local RunEvents = require("../Run/RunEvents")
local Tuning = require("../Run/Tuning")

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
}

export type Phase = "Playing" | "Breather"

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
		_rng: Rng.Rng,
		_plans: { WavePlan }?, -- fixed plans, or nil to build them from the data
		_plan: WavePlan?,
		_toSpawn: number,
		_first: RockTypes.RockType?,
		_spawnTimer: number,
		_breatherTimer: number,
	},
	WaveDirector
))

-- The specials (types other than plain rock) that wave `wave` can draw, with their weights.
local function specials(waves: Tuning.Tuning, wave: number): { MixEntry }
	local config = waves.Waves
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

-- The plan for wave `wave`, built from the wave data in `tuning`.
function WaveDirector.PlanFor(tuning: Tuning.Tuning, wave: number): WavePlan
	local config = tuning.Waves
	local plain = math.clamp(1 - (wave - 1) * config.PlainShareDrop, config.PlainShareMin, 1)
	local extra = specials(tuning, wave)
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
	for _, entry in extra do
		local from = if entry.Type == RockTypes.Comet
			then config.CometFrom
			elseif entry.Type == RockTypes.Iron then config.IronFrom
			else config.ClusterFrom
		if from == wave then
			first = entry.Type
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
	}
end

-- A director about to start wave 1. `plans` replaces the data's waves (an empty list plays none).
function WaveDirector.new(rng: Rng.Rng, plans: { WavePlan }?): WaveDirector
	return setmetatable({
		Wave = 0,
		Phase = "Breather" :: Phase,
		_rng = rng,
		_plans = plans,
		_plan = nil,
		_toSpawn = 0,
		_first = nil,
		_spawnTimer = 0,
		_breatherTimer = 0,
	}, WaveDirector)
end

local function startWave(self: WaveDirector, ctx: Context): boolean
	local wave = self.Wave + 1
	local plan: WavePlan
	local plans = self._plans
	if plans then
		local fixed = plans[wave]
		if not fixed then
			return false
		end
		plan = fixed
	else
		plan = WaveDirector.PlanFor(ctx.tuning, wave)
	end
	self.Wave = wave
	self.Phase = "Playing"
	self._plan = plan
	self._toSpawn = plan.Total
	self._first = plan.First
	self._spawnTimer = plan.FirstGroupDelay
	ctx.events.WaveStarted:Fire(wave)
	return true
end

local function pickType(self: WaveDirector, plan: WavePlan): RockTypes.RockType
	local first = self._first
	if first then
		self._first = nil
		return first
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
		local angle = centre + (i - 1 - (count - 1) / 2) * spread + rng:Range(-0.05, 0.05)
		local radius = arena.ArenaRadius + config.SpawnBeyondEdge + rng:Range(0, config.SpawnDepth)
		ctx.spawn(pickType(self, plan), Vector2.new(math.cos(angle), math.sin(angle)) * radius, plan.SpeedMult)
	end
	self._toSpawn -= count
	self._spawnTimer = plan.GroupInterval * rng:Range(0.8, 1.2)
end

function WaveDirector.Step(self: WaveDirector, dt: number, ctx: Context)
	if self.Phase == "Breather" then
		self._breatherTimer -= dt
		if self._breatherTimer <= 0 then
			startWave(self, ctx)
		end
		return
	end

	local plan = self._plan
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
		self.Phase = "Breather"
		self._breatherTimer = ctx.tuning.Waves.Breather
		ctx.events.WaveCleared:Fire(self.Wave)
	end
end

return WaveDirector
