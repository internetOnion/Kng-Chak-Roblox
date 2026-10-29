--!strict
--[[
	Combat: what happens when the ship meets a rock, ported from the web prototype.

	- Ram: with the spear out (boosting), a rock touching the front half of the ship
	  (within BreakArcDeg of the nose, or on the spear itself) breaks.
	- Bump: a rock touching the back half, or touching the soft nose when the spear
	  is in, knocks the ship away and stuns it for StunTime.
	- Push: the flame behind the ship is the push zone. A rock inside its cone and
	  reach is shoved away from the ship and the planet (scaled by its type's
	  PushFactor) and becomes primed for PrimedTime.
	- Flare: in orbit the flame fans outward instead (FlareRange, FlareConeDeg). A
	  rock it touches is primed, pops up at FlareLift and hangs nearly still for
	  FlareHang, ready for a slingshot. Flaring frees the ship from capture, so the
	  slingshot is there to take. A rock can only be flared once.

	The Run calls Step once per sub-step, after the ship and rocks have moved.
	It returns the rocks that survived.
]]

local Rock = require("../Rocks/Rock")
local RunEvents = require("../Run/RunEvents")
local Ship = require("../Ship/Ship")
local Tuning = require("../Run/Tuning")

local Combat = {}

-- What a step of combat changed for the Run, beyond the ship and rocks.
export type Result = {
	survivors: { Rock.Rock },
	score: number, -- points earned this step
}

local function push(ship: Ship.Ship, rock: Rock.Rock, tuning: Tuning.Tuning, events: RunEvents.RunEvents)
	local flare = ship.IsInOrbit
	if rock.PushCooldown > 0 or (flare and rock.IsFlared) then
		return
	end
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
	end
end

local function bump(
	ship: Ship.Ship,
	rock: Rock.Rock,
	toRock: Vector2,
	tuning: Tuning.Tuning,
	events: RunEvents.RunEvents
)
	local config = tuning.Ship
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
	events.ShipBumped:Fire(Rock.Snapshot(rock), knock)
end

function Combat.Step(ship: Ship.Ship, rocks: { Rock.Rock }, tuning: Tuning.Tuning, events: RunEvents.RunEvents): Result
	local config = tuning.Ship
	local facing = ship.Facing
	local flame = ship.FlameDirection
	local hard = ship.IsSpearOut
	local cosBreak = math.cos(math.rad(config.BreakArcDeg))
	local cosCone = math.cos(math.rad(if ship.IsInOrbit then config.FlareConeDeg else config.PushConeDeg))

	local survivors = {}
	local score = 0
	for _, rock in rocks do
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
				score += rock.Type.Score
				events.RockBroken:Fire(Rock.Snapshot(rock), if ship.IsSlingshotting then "Dive" else "Ram")
				continue
			elseif ship.InvulnerableTime <= 0 then
				bump(ship, rock, toRock, tuning, events)
			end
		elseif ship.FlameReach > config.NozzleDist and distance > 0.3 and distance < ship.FlameReach then
			if offset:Dot(flame) / distance > cosCone then
				push(ship, rock, tuning, events)
			end
		end
		table.insert(survivors, rock)
	end
	return { survivors = survivors, score = score }
end

return table.freeze(Combat)
