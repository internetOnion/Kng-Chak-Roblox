--!strict
--[[
	ShipView: draws the Lancer from the Run's snapshot (or any ship-shaped state).

	    local ship = ShipView.new(folder)
	    ship:Update(run:Snapshot().Ship) -- every frame, after the Run steps

	The model is a clone of ReplicatedStorage.Assets.Ship.Ship, built nose along -Z
	around the origin. The soft Helmet nose shows normally; Spear and SpearTip
	replace it while the spear is out. The three Flame bands (edge, mid, core)
	stretch behind the engine as far as the flame's push reach, so the flame you
	see is the push zone, and take the heat colours of the ship's state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaSpace = require(KngChak.Arena.ArenaSpace)

local LIFT = 3 -- studs above the play plane (see the art guide's heights)
local FLAME_START = 1.45 -- studs behind the ship's centre: the back of the grille
local PILOT_LENGTH = 0.8 -- the flame's length when the engine idles
local FLAME_TRANSPARENCY = 0.05

-- Heat ladder from the art guide: edge, mid, core.
local HEAT = {
	soft = { Color3.fromHex("#ff4a1c"), Color3.fromHex("#ff9a1f"), Color3.fromHex("#ffe066") },
	boost = { Color3.fromHex("#ffa030"), Color3.fromHex("#ffe08a"), Color3.fromHex("#ffffff") },
	stunned = { Color3.fromHex("#40444d"), Color3.fromHex("#6a707c"), Color3.fromHex("#9aa0aa") },
}
local BANDS = { "FlameEdge", "FlameMid", "FlameCore" }
local BAND_SCALE = { 1, 0.72, 0.44 } -- each band's length relative to the edge's

-- The fields the view reads. A Run snapshot's Ship has them all.
export type ShipLook = {
	Position: Vector2,
	Facing: Vector2,
	IsSpearOut: boolean,
	IsBoosting: boolean,
	IsStunned: boolean,
	FlameReach: number,
}

type Band = {
	part: BasePart,
	width: Vector2, -- the band's width and height, from the model
	scale: number,
}

local ShipView = {}
ShipView.__index = ShipView

export type ShipView = typeof(setmetatable(
	{} :: {
		_model: Model,
		_helmet: BasePart?,
		_spear: { BasePart },
		_bands: { Band },
		_heat: { Color3 }?,
	},
	ShipView
))

function ShipView.new(parent: Instance): ShipView
	local prefab = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Ship"):WaitForChild("Ship") :: Model
	local model = prefab:Clone()
	model.WorldPivot = CFrame.identity -- assets are built around the origin; Studio may have picked another pivot

	local spear = {}
	for _, name in { "Spear", "SpearTip" } do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(spear, part)
		end
	end
	local bands = {}
	for i, name in BANDS do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(bands, { part = part, width = Vector2.new(part.Size.X, part.Size.Y), scale = BAND_SCALE[i] })
		end
	end

	model.Parent = parent
	return setmetatable({
		_model = model,
		_helmet = model:FindFirstChild("Helmet") :: BasePart?,
		_spear = spear,
		_bands = bands,
		_heat = nil :: { Color3 }?,
	}, ShipView)
end

function ShipView.Update(self: ShipView, ship: ShipLook)
	local pivot = ArenaSpace.CFrameAt(ship.Position, ship.Facing, LIFT)
	self._model:PivotTo(pivot)

	local helmet = self._helmet
	if helmet then
		helmet.Transparency = if ship.IsSpearOut then 1 else 0
	end
	for _, part in self._spear do
		part.Transparency = if ship.IsSpearOut then 0 else 1
	end

	local heat = if ship.IsStunned then HEAT.stunned elseif ship.IsBoosting then HEAT.boost else HEAT.soft
	local length = math.max(PILOT_LENGTH, ship.FlameReach - FLAME_START)
	for i, band in self._bands do
		local bandLength = length * band.scale
		band.part.Size = Vector3.new(band.width.X, band.width.Y, bandLength)
		band.part.CFrame = pivot * CFrame.new(0, 0, FLAME_START + bandLength / 2)
		band.part.Transparency = FLAME_TRANSPARENCY
		if heat ~= self._heat then
			band.part.Color = heat[i]
		end
	end
	self._heat = heat
end

function ShipView.Destroy(self: ShipView)
	self._model:Destroy()
end

return ShipView
