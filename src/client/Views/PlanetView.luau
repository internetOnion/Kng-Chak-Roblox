--!strict
--[[
	PlanetView: draws the planet at the arena's centre.

	The model is a clone of ReplicatedStorage.Assets.Planet.Planet, built at
	radius 10 around the origin with north (the top of the screen) along -Z, and
	scaled to ArenaConfig.PlanetRadius. Swapping the greybox for real art changes
	only that asset.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaConfig = require(KngChak.Data.ArenaConfig)
local ArenaSpace = require(KngChak.Arena.ArenaSpace)

local MODEL_RADIUS = 10 -- the radius the asset is built at

local PlanetView = {}
PlanetView.__index = PlanetView

export type PlanetView = typeof(setmetatable({} :: { _model: Model }, PlanetView))

function PlanetView.new(parent: Instance): PlanetView
	local prefab = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Planet"):WaitForChild("Planet") :: Model
	local model = prefab:Clone()
	model.WorldPivot = CFrame.identity -- assets are built around the origin; Studio may have picked another pivot
	model:ScaleTo(ArenaConfig.PlanetRadius / MODEL_RADIUS)
	model:PivotTo(ArenaSpace.CFrameAt(Vector2.zero))
	model.Parent = parent
	return setmetatable({ _model = model }, PlanetView)
end

function PlanetView.Destroy(self: PlanetView)
	self._model:Destroy()
end

return PlanetView
