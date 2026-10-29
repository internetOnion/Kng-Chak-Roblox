--!strict
--[[
	Inferno: the boss that ends an emergency call, a giant burning meteor.

	It has no AI: it drifts straight at the planet, and its descent is the
	countdown. It's fought with the rock and combat rules the player already
	knows, because its armour plates and its core are rocks (types Plate and Core)
	that ride on it instead of falling on their own.

	1. Armour: it enters at EnterDistance with Plates plates round its body. A plate
	   breaks only once primed (push it, then ram it).
	2. Burn-off: once half the plates are gone it sheds a comet or a cluster at the
	   planet every ShedInterval seconds while the last plates are finished.
	3. Core: with every plate gone the iron core is exposed. Only a PERFECT gets
	   through to it, and it takes CoreHits of them. The orbit flare makes a part
	   hang, and while any part hangs the whole Inferno holds still.

	Each phase it comes in faster: it would cover the distance from EnterDistance
	to the planet in Phase1Time, Phase2Time, Phase3Time seconds. If its body
	reaches the planet, the planet takes ContactDamage and the Inferno bounces back
	to EnterDistance, in the same phase: broken plates stay broken.

	The Run owns it and calls Step once per sub-step, after the rocks have fallen
	and before combat, and does what the result says.
]]

local Context = require("../Run/Context")
local Rock = require("../Rocks/Rock")
local RockTypes = require("../Data/RockTypes")

export type Inferno = {
	Phase: number, -- 1 armour, 2 burn-off, 3 core
	Angle: number, -- radians: the direction it comes in from, seen from the planet
	Distance: number, -- its centre's distance from the planet's centre
	Position: Vector2,
	Velocity: Vector2,
	IsHolding: boolean, -- a part is hanging after a flare, so it holds still
	PlateIds: { number }, -- every plate it started with, in order round the body
	CoreId: number?, -- the core, once exposed
	CoreHitsLeft: number,
	Spin: number, -- radians the plates have turned
	ShedTimer: number,
	IsDefeated: boolean, -- the core cracked: the call is won
}

-- What one step of the Inferno asks of the Run.
export type Result = {
	added: { Rock.Rock }, -- new rocks: shed rocks and the core
	contactDamage: number, -- > 0 when it reached the planet this step
}

local Inferno = {}

local function phaseTime(ctx: Context.Context, phase: number): number
	local config = ctx.tuning.Inferno
	return if phase == 1 then config.Phase1Time elseif phase == 2 then config.Phase2Time else config.Phase3Time
end

-- How far its centre gets from the planet's centre before the body touches the planet.
local function contactDistance(ctx: Context.Context): number
	return ctx.tuning.Arena.PlanetRadius + ctx.tuning.Inferno.BodyRadius
end

local function inward(boss: Inferno): Vector2
	return -Vector2.new(math.cos(boss.Angle), math.sin(boss.Angle))
end

-- The Inferno entering along `angle` (radians), and its plates (rocks to add to the arena).
function Inferno.new(ctx: Context.Context, angle: number): (Inferno, { Rock.Rock })
	local config = ctx.tuning.Inferno
	local position = Vector2.new(math.cos(angle), math.sin(angle)) * config.EnterDistance
	local boss: Inferno = {
		Phase = 1,
		Angle = angle,
		Distance = config.EnterDistance,
		Position = position,
		Velocity = Vector2.zero,
		IsHolding = false,
		PlateIds = {},
		CoreId = nil,
		CoreHitsLeft = config.CoreHits,
		Spin = 0,
		ShedTimer = config.ShedInterval,
		IsDefeated = false,
	}
	local plates = {}
	for _ = 1, config.Plates do
		local plate = ctx.newRock(RockTypes.Plate, position, 1, Vector2.zero)
		table.insert(boss.PlateIds, plate.Id)
		table.insert(plates, plate)
	end
	Inferno.Place(boss, ctx)
	ctx.events.BossPhaseChanged:Fire(1)
	return boss, plates
end

-- The rocks of `boss` still in the arena: its plates (by slot) and its core.
local function parts(boss: Inferno, ctx: Context.Context): ({ [number]: Rock.Rock }, Rock.Rock?)
	local plates = {}
	local core = nil
	for _, rock in ctx.rocks do
		local slot = table.find(boss.PlateIds, rock.Id)
		if slot then
			plates[slot] = rock
		elseif rock.Id == boss.CoreId then
			core = rock
		end
	end
	return plates, core
