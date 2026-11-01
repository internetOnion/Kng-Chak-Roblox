--!strict
--[[
	BossView: draws the Inferno's burning body while it's in the arena.

	    local boss = BossView.new(folder)
	    boss:Update(snapshot.Boss, tuning.Inferno) -- every frame; nil when there's no boss

	The model is ReplicatedStorage.Assets.Boss.Inferno, built at radius 1 around
	the origin with its front along -Z; the view scales it to the body radius,
	paints its Body parts with the data's tint and turns its front to the planet.
	Its plates and core are rocks, so the rock view draws them. The view only
	reads the snapshot and never changes the Run.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local InfernoConfig = require(KngChak.Data.InfernoConfig)
local Run = require(KngChak.Run.Run)

local Outlines = require(script.Parent.Outlines)

local LIFT = -1.5 -- sunk into the play plane, so its top stays about level with the ship and its plates stand out on its rim

local BossView = {}
BossView.__index = BossView

export type BossView = typeof(setmetatable(
	{} :: {
		_parent: Instance,
		_model: Model?,
		_outline: Outlines.Handle?,
	},
	BossView
))

function BossView.new(parent: Instance): BossView
	return setmetatable({ _parent = parent, _model = nil :: Model?, _outline = nil :: Outlines.Handle? }, BossView)
end

local function build(parent: Instance, config: InfernoConfig.InfernoConfig): (Model, Outlines.Handle)
	local assets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Boss")
	local prefab = (
		assets:FindFirstChild("kc_boss_inferno")
		or assets:FindFirstChild("Inferno")
		or assets:FindFirstChildWhichIsA("Model")
	) :: Model
	local model = prefab:Clone()
	model.WorldPivot = CFrame.identity -- assets are built around the origin; Studio may have picked another pivot
	model:ScaleTo(config.BodyRadius)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and string.sub(part.Name, 1, 4) == "Body" then
			part.Color = config.BodyTint
		end
	end
	model.Parent = parent
	local outline = Outlines.Register(model, config.BodyRadius, Outlines.Tier.Hero)
	return model, outline
end

function BossView.Update(self: BossView, boss: Run.BossSnapshot?, config: InfernoConfig.InfernoConfig)
	if not boss then
		if self._outline then
			self._outline:Unregister()
			self._outline = nil
		end
		if self._model then
			self._model:Destroy()
			self._model = nil
		end
		return
	end
	local existingModel = self._model
	local existingOutline = self._outline
	local activeModel: Model
	local activeOutline: Outlines.Handle
	if existingModel and existingOutline then
		activeModel = existingModel
		activeOutline = existingOutline
	else
		activeModel, activeOutline = build(self._parent, config)
		self._model = activeModel
		self._outline = activeOutline
	end
	activeModel:PivotTo(ArenaSpace.CFrameAt(boss.Position, -boss.Position, LIFT))
	activeOutline:SetState(true, false, boss.Position.Magnitude, Outlines.Tier.Hero)
end

function BossView.Destroy(self: BossView)
	if self._outline then
		self._outline:Unregister()
		self._outline = nil
	end
	if self._model then
		self._model:Destroy()
		self._model = nil
	end
end

return BossView
