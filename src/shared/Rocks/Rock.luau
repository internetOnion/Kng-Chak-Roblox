--!strict
--[[
	Rock: one rock's state in the simulation, as plain data.

	The Run owns its rocks and changes them as it steps. Everything else reads
	them through the Run's snapshot (frozen copies) and never sets them. A rock
	has no model: the client's rock view draws one for each rock in the snapshot.
	Positions are arena positions (see Arena/ArenaSpace), with the planet at (0, 0).

	    rock.Id        number    unique within its Run; views track models by it
	    rock.Type      RockType  see Data/RockTypes
	    rock.Position  Vector2   arena position
	    rock.Velocity  Vector2   arena units per second
	    rock.FallSpeed number    arena units per second toward the planet (its type's, scaled by the wave)
	    rock.IsPrimed  boolean   pushed by the flame (milestone 1, flame push)
]]

local RockTypes = require("../Data/RockTypes")

export type Rock = {
	Id: number,
	Type: RockTypes.RockType,
	Position: Vector2,
	Velocity: Vector2,
	FallSpeed: number,
	IsPrimed: boolean,
}

local Rock = {}

-- A new rock. `speedMult` scales its type's fall speed (default 1).
function Rock.new(id: number, rockType: RockTypes.RockType, position: Vector2, speedMult: number?): Rock
	return {
		Id = id,
		Type = rockType,
		Position = position,
		Velocity = Vector2.zero,
		FallSpeed = rockType.FallSpeed * (speedMult or 1),
		IsPrimed = false,
	}
end

-- Moves the rock straight toward the planet at its fall speed for dt seconds.
function Rock.Fall(rock: Rock, dt: number)
	local distance = rock.Position.Magnitude
	if distance < 1e-6 then
		rock.Velocity = Vector2.zero
		return
	end
	rock.Velocity = -rock.Position / distance * rock.FallSpeed
	rock.Position += rock.Velocity * dt
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
