--!strict
--[[
	ShipView: draws the Lancer toy hull and its engine flame from the Run's snapshot.

	    local ship = ShipView.new(folder)
	    ship:Listen(GameEvents)                     -- optional: clank flash on RockClanged
	    ship:Update(run:Snapshot().Ship, dt, true)  -- every frame, after the Run steps

	The model is a clone of ReplicatedStorage.Assets.Ship.Ship, built nose along -Z
	around the origin. Soft Helmet* parts show normally; Spear* parts replace them
	while the spear is out. FlameView renders the 3-band Neon engine plume and sparks
	outside the highlighted hull Model so the black Toy Box outline hugs the solid
	hull and the flame glows cleanly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local RunEvents = require(KngChak.Run.RunEvents)

local FlameView = require(script.Parent.FlameView)
local Outlines = require(script.Parent.Outlines)

local LIFT = 3 -- studs above the play plane (see the art guide's heights)
local SHIP_OUTLINE_RADIUS = 1.8

-- The fields the view reads. A Run snapshot's Ship has them all.
export type ShipLook = FlameView.FlameLook & {
	IsSpearOut: boolean,
}

local ShipView = {}
ShipView.__index = ShipView

export type ShipView = typeof(setmetatable(
	{} :: {
		_model: Model,
		_helmet: { BasePart },
		_spear: { BasePart },
		_flame: FlameView.FlameView,
		_outline: Outlines.Handle,
	},
	ShipView
))

function ShipView.new(parent: Instance): ShipView
	local assets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Ship")
	local prefab = (
		assets:FindFirstChild("kc_ship_lancer")
		or assets:FindFirstChild("Ship")
		or assets:FindFirstChildWhichIsA("Model")
	) :: Model
	local model = prefab:Clone()
	model.WorldPivot = CFrame.identity -- assets are built around the origin; Studio may have picked another pivot

	local helmet: { BasePart } = {}
	local spear: { BasePart } = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			if string.sub(part.Name, 1, 6) == "Helmet" then
				table.insert(helmet, part)
			elseif string.sub(part.Name, 1, 5) == "Spear" then
				table.insert(spear, part)
			end
		end
	end

	model.Parent = parent
	local outline = Outlines.Register(model, SHIP_OUTLINE_RADIUS, Outlines.Tier.Hero)
	local flame = FlameView.new(parent)

	return setmetatable({
		_model = model,
		_helmet = helmet,
		_spear = spear,
		_flame = flame,
		_outline = outline,
	}, ShipView)
end

function ShipView.Listen(self: ShipView, events: RunEvents.RunEvents)
	self._flame:Listen(events)
end

function ShipView.Update(self: ShipView, ship: ShipLook, dt: number?, active: boolean?, coneDeg: number?)
	local pivot = ArenaSpace.CFrameAt(ship.Position, ship.Facing, LIFT)
	self._model:PivotTo(pivot)

	local helmetAlpha = if ship.IsSpearOut then 1 else 0
	local spearAlpha = if ship.IsSpearOut then 0 else 1
	for _, part in self._helmet do
		part.Transparency = helmetAlpha
	end
	for _, part in self._spear do
		part.Transparency = spearAlpha
	end

	self._outline:SetState(true, false, ship.Position.Magnitude, Outlines.Tier.Hero)
	self._flame:Update(ship, dt, active, coneDeg)
end

function ShipView.Destroy(self: ShipView)
	self._outline:Unregister()
	self._flame:Destroy()
	self._model:Destroy()
end

return ShipView
