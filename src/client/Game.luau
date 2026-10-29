--!strict
--[[
	Game: starts a Run on this client and draws it.

	Each frame the Run steps with the player's input, then the views read its
	snapshot. GameEvents follows the Run, so anything listening there hears it.

	First slice: a few rocks drop onto the planet. Input is idle until flight lands.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local KngChak = ReplicatedStorage.KngChak
local GameEvents = require(KngChak.GameEvents)
local RockTypes = require(KngChak.Data.RockTypes)
local Run = require(KngChak.Run.Run)

local CameraView = require(script.Parent.Views.CameraView)
local PlanetView = require(script.Parent.Views.PlanetView)
local RockView = require(script.Parent.Views.RockView)

-- Until the spawner lands: rocks of a few types, arriving one after another.
local START_ROCKS: { Run.RockSetup } = {
	{ Type = RockTypes.Rock, Position = Vector2.new(0, 40) },
	{ Type = RockTypes.Comet, Position = Vector2.new(-40, 28) },
	{ Type = RockTypes.Iron, Position = Vector2.new(30, -18) },
}

return function()
	local folder = Instance.new("Folder")
	folder.Name = "Arena"
	folder.Parent = workspace

	local run = Run.new({ Rocks = START_ROCKS })
	GameEvents.Follow(run.Events)

	PlanetView.new(folder)
	local rocks = RockView.new(folder)
	CameraView.LookAt(Vector2.zero)

	RunService.RenderStepped:Connect(function(dt: number)
		run:Step(Run.IdleInput, dt)
		local snapshot = run:Snapshot()
		rocks:Update(snapshot.Rocks)
	end)
end
