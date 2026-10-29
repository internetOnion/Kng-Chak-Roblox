--!strict
--[[
	GuidedConfig: the guided first call, which teaches one move per step.

	Values from the design pitch's mobile onboarding. The planet can't be damaged
	during it; it starts a little hurt so the push-then-break heal shows. Game code
	reads these and never writes them: the tables are frozen.
	Positions are arena positions (the planet at the centre, the ship starting at ArenaConfig.ShipStart).
]]

local GuidedConfig = {
	StartHp = 85, -- planet HP % the guided call starts at

	-- The steps, in order
	Steps = table.freeze({ "Move", "Boost", "PushBreak", "Slingshot" }),

	-- 1. Move: fly through the beacon
	BeaconAt = Vector2.new(22, -34),
	BeaconRadius = 4,

	-- 2-4. Dummy rocks: plain rocks that fall very slowly; one waits at each step's spot
	DummySpeed = 0.15, -- × a plain rock's fall speed
	BoostRockAt = Vector2.new(22, -48), -- 2. Boost: ram it
	PushRockAt = Vector2.new(-6, -40), -- 3. Push then break: prime it with the flame, then ram it
	DiveRockAt = Vector2.new(0, -24), -- 4. Orbit and slingshot: lock onto the orbit, then dive out at it
}

export type GuidedConfig = typeof(GuidedConfig)

return table.freeze(GuidedConfig)
