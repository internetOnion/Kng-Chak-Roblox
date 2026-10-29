--!strict
--[[
	ShieldView: the shield ring around the planet, shown only while there's shield.

	    local shield = ShieldView.new(folder)
	    shield:Update(snapshot.PlanetShield, snapshot.PlanetMaxShield, run:GetTuning().Arena) -- every frame

	A ring of glowing beads just outside the planet's surface (the shield is energy).
	It's hidden at 0 shield and grows more solid as the shield fills toward its max.
	It only reads the snapshot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaConfig = require(KngChak.Data.ArenaConfig)
local ArenaSpace = require(KngChak.Arena.ArenaSpace)

local COLOR = Color3.fromHex("#bff6ff")
local GAP = 1.2 -- studs out from the planet's surface
local LIFT = 0.5
local BEADS = 48
local BEAD = Vector3.new(0.6, 0.6, 1.1)
local FAINTEST = 0.75 -- transparency at a sliver of shield; a full shield is SOLIDEST
local SOLIDEST = 0.1

local ShieldView = {}
ShieldView.__index = ShieldView

export type ShieldView = typeof(setmetatable(
	{} :: {
		_parent: Instance,
		_centre: Vector2,
		_model: Model?,
		_radius: number,
		_transparency: number,
	},
	ShieldView
))

function ShieldView.new(parent: Instance, centre: Vector2?): ShieldView
	return setmetatable({
		_parent = parent,
		_centre = centre or Vector2.zero,
		_model = nil :: Model?,
		_radius = 0,
		_transparency = -1,
	}, ShieldView)
end

local function build(self: ShieldView, radius: number): Model
	local model = Instance.new("Model")
	model.Name = "Shield"
	for i = 1, BEADS do
		local angle = (i - 0.5) / BEADS * 2 * math.pi
		local position = self._centre + Vector2.new(math.cos(angle), math.sin(angle)) * radius
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = COLOR
		part.Size = BEAD
		part.Transparency = 1
		local bead = Instance.new("SpecialMesh")
		bead.MeshType = Enum.MeshType.Sphere
		bead.Parent = part
		part.CFrame = ArenaSpace.CFrameAt(position, Vector2.new(-math.sin(angle), math.cos(angle)), LIFT)
		part.Parent = model
	end
	model.Parent = self._parent
	return model
end

function ShieldView.Update(self: ShieldView, shield: number, maxShield: number, arena: ArenaConfig.ArenaConfig)
	local radius = arena.PlanetRadius + GAP
	local model = self._model
	if not model or self._radius ~= radius then
		if model then
			model:Destroy()
		end
		model = build(self, radius)
		self._model = model
		self._radius = radius
		self._transparency = -1
	end
	local fill = if maxShield > 0 then math.clamp(shield / maxShield, 0, 1) else 0
	local transparency = if shield > 0 then FAINTEST + (SOLIDEST - FAINTEST) * fill else 1
	if math.abs(transparency - self._transparency) > 0.01 then
		self._transparency = transparency
		for _, part in (model :: Model):GetChildren() do
			(part :: BasePart).Transparency = transparency
		end
	end
end

function ShieldView.Destroy(self: ShieldView)
	if self._model then
		self._model:Destroy()
	end
end

return ShieldView
