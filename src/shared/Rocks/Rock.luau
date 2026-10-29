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
	    rock.IsPrimed     boolean   pushed by the flame recently; worth more when broken
	    rock.PrimedTime   number    seconds of priming left
	    rock.PushCooldown number    seconds before the flame can push it again
	    rock.IsFlared     boolean   pushed by the orbit flare once (it can't be flared again)
	    rock.HangTime     number    seconds left hanging nearly still after a flare
]]

local RockTypes = require("../Data/RockTypes")
local Tuning = require("../Run/Tuning")

export type Rock = {
	Id: number,
	Type: RockTypes.RockType,
	Position: Vector2,
	Velocity: Vector2,
	FallSpeed: number,
	IsPrimed: boolean,
	PrimedTime: number,
	PushCooldown: number,
	IsFlared: boolean,
	HangTime: number,
}

local SETTLE_RATE = 1 -- how fast a pushed rock's speed toward the planet returns to its fall speed
local SIDE_DAMPING = 0.8 -- how fast sideways drift dies out

local Rock = {}

-- A new rock, already falling. `speedMult` scales its type's fall speed (default 1).
function Rock.new(id: number, rockType: RockTypes.RockType, position: Vector2, speedMult: number?): Rock
	local fallSpeed = rockType.FallSpeed * (speedMult or 1)
	local distance = position.Magnitude
	return {
		Id = id,
		Type = rockType,
		Position = position,
		Velocity = if distance > 1e-6 then -position / distance * fallSpeed else Vector2.zero,
		FallSpeed = fallSpeed,
		IsPrimed = false,
		PrimedTime = 0,
		PushCooldown = 0,
		IsFlared = false,
		HangTime = 0,
	}
end

--[[
	Moves the rock for dt seconds. It falls toward the planet: after a push its
	speed toward the planet eases back to its fall speed and sideways drift dies
	out, so a push carries it a while before it falls again. A flared rock hangs
	nearly still instead until its hang time runs out. Priming wears off.
]]
function Rock.Fall(rock: Rock, tuning: Tuning.Tuning, dt: number)
	local distance = rock.Position.Magnitude
	if rock.HangTime > 0 then
		rock.HangTime = math.max(0, rock.HangTime - dt)
		rock.Velocity *= 1 - math.min(1, tuning.Ship.FlareHangDrag * dt)
	elseif distance > 1e-6 then
		local inward = -rock.Position / distance
		local v = rock.Velocity
		local along = v:Dot(inward)
		v += inward * (rock.FallSpeed - along) * SETTLE_RATE * dt
		local side = v - inward * v:Dot(inward)
		v -= side * SIDE_DAMPING * dt
		rock.Velocity = v
	end
	rock.Position += rock.Velocity * dt

	rock.PushCooldown = math.max(0, rock.PushCooldown - dt)
	if rock.IsPrimed then
		rock.PrimedTime -= dt
		if rock.PrimedTime <= 0 then
			rock.PrimedTime = 0
			rock.IsPrimed = false
		end
	end
end

-- True once the rock's edge has reached the surface of a planet of `planetRadius`.
function Rock.TouchesPlanet(rock: Rock, planetRadius: number): boolean
	return rock.Position.Magnitude <= planetRadius + rock.Type.Radius
end

-- A frozen copy of the rock, safe to hand to code outside the simulation.
function Rock.Snapshot(rock: Rock): Rock
	return table.freeze(table.clone(rock))
end

return table.freeze(Rock)
