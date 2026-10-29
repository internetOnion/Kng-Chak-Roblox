--!strict
--[[
	Rock: one rock's state in the simulation, as plain data.

	The Run owns its rocks and changes them as it steps. Everything else reads
	them through the Run's snapshot (frozen copies) and never sets them. A rock
	has no model: the client's rock view draws one for each rock in the snapshot.
	Positions are arena positions (see Arena/ArenaSpace), with the planet at (0, 0).

	    rock.Id           number    unique within its Run; views track models by it
	    rock.Type         RockType  see Data/RockTypes
	    rock.Position     Vector2   arena position
	    rock.Velocity     Vector2   arena units per second
	    rock.FallSpeed    number    speed toward the planet (its type's, scaled by the wave)
	    rock.SpeedMult    number    the wave's fall speed multiplier it was made with
	    rock.IsPrimed     boolean   pushed by the flame recently; worth more when broken
	    rock.PrimedTime   number    seconds of priming left
	    rock.PushCooldown number    seconds before the flame can push it again
	    rock.IsFlared     boolean   pushed by the orbit flare once (it can't be flared again)
	    rock.HangTime     number    seconds left hanging nearly still after a flare
	    rock.GraceTime    number    seconds left before it can touch the ship (a new shard)
	    rock.HitsLeft     number    breaking hits it still takes (1, except the Inferno's core)
]]

local RockTypes = require("../Data/RockTypes")
local Tuning = require("../Run/Tuning")

export type Rock = {
	Id: number,
	Type: RockTypes.RockType,
	Position: Vector2,
	Velocity: Vector2,
	FallSpeed: number,
	SpeedMult: number,
	IsPrimed: boolean,
	PrimedTime: number,
	PushCooldown: number,
	IsFlared: boolean,
	HangTime: number,
	GraceTime: number,
	HitsLeft: number,
}

local SETTLE_RATE = 1 -- how fast a pushed rock's speed toward the planet returns to its fall speed (outside the drag band)
local SIDE_DAMPING = 0.8 -- how fast sideways drift dies out

local Rock = {}

--[[
	A new rock. `speedMult` scales its type's fall speed (default 1). It starts
	falling straight at the planet unless given a `velocity`; a `grace` time keeps
	it from touching the ship at first.
]]
function Rock.new(
	id: number,
	rockType: RockTypes.RockType,
	position: Vector2,
	speedMult: number?,
	velocity: Vector2?,
	grace: number?
): Rock
	local mult = speedMult or 1
	local fallSpeed = rockType.FallSpeed * mult
	local distance = position.Magnitude
	return {
		Id = id,
		Type = rockType,
		Position = position,
		Velocity = velocity or if distance > 1e-6 then -position / distance * fallSpeed else Vector2.zero,
		FallSpeed = fallSpeed,
		SpeedMult = mult,
		IsPrimed = false,
		PrimedTime = 0,
		PushCooldown = 0,
		IsFlared = false,
		HangTime = 0,
		GraceTime = grace or 0,
		HitsLeft = 1,
	}
end

--[[
	Moves the rock for dt seconds. It falls toward the planet: after a push its
	speed toward the planet eases back to its fall speed and sideways drift dies
	out, so a push carries it a while before it falls again. In the drag band just
	above the orbit track it falls at DragBandMult of its fall speed. A flared rock
	hangs nearly still instead until its hang time runs out. Priming wears off.
	A part of the Inferno doesn't move here: the boss carries it (see Boss/Inferno).
]]
function Rock.Fall(rock: Rock, tuning: Tuning.Tuning, dt: number)
	local distance = rock.Position.Magnitude
	if rock.Type.IsBossPart then
		rock.HangTime = math.max(0, rock.HangTime - dt)
	elseif rock.HangTime > 0 then
		rock.HangTime = math.max(0, rock.HangTime - dt)
		rock.Velocity *= 1 - math.min(1, tuning.Ship.FlareHangDrag * dt)
	elseif distance > 1e-6 then
		local arena = tuning.Arena
		local inBand = distance < arena.PlanetRadius + arena.OrbitAlt + arena.DragBandHeight
		local fall = if inBand then rock.FallSpeed * arena.DragBandMult else rock.FallSpeed
		local settle = if inBand then arena.DragBandSettle else SETTLE_RATE
		local inward = -rock.Position / distance
		local v = rock.Velocity
		local along = v:Dot(inward)
		v += inward * (fall - along) * settle * dt
		local side = v - inward * v:Dot(inward)
		v -= side * SIDE_DAMPING * dt
		rock.Velocity = v
	end
	if not rock.Type.IsBossPart then
		rock.Position += rock.Velocity * dt
	end

	rock.PushCooldown = math.max(0, rock.PushCooldown - dt)
	rock.GraceTime = math.max(0, rock.GraceTime - dt)
	if rock.IsPrimed then
		rock.PrimedTime -= dt
		if rock.PrimedTime <= 0 then
			rock.PrimedTime = 0
			rock.IsPrimed = false
		end
	end
end

-- True once the rock's edge has reached the surface of a planet of `planetRadius`. Never for the Inferno's parts.
function Rock.TouchesPlanet(rock: Rock, planetRadius: number): boolean
	return not rock.Type.IsBossPart and rock.Position.Magnitude <= planetRadius + rock.Type.Radius
end

-- A frozen copy of the rock, safe to hand to code outside the simulation.
function Rock.Snapshot(rock: Rock): Rock
	return table.freeze(table.clone(rock))
end

return table.freeze(Rock)
