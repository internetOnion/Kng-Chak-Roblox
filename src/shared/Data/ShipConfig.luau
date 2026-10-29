--!strict
--[[
	ShipConfig: how the Lancer flies, boosts and hits (area 5 owns the values).

	Values come from the web prototype's TUNE table. Game code reads them through
	the Run's tuning (see Run/Tuning) and never writes them: the table is frozen.
	Distances are in arena units, speeds in units per second, angles in degrees.
]]

local ShipConfig = {
	-- Flight
	ThrustAccel = 32, -- acceleration while holding a direction
	MaxSpeed = 22, -- top cruise speed (boost goes past it)
	Drag = 0.45, -- speed bleed while coasting
	Brake = 2.6, -- how hard the brake slows you
	ArriveBrake = 2.5, -- slows you as you near the cursor or ease off the stick
	TurnRate = 5.5, -- radians per second the nose swings toward where you steer
	ThrustConeDeg = 75, -- only thrust once the nose is within this angle of where you steer
	Grip = 1.7, -- how fast momentum follows the nose (lower = more drift)
	RetroBrake = 3.5, -- steering against your motion fires retro thrust to kill it
	OverspeedDecay = 5, -- above max speed (after a boost), the extra bleeds off this fast

	-- Boost and fuel
	FuelMax = 100,
	FuelRegen = 7, -- fuel per second
	BoostCost = 30, -- fuel for one boost burst (a tap)
	BoostDrain = 55, -- fuel per second to keep boosting while held
	BoostSpeed = 46,
	BoostDuration = 0.45, -- seconds of one burst
	BoostTurnRate = 7, -- radians per second the nose turns while boosting
	BoostCarry = 1.3, -- when a boost ends you keep at most this × max speed
	BoostExitTime = 0.35, -- just after a boost, the nose keeps boost turning...
	BoostExitGrip = 4, -- ...and momentum follows it this much harder

	-- Body (the hit zone matches the model: prototype sizes at shipScale 1.3)
	HitRadius = 1.56, -- body hit radius
	SpearTip = 2.6, -- centre to the spear's tip, along the nose
	SpearHalfWidth = 0.33,
	NozzleDist = 1.95, -- centre to the engine nozzle, where the flame starts
	BreakArcDeg = 90, -- with the spear out, rocks within this angle of the nose break; behind it they bump

	-- Bump
	StunTime = 0.6, -- seconds without control after a bump
	BumpKnock = 14, -- speed the ship is knocked away at

	-- Push (the flame is the push zone)
	PushRangeMin = 5, -- flame reach at the lowest throttle...
	PushRange = 10, -- ...at full throttle
	PushBoostRange = 12, -- ...while boosting
	PushConeDeg = 42, -- half-angle of the flame's cone
	PushKick = 5, -- shove away from the ship...
	PushLift = 4, -- ...and away from the planet, both × the rock type's PushFactor
	PushCooldown = 0.5, -- seconds before the same rock can be pushed again
	PrimedTime = 5, -- seconds a pushed rock stays primed
}

export type ShipConfig = typeof(ShipConfig)

return table.freeze(ShipConfig)
