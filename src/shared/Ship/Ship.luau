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
	    ship.FlameReach  number   how far the flame (the push zone) reaches from the ship's centre
	    ship.IsInOrbit   boolean  locked onto the orbit track (it can't touch the planet)
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
	FlameReach: number,
	BoostTime: number, -- seconds of boost left
	ExitTime: number, -- seconds left of the boost's exit (sharper turning and grip)
	StunTime: number, -- seconds of stun left
	InvulnerableTime: number, -- seconds left in which rocks can't bump the ship again
	IsInOrbit: boolean,
	OrbitDir: number, -- 1 = anticlockwise round the planet, -1 = clockwise
	OrbitSpeed: number, -- speed along the orbit track
	OrbitTime: number, -- seconds since locking on
	OrbitRelock: number, -- seconds left before the band can lock the ship again
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
		FlameReach = 0,
		BoostTime = 0,
		ExitTime = 0,
		StunTime = 0,
		InvulnerableTime = 0,
		IsInOrbit = false,
		OrbitDir = 1,
		OrbitSpeed = 0,
		OrbitTime = 0,
		OrbitRelock = 0,
	}
end

-- A frozen copy of the ship, safe to hand to code outside the simulation.
function Ship.Snapshot(ship: Ship): Ship
	return table.freeze(table.clone(ship))
end

return table.freeze(Ship)
