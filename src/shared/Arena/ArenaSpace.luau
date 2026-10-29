--!strict
--[[
	ArenaSpace: converts between arena positions and the 3D world (area 1).

	The game is 2D, like the prototype. Game code works in arena positions: Vector2
	in arena units, planet at (0, 0), +x to the right and +y up the screen. The
	world plays it on a flat plane at ArenaConfig.PlaneHeight, seen from above:

	    arena +x  ->  world +X
	    arena +y  ->  world -Z   (the camera looks down with -Z at the top of the screen)

	1 arena unit = 1 stud. Only this module knows the mapping, so keep world maths here.
]]

local ArenaConfig = require("../Data/ArenaConfig")

local ArenaSpace = {}

-- World position of an arena position. `lift` raises it off the plane (default 0).
function ArenaSpace.ToWorld(position: Vector2, lift: number?): Vector3
	return Vector3.new(position.X, ArenaConfig.PlaneHeight + (lift or 0), -position.Y)
end

-- Arena position of a world position (its height is dropped).
function ArenaSpace.ToArena(world: Vector3): Vector2
	return Vector2.new(world.X, -world.Z)
end

-- Arena position where a ray (say, from the camera through a screen point) meets the
-- plane raised by `lift`, or nil if it runs parallel to the plane or away from it.
function ArenaSpace.RayHit(origin: Vector3, direction: Vector3, lift: number?): Vector2?
	local height = ArenaConfig.PlaneHeight + (lift or 0)
	if math.abs(direction.Y) < 1e-6 then
		return nil
	end
	local t = (height - origin.Y) / direction.Y
	if t < 0 then
		return nil
	end
	return ArenaSpace.ToArena(origin + direction * t)
end

-- World CFrame at an arena position, facing along an arena direction (default: up the screen).
function ArenaSpace.CFrameAt(position: Vector2, facing: Vector2?, lift: number?): CFrame
	local origin = ArenaSpace.ToWorld(position, lift)
	local direction = facing or Vector2.new(0, 1)
	if direction.Magnitude < 1e-6 then
		return CFrame.new(origin)
	end
	local look = Vector3.new(direction.X, 0, -direction.Y)
	return CFrame.lookAt(origin, origin + look)
end

return table.freeze(ArenaSpace)
