--!strict
--[[
	Combat: what happens when the ship meets a rock, ported from the web prototype.

	- Ram: with the spear out (boosting or slingshotting), a rock touching the front
	  half of the ship (within BreakArcDeg of the nose, or on the spear itself) breaks.
	- Bump: a rock touching the back half, or touching the soft nose when the spear
	  is in, knocks the ship away, stuns it for StunTime and loses the combo.
	- Push: the flame behind the ship is the push zone. A rock inside its cone and
	  reach is shoved away from the ship and the planet (scaled by its type's
	  PushFactor) and becomes primed for PrimedTime.
	- Flare: in orbit the flame fans outward instead (FlareRange, FlareConeDeg). A
	  rock it touches is primed, pops up at FlareLift and hangs nearly still for
	  FlareHang, ready for a slingshot. Flaring frees the ship from capture, so the
	  slingshot is there to take. A rock can only be flared once.

	How a rock breaks decides what it's worth (see Data/ComboConfig):

	    primed, then slingshot   Perfect    most combo points, heals the most
	    primed, then rammed      PushBreak  heals; gives fuel back
	    slingshot, not primed    Dive       heals a little
	    plain boosted ram        Ram        scores, never heals

	Breaking a primed rock gives fuel back. A break scores the rock's score × its
	combo points × the combo multiplier from before the break.

	The Run calls Step once per sub-step, after the ship and rocks have moved.
	It returns the rocks that survived.
]]

local Combo = require("./Combo")
local Context = require("../Run/Context")
local Rock = require("../Rocks/Rock")
local Ship = require("../Ship/Ship")

local Combat = {}

-- What a step of combat changed for the Run, beyond the ship, rocks, combo and planet.
export type Result = {
	survivors: { Rock.Rock },
	score: number, -- points earned this step
}

local function push(ship: Ship.Ship, rock: Rock.Rock, ctx: Context.Context)
	local flare = ship.IsInOrbit
	if rock.PushCooldown > 0 or (flare and rock.IsFlared) then
		return
	end
	local tuning, events = ctx.tuning, ctx.events
	local config = tuning.Ship
	rock.PushCooldown = config.PushCooldown
	local outward = rock.Position.Unit
	if flare then
		rock.IsFlared = true
		rock.HangTime = config.FlareHang
		rock.Velocity = outward * config.FlareLift
		ship.IsCaptured = false
		ship.OrbitTime = 0
		ship.SlingshotCooldown = 0
		events.RockFlared:Fire(Rock.Snapshot(rock))
	else
		local factor = rock.Type.PushFactor
		rock.Velocity += (ship.FlameDirection * config.PushKick + outward * config.PushLift) * factor
	end
	local first = not rock.IsPrimed
	rock.IsPrimed = true
	rock.PrimedTime = config.PrimedTime
	if first then
		events.RockPrimed:Fire(Rock.Snapshot(rock))
		Combo.Add(ctx.combo, tuning, events, tuning.Combo.PushPoints, if flare then "Flare" else "Push")
	end
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

-- Breaks `rock` and pays out for how it broke. Returns the score it earned.
local function breakRock(ship: Ship.Ship, rock: Rock.Rock, ctx: Context.Context): number
	local tuning, events = ctx.tuning, ctx.events
	local config = tuning.Combo
	local cause, points, heal
	if rock.IsPrimed and ship.IsSlingshotting then
		cause, points, heal = "Perfect", config.PerfectPoints, config.HealPerfect
	elseif rock.IsPrimed then
		cause, points, heal = "PushBreak", config.PushBreakPoints, config.HealPushBreak
	elseif ship.IsSlingshotting then
		cause, points, heal = "Dive", config.DivePoints, config.HealDive
	else
		cause, points, heal = "Ram", config.RamPoints, 0
	end

	local score = rock.Type.Score * points * Combo.Multiplier(ctx.combo, tuning)
	local broken = Rock.Snapshot(rock)
	events.RockBroken:Fire(broken, cause)
	if cause == "Perfect" then
		events.Perfect:Fire(broken)
	end
	Combo.Add(ctx.combo, tuning, events, points, cause)
	if heal > 0 then
		ctx.planet:Heal(heal)
		events.Healed:Fire(heal, cause)
	end
	if rock.IsPrimed then
		local fuelMax = tuning.Ship.FuelMax
		local refund = math.min(config.PushBreakRefuel, fuelMax - ship.Fuel)
		ship.Fuel += refund
		events.FuelRefunded:Fire(refund)
	end
	return score
end

function Combat.Step(ship: Ship.Ship, ctx: Context.Context): Result
	local config = ctx.tuning.Ship
	local facing = ship.Facing
	local flame = ship.FlameDirection
	local hard = ship.IsSpearOut
	local cosBreak = math.cos(math.rad(config.BreakArcDeg))
	local cosCone = math.cos(math.rad(if ship.IsInOrbit then config.FlareConeDeg else config.PushConeDeg))

	local survivors = {}
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

		if touchesBody or touchesSpear then
			local toRock = if distance > 1e-3 then offset / distance else facing
			local front = touchesSpear or distance < 1e-3 or along / distance >= cosBreak
			if hard and front then
				score += breakRock(ship, rock, ctx)
				continue
			elseif ship.InvulnerableTime <= 0 then
				bump(ship, rock, toRock, ctx)
			end
		elseif ship.FlameReach > config.NozzleDist and distance > 0.3 and distance < ship.FlameReach then
			if offset:Dot(flame) / distance > cosCone then
				push(ship, rock, ctx)
			end
		end
		table.insert(survivors, rock)
	end
	return { survivors = survivors, score = score }
end

return table.freeze(Combat)
