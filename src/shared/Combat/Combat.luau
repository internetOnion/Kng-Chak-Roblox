--!strict
--[[
	Combat: what happens when the ship meets a rock, ported from the web prototype.

	- Ram: with the spear out (boosting or slingshotting), a rock touching the front
	  half of the ship (within BreakArcDeg of the nose, or on the spear itself) breaks.
	- Clang: unless the rock's type can't be broken that way yet (its BreaksBy): an
	  unpushed comet, iron that's neither primed nor hit by a slingshot, gold
	  without a PERFECT. Then the spear clangs off: the ship is knocked back and
	  briefly stunned, and the rock is deflected.
	- Bump: a rock touching the back half, or touching the soft nose when the spear
	  is in, knocks the ship away, stuns it for StunTime and loses the combo.
	- Push: the flame behind the ship is the push zone. A rock whose centre is
	  inside its cone and whose near edge is inside its reach is shoved away from
	  the ship and the planet (scaled by its type's PushFactor) and becomes primed
	  for PrimedTime. A pushed comet slows to its slow fall speed for good.
	- Flare: in orbit the flame fans outward instead (FlareRange, FlareConeDeg). A
	  rock it touches is primed, pops up at FlareLift and hangs nearly still for
	  FlareHang, ready for a slingshot. Flaring frees the ship from capture, so the
	  slingshot is there to take. A rock pops up and hangs only the first time, so
	  nothing hovers above the orbit forever; after that the flare just primes it.

	How a rock breaks decides what it's worth (see Data/ComboConfig):

	    primed, then slingshot   Perfect    most combo points, heals the most
	    primed, then rammed      PushBreak  heals; gives fuel back
	    slingshot, not primed    Dive       heals a little
	    plain boosted ram        Ram        scores, never heals

	A golden rock's PERFECT heals HealGold instead. Breaking a primed rock gives
	fuel back, and with the Shockwave upgrade primes every rock near it. A rock
	that takes more than one hit (the Inferno's core) cracks on each but the last:
	it pays out like a break, the ship bounces off, and the rock stays. A break scores the rock's score × its
	combo points × the combo multiplier from before the break. A rock type with a
	Split (the cluster) breaks into that many shards (more in a Bloom wave), which fly apart and can't
	touch the ship for their grace time.

	The Run calls Step once per sub-step, after the ship and rocks have moved.
	It returns the rocks that survived.
]]

local Combo = require("./Combo")
local Context = require("../Run/Context")
local Rock = require("../Rocks/Rock")
local RockTypes = require("../Data/RockTypes")
local Ship = require("../Ship/Ship")

local Combat = {}

-- What a step of combat changed for the Run, beyond the ship, rocks, combo and planet.
export type Result = {
	survivors: { Rock.Rock },
	score: number, -- points earned this step
}

-- A pushed comet slows to its slow fall speed for good.
local function slow(rock: Rock.Rock)
	local slowFall = rock.Type.SlowFallSpeed
	if slowFall then
		rock.FallSpeed = slowFall
		rock.Velocity *= 0.3
	end
end

-- Primes `rock` for the tuning's PrimedTime. The first prime adds combo points for `move`.
local function prime(rock: Rock.Rock, ctx: Context.Context, move: string)
	local tuning = ctx.tuning
	local first = not rock.IsPrimed
	rock.IsPrimed = true
	rock.PrimedTime = tuning.Ship.PrimedTime
	if first then
		ctx.events.RockPrimed:Fire(Rock.Snapshot(rock))
		Combo.Add(ctx.combo, tuning, ctx.events, tuning.Combo.PushPoints, move)
	end
end

local function push(ship: Ship.Ship, rock: Rock.Rock, ctx: Context.Context)
	local flare = ship.IsInOrbit
	if rock.PushCooldown > 0 then
		return
	end
	local tuning, events = ctx.tuning, ctx.events
	local config = tuning.Ship
	rock.PushCooldown = config.PushCooldown
	local outward = rock.Position.Unit
	slow(rock)
	if flare and not rock.IsFlared then -- a later flare only primes it again (below)
		rock.IsFlared = true
		rock.HangTime = config.FlareHang
		rock.Velocity = outward * config.FlareLift
		ship.IsCaptured = false
		ship.OrbitTime = 0
		ship.SlingshotCooldown = 0
		events.RockFlared:Fire(Rock.Snapshot(rock))
	elseif not flare then
		local factor = rock.Type.PushFactor
		rock.Velocity += (ship.FlameDirection * config.PushKick + outward * config.PushLift) * factor
	end
	prime(rock, ctx, if flare then "Flare" else "Push")
end

local function bump(ship: Ship.Ship, rock: Rock.Rock, toRock: Vector2, ctx: Context.Context)
	local config = ctx.tuning.Ship
	local knock = -toRock * config.BumpKnock
	ship.Velocity = knock
	ship.OrbitSpeed *= 0.5 -- in orbit, a bump costs half the orbit speed instead
	ship.StunTime = config.StunTime
	ship.InvulnerableTime = config.StunTime + 0.4
	ship.BoostTime = 0
	ship.SlingshotTime = 0
	ship.IsBoosting = false
	ship.IsSlingshotting = false
	ship.IsSpearOut = false
	ship.IsStunned = true
	rock.Velocity += toRock * 3
	ctx.events.ShipBumped:Fire(Rock.Snapshot(rock), knock)
	Combo.Lose(ctx.combo, ctx.events, "Bump")
end

-- True when the spear can break `rock` right now.
local function canBreak(ship: Ship.Ship, rock: Rock.Rock): boolean
	local rule = rock.Type.BreaksBy
	if rule == "Primed" then
		return rock.IsPrimed
	elseif rule == "PrimedOrDive" then
		return rock.IsPrimed or ship.IsSlingshotting
	elseif rule == "Perfect" then
		return rock.IsPrimed and ship.IsSlingshotting
	end
	return true
end

-- The spear glances off a rock it can't break: knocked back, briefly stunned, the rock deflected.
local function clang(ship: Ship.Ship, rock: Rock.Rock, toRock: Vector2, ctx: Context.Context)
	local config = ctx.tuning.Ship
	local knock = -toRock * config.ClangKnock
	ship.Velocity = knock
	ship.OrbitSpeed *= 0.5
	ship.StunTime = math.max(ship.StunTime, config.ClangStunTime)
	ship.InvulnerableTime = config.ClangStunTime + 0.4
	ship.BoostTime = 0
	ship.SlingshotTime = 0
	ship.IsBoosting = false
	ship.IsSlingshotting = false
	ship.IsSpearOut = false
	ship.IsStunned = true
	rock.Velocity += toRock * 2
	ctx.events.RockClanged:Fire(Rock.Snapshot(rock), knock)
end

-- Splits a broken rock into its shards, added to `into`.
local function split(rock: Rock.Rock, ctx: Context.Context, into: { Rock.Rock })
	local rule = rock.Type.Split
	if not rule then
		return
	end
	local shardType = (RockTypes :: any)[rule.Into] :: RockTypes.RockType
	local outward = rock.Position.Unit
	local base = ctx.rng:Next() * 2 * math.pi
	local shards = {}
	local count = rule.Count + ctx.tuning.Waves.ExtraShards
	for i = 1, count do
		local angle = base + (i - 1) / count * 2 * math.pi
		local velocity = Vector2.new(math.cos(angle), math.sin(angle)) * rule.Speed + outward * rule.Lift
		local shard = ctx.newRock(shardType, rock.Position + velocity * 0.12, rock.SpeedMult, velocity, rule.Grace)
		table.insert(into, shard)
		table.insert(shards, Rock.Snapshot(shard))
	end
	ctx.events.RockSplit:Fire(Rock.Snapshot(rock), table.freeze(shards))
end

-- Primes every rock within the Shockwave upgrade's radius of `broken` (a primed rock that just broke).
local function shockwave(broken: Rock.Rock, ctx: Context.Context)
	local radius = ctx.tuning.Combo.ShockwaveRadius
	if radius <= 0 then
		return
	end
	for _, rock in ctx.rocks do
		if rock ~= broken and not rock.IsPrimed then
			if (rock.Position - broken.Position).Magnitude - rock.Type.Radius <= radius then
				slow(rock)
				prime(rock, ctx, "Shockwave")
			end
		end
	end
end

--[[
	Pays out for the spear getting through to `rock`: score, combo, heal and fuel
	back, by how it was hit. If it was the rock's last hit it breaks (RockBroken);
	a tougher rock (the Inferno's core) only cracks (CoreCracked) and stays.
	Returns the score it earned.
]]
local function payOut(ship: Ship.Ship, rock: Rock.Rock, ctx: Context.Context, breaks: boolean): number
	local tuning, events = ctx.tuning, ctx.events
	local config = tuning.Combo
	local cause, points, heal
	if rock.IsPrimed and ship.IsSlingshotting then
		cause, points, heal = "Perfect", config.PerfectPoints, config.HealPerfect
		if rock.Type == RockTypes.Gold then
			heal = config.HealGold
		end
	elseif rock.IsPrimed then
		cause, points, heal = "PushBreak", config.PushBreakPoints, config.HealPushBreak
	elseif ship.IsSlingshotting then
		cause, points, heal = "Dive", config.DivePoints, config.HealDive
	else
		cause, points, heal = "Ram", config.RamPoints, 0
	end

	local score = rock.Type.Score * points * Combo.Multiplier(ctx.combo, tuning)
	local primed = rock.IsPrimed
	if breaks then
		local broken = Rock.Snapshot(rock)
		events.RockBroken:Fire(broken, cause)
		if cause == "Perfect" then
			events.Perfect:Fire(broken)
		end
	else
		rock.HitsLeft -= 1
		rock.IsPrimed = false
		rock.PrimedTime = 0
		rock.IsFlared = false -- the flare can catch it again for the next one
		rock.HangTime = 0
		local cracked = Rock.Snapshot(rock)
		events.CoreCracked:Fire(cracked, rock.HitsLeft)
		if cause == "Perfect" then
			events.Perfect:Fire(cracked)
		end
	end
	Combo.Add(ctx.combo, tuning, events, points, cause)
	if heal > 0 then
		ctx.planet:Heal(heal)
		events.Healed:Fire(heal, cause)
	end
	if primed then
		local fuelMax = tuning.Ship.FuelMax
		local refund = math.min(config.PushBreakRefuel, fuelMax - ship.Fuel)
		ship.Fuel += refund
		events.FuelRefunded:Fire(refund)
		if breaks then
			shockwave(rock, ctx)
		end
	end
	return score
end

-- A hit that cracks a tough rock without breaking it: the ship bounces off, spear in, but isn't stunned.
local function bounceOff(ship: Ship.Ship, toRock: Vector2, ctx: Context.Context)
	ship.Velocity = -toRock * ctx.tuning.Inferno.CrackKnock
	ship.InvulnerableTime = 0.5
	ship.BoostTime = 0
	ship.SlingshotTime = 0
	ship.IsBoosting = false
	ship.IsSlingshotting = false
	ship.IsSpearOut = false
end

function Combat.Step(ship: Ship.Ship, ctx: Context.Context): Result
	local config = ctx.tuning.Ship
	local facing = ship.Facing
	local flame = ship.FlameDirection
	local hard = ship.IsSpearOut
	local cosBreak = math.cos(math.rad(config.BreakArcDeg))
	local cosCone = math.cos(math.rad(if ship.IsInOrbit then config.FlareConeDeg else config.PushConeDeg))

	local survivors = {}
	local shards = {}
	local score = 0
	for _, rock in ctx.rocks do
		local offset = rock.Position - ship.Position
		local distance = offset.Magnitude
		local along = offset:Dot(facing)
		local lateral = math.abs(offset:Cross(facing))
		local radius = rock.Type.Radius
		local touchesBody = distance < radius + config.HitRadius
		local touchesSpear = hard
			and along > 0
			and along < config.SpearTip + radius * 0.7
			and lateral < radius * 0.8 + config.SpearHalfWidth

		if rock.GraceTime <= 0 and (touchesBody or touchesSpear) then
			local toRock = if distance > 1e-3 then offset / distance else facing
			local front = touchesSpear or distance < 1e-3 or along / distance >= cosBreak
			if hard and front and canBreak(ship, rock) and rock.HitsLeft > 1 then
				score += payOut(ship, rock, ctx, false)
				bounceOff(ship, toRock, ctx)
			elseif hard and front and canBreak(ship, rock) then
				score += payOut(ship, rock, ctx, true)
				split(rock, ctx, shards)
				continue
			elseif hard and front then
				clang(ship, rock, toRock, ctx)
			elseif ship.InvulnerableTime <= 0 then
				bump(ship, rock, toRock, ctx)
			end
		elseif ship.FlameReach > config.NozzleDist and distance > 0.3 and distance - radius < ship.FlameReach then
			if offset:Dot(flame) / distance > cosCone then
				push(ship, rock, ctx)
			end
		end
		table.insert(survivors, rock)
	end
	for _, shard in shards do
		table.insert(survivors, shard)
	end
	return { survivors = survivors, score = score }
end

return table.freeze(Combat)
