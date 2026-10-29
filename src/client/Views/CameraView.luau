--!strict
--[[
	CameraView: the scripted camera looking down on the play plane.

	    local camera = CameraView.new()
	    camera:Update(snapshot.Ship.Position, run:GetTuning().Arena, dt) -- every frame

	It sits high above the plane with a narrow field of view, tilted CamTilt from
	straight down with north at the top of the screen, far enough that CamView arena
	units show from the screen's centre to its nearer edge. It follows the ship out
	in the arena and eases onto the planet near orbit (see Arena/ViewMath). It only
	pans: it never rotates and never lags; only a sudden jump in its target (a
	restart) is eased out over CamSettle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaConfig = require(KngChak.Data.ArenaConfig)
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local ViewMath = require(KngChak.Arena.ViewMath)

local JUMP = 5 -- a target move bigger than this in one frame is a jump, not flight

local CameraView = {}
CameraView.__index = CameraView

export type CameraView = typeof(setmetatable(
	{} :: {
		_target: Vector2?,
		_offset: Vector2, -- what's left of a jump, decaying to zero
		_focus: Vector2, -- where it looks now
		_viewHalf: Vector2, -- half the visible play plane, in arena units
	},
	CameraView
))

function CameraView.new(): CameraView
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	return setmetatable(
		{ _target = nil, _offset = Vector2.zero, _focus = Vector2.zero, _viewHalf = Vector2.one },
		CameraView
	)
end

function CameraView.Update(self: CameraView, shipPosition: Vector2, arena: ArenaConfig.ArenaConfig, dt: number)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = arena.CamFov

	local viewport = camera.ViewportSize
	local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
	local viewHalf = ViewMath.ViewHalf(arena, aspect)
	local target = ViewMath.CameraFocus(arena, shipPosition, viewHalf)
	self._viewHalf = viewHalf

	local last = self._target
	if last and (target - last).Magnitude > JUMP then
		self._offset += last - target
	end
	self._target = target
	self._offset *= math.exp(-arena.CamSettle * dt)
	self._focus = target + self._offset
	CameraView.LookAt(self, self._focus, arena)
end

-- What's on screen: the arena position at its centre and half its size, in arena units (for the radar).
function CameraView.View(self: CameraView): (Vector2, Vector2)
	return self._focus, self._viewHalf
end

-- Points the camera straight at an arena position, at the game's zoom, field of view and tilt.
function CameraView.LookAt(_self: CameraView, focus: Vector2, arena: ArenaConfig.ArenaConfig)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = arena.CamFov
	local distance = arena.CamView / math.tan(math.rad(arena.CamFov / 2))
	local tilt = math.rad(arena.CamTilt)
	-- Back toward the bottom of the screen (world +Z) and up, by the tilt angle.
	local offset = Vector3.new(0, math.cos(tilt), math.sin(tilt)) * distance
	local world = ArenaSpace.ToWorld(focus)
	camera.CFrame = CFrame.lookAt(world + offset, world)
end

return CameraView