end

-- Moves the plates and core to where the body is now.
function Inferno.Place(boss: Inferno, ctx: Context.Context)
	local config = ctx.tuning.Inferno
	local plates, core = parts(boss, ctx)
	local count = #boss.PlateIds
	for slot, plate in plates do
		local angle = boss.Spin + (slot - 1) / count * 2 * math.pi
		plate.Position = boss.Position + Vector2.new(math.cos(angle), math.sin(angle)) * config.PlateRing
		plate.Velocity = boss.Velocity
	end
	if core then
		core.Position = boss.Position
		core.Velocity = boss.Velocity
	end
end

-- How many of its plates are still on.
function Inferno.PlatesLeft(boss: Inferno, ctx: Context.Context): number
	local plates = parts(boss, ctx)
	local count = 0
	for _ in plates do
		count += 1
	end
	return count
end

local function setPhase(boss: Inferno, ctx: Context.Context, phase: number)
	boss.Phase = phase
	ctx.events.BossPhaseChanged:Fire(phase)
end

local function shed(boss: Inferno, ctx: Context.Context): Rock.Rock
	local config = ctx.tuning.Inferno
	local rockType = if ctx.rng:Chance(config.ShedClusterChance) then RockTypes.Cluster else RockTypes.Comet
	local spot = boss.Position + inward(boss) * (config.BodyRadius + rockType.Radius + 0.5)
	-- fanned a little either side, so they don't all land on one spot
	local side = Vector2.new(-inward(boss).Y, inward(boss).X) * ctx.rng:Range(-3, 3)
	return ctx.newRock(rockType, spot + side, config.ShedSpeedMult)
end

function Inferno.Step(boss: Inferno, ctx: Context.Context, dt: number): Result
	local config = ctx.tuning.Inferno
	local result: Result = { added = {}, contactDamage = 0 }
	if boss.IsDefeated then
		return result
	end
	local plates, core = parts(boss, ctx)

	-- The core went: the call is won
	if boss.CoreId and not core then
		boss.IsDefeated = true
		boss.CoreHitsLeft = 0
		return result
	end
	if core then
		boss.CoreHitsLeft = core.HitsLeft
	end

	-- Phases follow the plates
	local left = 0
	for _ in plates do
		left += 1
	end
	if boss.Phase == 1 and left <= math.floor(#boss.PlateIds / 2) then
		setPhase(boss, ctx, 2)
		boss.ShedTimer = config.ShedInterval
	end
	if boss.Phase == 2 and left == 0 then
		setPhase(boss, ctx, 3)
		local newCore = ctx.newRock(RockTypes.Core, boss.Position, 1, Vector2.zero)
		newCore.HitsLeft = boss.CoreHitsLeft
		boss.CoreId = newCore.Id
		table.insert(result.added, newCore)
	end
	if boss.Phase == 2 then
		boss.ShedTimer -= dt
		if boss.ShedTimer <= 0 then
			boss.ShedTimer += config.ShedInterval
			table.insert(result.added, shed(boss, ctx))
		end
	end

	-- Descend, unless a flared part holds it
	local holding = false
	for _, plate in plates do
		holding = holding or plate.HangTime > 0
	end
	holding = holding or (core ~= nil and core.HangTime > 0)
	boss.IsHolding = holding
	local contact = contactDistance(ctx)
	local speed = if holding then 0 else (config.EnterDistance - contact) / phaseTime(ctx, boss.Phase)
	boss.Distance -= speed * dt
	boss.Velocity = inward(boss) * speed
	if boss.Distance <= contact then
		result.contactDamage = config.ContactDamage
		boss.Distance = config.EnterDistance
	end
	boss.Position = -inward(boss) * boss.Distance
	boss.Spin += config.Spin * dt
	Inferno.Place(boss, ctx)
	return result
end

-- Seconds until it reaches the planet at this phase's speed, if nothing holds it.
function Inferno.TimeToImpact(boss: Inferno, ctx: Context.Context): number
	local config = ctx.tuning.Inferno
	local speed = (config.EnterDistance - contactDistance(ctx)) / phaseTime(ctx, boss.Phase)
	return math.max(0, boss.Distance - contactDistance(ctx)) / speed
end

return table.freeze(Inferno)
