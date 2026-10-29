--!strict
--[[
	InfernoConfig: the boss at the end of an emergency call.

	Values come from the design pitch's Inferno tuning table. Game code reads them
	through the Run's tuning (see Run/Tuning) and never writes them: the table is frozen.
	Distances are in arena units, times in seconds.
]]

local InfernoConfig = {
	-- Body
	BodyRadius = 5, -- the burning meteor; it touches the planet when its centre is this far above the surface
	EnterDistance = 58, -- enters this far from the planet's centre (just inside the arena edge), and bounces back here
	Spin = 0.25, -- radians per second the plates turn round the body

	-- Phase 1: armour
	Plates = 6,
	PlateRing = 4.6, -- plates sit this far from the body's centre

	-- Descent: seconds it takes to come from EnterDistance to the planet, if ignored, in each phase
	Phase1Time = 90,
	Phase2Time = 60,
	Phase3Time = 40,

	-- Phase 2: burn-off (starts once half the plates are gone)
	ShedInterval = 4, -- sheds a comet or a cluster this often...
	ShedClusterChance = 0.4, -- ...a cluster this often, a comet otherwise
	ShedSpeedMult = 1.2, -- shed rocks fall at this multiple of their type's fall speed

	-- Phase 3: core
	CoreHits = 3, -- PERFECTs it takes to crack the core
	CrackKnock = 14, -- a PERFECT that doesn't finish the core knocks the ship back this fast

	-- Contact
	ContactDamage = 40, -- % the planet takes when the Inferno reaches it (then it bounces back; broken plates stay broken)
}

export type InfernoConfig = typeof(InfernoConfig)

return table.freeze(InfernoConfig)
