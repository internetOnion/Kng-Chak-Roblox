--!strict
--[[
	Ship: the Lancer's state in the simulation, as plain data.

	The Run owns the ship and changes it as it steps (see Ship/Flight). Everything
	else reads it through the Run's snapshot (a frozen copy) and never sets it.

	    ship.Position    Vector2  arena position
	    ship.Velocity    Vector2  arena units per second
	    ship.Facing      Vector2  unit vector the nose points along
	    ship.Throttle    number   0..1, how hard the engine pushes (sets the flame's reach)
	    ship.IsBoosting  boolean
	    ship.IsSpearOut  boolean  the nose is a spear (the only state that breaks rocks)
	    ship.Fuel        number   0..ShipConfig.FuelMax
	    ship.IsStunned   boolean  after a bad bump: no control, grey flame
]]

export type Ship = {
	Position: Vector2,
	Velocity: Vector2,
	Facing: Vector2,
	Heading: number, -- radians, the angle of Facing
	Throttle: number,
	IsThrusting: boolean,
	IsBoosting: boolean,
	IsSpearOut: boolean,
	IsStunned: boolean,
	Fuel: number,
	BoostTime: number, -- seconds of boost left
	ExitTime: number, -- seconds left of the boost's exit (sharper turning and grip)
	StunTime: number, -- seconds of stun left
	InvulnerableTime: number, -- seconds left in which rocks can't bump the ship again
}

local Ship = {}

-- A ship at rest at `position`, nose pointing along `heading` (radians, default straight down).
function Ship.new(position: Vector2, fuel: number, heading: number?): Ship
	local angle = heading or -math.pi / 2
	return {
		Position = position,
		Velocity = Vector2.zero,
		Facing = Vector2.new(math.cos(angle), math.sin(angle)),
		Heading = angle,
		Throttle = 0,
		IsThrusting = false,
		IsBoosting = false,
		IsSpearOut = false,
		IsStunned = false,
		Fuel = fuel,
		BoostTime = 0,
		ExitTime = 0,
		StunTime = 0,
		InvulnerableTime = 0,
	}
end

-- A frozen copy of the ship, safe to hand to code outside the simulation.
function Ship.Snapshot(ship: Ship): Ship
	return table.freeze(table.clone(ship))
end

return table.freeze(Ship)
