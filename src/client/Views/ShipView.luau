--!strict
--[[
	ShipView: draws the Lancer from the Run's snapshot.

	    local ship = ShipView.new(folder)
	    ship:Update(run:Snapshot().Ship) -- every frame, after the Run steps

	The model is a clone of ReplicatedStorage.Assets.Ship.Ship, built nose along
	-Z around the origin. Its Spear part shows while the spear is out; its Flame
	part stretches behind the engine as far as the flame's push reach and takes the
	state's colour.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local Ship = require(KngChak.Ship.Ship)

local LIFT = 3 -- studs above the play plane (see the art guide's heights)
local FLAME_START = 1.7 -- studs behind the ship's centre
local FLAME_WIDTH = 0.8

-- Mid heat colours from the art guide.
local FLAME_SOFT = Color3.fromHex("#ff9a1f")
local FLAME_BOOST = Color3.fromHex("#ffe08a")
local FLAME_STUNNED = Color3.fromHex("#6a707c")

local ShipView = {}
ShipView.__index = ShipView

export type ShipView = typeof(setmetatable(
	{} :: {
		_model: Model,
		_spear: BasePart?,
		_flame: BasePart?,
	},
	ShipView
))

function ShipView.new(parent: Instance): ShipView
	local prefab = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Ship"):WaitForChild("Ship") :: Model
	local model = prefab:Clone()
	model.Parent = parent
	return setmetatable({
		_model = model,
		_spear = model:FindFirstChild("Spear") :: BasePart?,
		_flame = model:FindFirstChild("Flame") :: BasePart?,
	}, ShipView)
end

function ShipView.Update(self: ShipView, ship: Ship.Ship)
	local pivot = ArenaSpace.CFrameAt(ship.Position, ship.Facing, LIFT)
	self._model:PivotTo(pivot)

	local spear = self._spear
	if spear then
		spear.Transparency = if ship.IsSpearOut then 0 else 1
	end

	local flame = self._flame
	if flame then
		-- the flame is the push zone, so it reaches exactly as far as the Run's FlameReach
		local length = math.max(0.6, ship.FlameReach - FLAME_START)
		local width = FLAME_WIDTH + length * 0.15
		flame.Size = Vector3.new(width, FLAME_WIDTH * 0.8, length)
		flame.CFrame = pivot * CFrame.new(0, 0, FLAME_START + length / 2)
		flame.Color = if ship.IsStunned then FLAME_STUNNED elseif ship.IsBoosting then FLAME_BOOST else FLAME_SOFT
		flame.Transparency = 0
	end
end

function ShipView.Destroy(self: ShipView)
	self._model:Destroy()
end

return ShipView
