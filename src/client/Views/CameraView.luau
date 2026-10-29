--!strict
--[[
	CameraView: the scripted camera looking down on the play plane.

	It sits high above the plane with a narrow field of view, tilted ArenaConfig.CamTilt
	from straight down with north at the top of the screen. Its distance is set so
	that ArenaConfig.CamView arena units show from the screen's centre to its top
	and bottom edges. For now it stays on the planet; following the ship comes later.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaConfig = require(KngChak.Data.ArenaConfig)
local ArenaSpace = require(KngChak.Arena.ArenaSpace)

local CameraView = {}

-- Points the current camera at an arena position.
function CameraView.LookAt(focus: Vector2)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = ArenaConfig.CamFov

	local distance = ArenaConfig.CamView / math.tan(math.rad(ArenaConfig.CamFov / 2))
	local tilt = math.rad(ArenaConfig.CamTilt)
	-- Back toward the bottom of the screen (world +Z) and up, by the tilt angle.
	local offset = Vector3.new(0, math.cos(tilt), math.sin(tilt)) * distance
	local target = ArenaSpace.ToWorld(focus)
	camera.CFrame = CFrame.lookAt(target + offset, target)
end

return table.freeze(CameraView)
