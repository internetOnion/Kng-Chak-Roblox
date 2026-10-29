--!strict
--[[
	BeaconView: the guided first call's beacon, a spinning ring of Neon beads to fly through.

	    local beacon = BeaconView.new(folder)
	    beacon:Update(snapshot.Guided and snapshot.Guided.Beacon, now) -- every frame; nil hides it

	Its size is the data's BeaconRadius, so it matches the spot that counts. It
	only reads the snapshot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local GuidedConfig = require(KngChak.Data.GuidedConfig)

local BEADS = 18
local LIFT = 2.5
local COLOR = Color3.fromHex("#ffe066")
local SPIN = 1.2 -- radians per second

local BeaconView = {}
BeaconView.__index = BeaconView

export type BeaconView = typeof(setmetatable({} :: { _model: Model, _beads: { Part } }, BeaconView))

function BeaconView.new(parent: Instance): BeaconView
	local model = Instance.new("Model")
	model.Name = "Beacon"
	local beads = {}
	for _ = 1, BEADS do
		local bead = Instance.new("Part")
		bead.Shape = Enum.PartType.Ball
		bead.Size = Vector3.one * 0.7
		bead.Material = Enum.Material.Neon
		bead.Color = COLOR
		bead.Anchored = true
		bead.CanCollide = false
		bead.CanTouch = false
		bead.CanQuery = false
		bead.CastShadow = false
		bead.Parent = model
		table.insert(beads, bead)
	end
	model.Parent = parent
	return setmetatable({ _model = model, _beads = beads }, BeaconView)
end

function BeaconView.Update(self: BeaconView, beacon: Vector2?, now: number)
	for index, bead in self._beads do
		if beacon then
			local angle = now * SPIN + (index - 1) / BEADS * 2 * math.pi
			local pulse = 1 + 0.08 * math.sin(now * 4)
			local offset = Vector2.new(math.cos(angle), math.sin(angle)) * GuidedConfig.BeaconRadius * pulse
			bead.Position = ArenaSpace.ToWorld(beacon + offset, LIFT)
			bead.Transparency = 0
		else
			bead.Transparency = 1
		end
	end
end

function BeaconView.Destroy(self: BeaconView)
	self._model:Destroy()
end

return BeaconView
