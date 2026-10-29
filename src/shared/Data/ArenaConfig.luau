--!strict
--[[
	ArenaConfig: sizes and camera tuning for the arena (area 5 owns the values).

	Values come from the web prototype's TUNE table. Game code reads them and never
	writes them: the table is frozen, so a write errors straight away.
	Distances are in arena units (1 unit = 1 stud, see Arena/ArenaSpace).
]]

local ArenaConfig = {
	-- Planet
	PlanetRadius = 10,
	PlanetMaxHp = 100, -- HP is a percentage

	-- Orbit band (heights above the planet's surface)
	OrbitBandTop = 4.5, -- flying below this locks you into orbit (milestone 2)
	OrbitAlt = 2.6, -- height of the locked orbit track

	-- Arena edge
	ArenaRadius = 66, -- soft wall around the play area
	EdgeShowDist = 8, -- the edge ring fades in when the ship is this close to it

	-- Ship
	ShipStart = Vector2.new(0, -24), -- where the ship starts each run

	-- Camera
	CamView = 50, -- world units from screen centre to the nearer screen edge (50 vs ~35: decide on a phone)
	CamNear = 15, -- ship closer than this to the planet's centre: camera stays on the planet
	CamFar = 30, -- ship farther than this: camera centres on the ship
	CamPlanetShow = 0.35, -- at least this fraction of the planet's width stays on screen
	CamSettle = 4, -- the camera is locked to its target; this is only how fast it settles after a jump (a restart)
	CamFov = 20, -- degrees, vertical: narrow, so the view is close to flat (there's no orthographic camera)
	CamTilt = 18, -- degrees from straight down, so the toys look solid; top of the screen stays north

	-- World placement
	PlaneHeight = 20, -- world Y of the play plane (clear of the template baseplate)
}

export type ArenaConfig = typeof(ArenaConfig)

return table.freeze(ArenaConfig)
