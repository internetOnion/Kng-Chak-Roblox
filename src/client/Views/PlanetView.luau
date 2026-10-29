--!strict
--[[
	PlanetView: draws the planet at the arena's centre.

	The model is a clone of ReplicatedStorage.Assets.Planet.Planet, sized from
	ArenaConfig.PlanetRadius. Swapping the greybox for real art changes only that asset.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaConfig = require(KngChak.Data.ArenaConfig)
local ArenaSpace = require(KngChak.Arena.ArenaSpace)

local PlanetView = {}
PlanetView.__index = PlanetView

export type PlanetView = typeof(setmetatable({} :: { _model: BasePart }, PlanetView))

function PlanetView.new(parent: Instance): PlanetView
	local prefab = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Planet"):WaitForChild("Planet") :: BasePart
	local model = prefab:Clone()
	model.Size = Vector3.one * ArenaConfig.PlanetRadius * 2
	model.CFrame = ArenaSpace.CFrameAt(Vector2.zero)
	model.Parent = parent
	return setmetatable({ _model = model }, PlanetView)
end

function PlanetView.Destroy(self: PlanetView)
	self._model:Destroy()
end

return PlanetView
