--!strict
--[[
	Game: starts a Run on this client and draws it.

	Each frame the input adapter turns the player's controls into the Run's input,
	the Run steps, then the views read its snapshot. GameEvents follows the Run,
	so anything listening there hears it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local KngChak = ReplicatedStorage.KngChak
local GameEvents = require(KngChak.GameEvents)
local RockTypes = require(KngChak.Data.RockTypes)
local Run = require(KngChak.Run.Run)

local CameraView = require(script.Parent.Views.CameraView)
local MouseInput = require(script.Parent.Input.MouseInput)
local PlanetView = require(script.Parent.Views.PlanetView)
local RingsView = require(script.Parent.Views.RingsView)
local RockView = require(script.Parent.Views.RockView)
local ShipView = require(script.Parent.Views.ShipView)

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
	local rings = RingsView.new(folder)
	local rocks = RockView.new(folder)
	local ship = ShipView.new(folder)
	local mouse = MouseInput.new()
	local camera = CameraView.new()

	local snapshot = run:Snapshot()
	RunService.RenderStepped:Connect(function(dt: number)
		run:Step(mouse:Read(snapshot.Ship.Position), dt)
		snapshot = run:Snapshot()
		local arena = run:GetTuning().Arena
		camera:Update(snapshot.Ship.Position, arena, dt)
		rings:Update(snapshot.Ship.Position, arena)
		ship:Update(snapshot.Ship)
		rocks:Update(snapshot.Rocks)
	end)
end
