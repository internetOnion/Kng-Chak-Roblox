--!strict
--[[
	ViewMath: where the camera looks and how visible the arena edge is.

	Pure maths shared by the camera and ring views, kept here so it can be tested.
	Takes the arena's tuning values (ArenaConfig, or the Run's tuning of it).
]]

local ArenaConfig = require("../Data/ArenaConfig")

local ViewMath = {}

type Arena = ArenaConfig.ArenaConfig

local function smoothstep(u: number): number
	return u * u * (3 - 2 * u)
end

-- Half the visible size of the play plane in arena units, for a screen of `aspect` (width / height).
-- CamView is the distance from the centre to the nearer screen edge.
function ViewMath.ViewHalf(arena: Arena, aspect: number): Vector2
	if aspect >= 1 then
		return Vector2.new(arena.CamView * aspect, arena.CamView)
	end
	return Vector2.new(arena.CamView, arena.CamView / aspect)
end

--[[
	The arena position the camera centres on. Out in the arena it's the ship; near
	the planet it eases onto the planet, so orbiting doesn't swing the view. It's
	leashed so at least CamPlanetShow of the planet's width stays on screen.
]]
function ViewMath.CameraFocus(arena: Arena, shipPosition: Vector2, viewHalf: Vector2): Vector2
	local near = math.min(arena.CamNear, arena.CamFar - 0.01)
	local u = math.clamp((shipPosition.Magnitude - near) / (arena.CamFar - near), 0, 1)
	local focus = shipPosition * smoothstep(u)
	local keep = 2 * arena.PlanetRadius * arena.CamPlanetShow
	local leashX = math.max(0, viewHalf.X + arena.PlanetRadius - keep)
	local leashY = math.max(0, viewHalf.Y + arena.PlanetRadius - keep)
	return Vector2.new(math.clamp(focus.X, -leashX, leashX), math.clamp(focus.Y, -leashY, leashY))
end

-- How visible the arena edge ring is (0..1): 0 until the ship is within EdgeShowDist of it.
function ViewMath.EdgeVisibility(arena: Arena, shipPosition: Vector2): number
	local gap = arena.ArenaRadius - shipPosition.Magnitude
	return math.clamp(1 - gap / arena.EdgeShowDist, 0, 1)
end

return table.freeze(ViewMath)
