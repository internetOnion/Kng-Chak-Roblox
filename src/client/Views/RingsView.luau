--!strict
--[[
	RingsView: the orbit band and the arena edge, drawn from the arena data.

	    local rings = RingsView.new(folder)
	    rings:Update(snapshot.Ship.Position, run:GetTuning().Arena) -- every frame

	Each ring is a loop of thin parts at a radius taken from the arena values, so
	changing a value moves its ring. The orbit band glows (it's energy); the edge
	stays hidden until the ship is within EdgeShowDist of it, then fades in.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaConfig = require(KngChak.Data.ArenaConfig)
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local ViewMath = require(KngChak.Arena.ViewMath)

local LIFT = 0.5 -- studs above the play plane
local BAND_COLOR = Color3.fromHex("#6ff3ff")
local BAND_TRANSPARENCY = 0.35
local EDGE_COLOR = Color3.fromHex("#ffffff")
local EDGE_MAX_OPACITY = 0.7

type Ring = {
	model: Model,
	parts: { BasePart },
	radius: number,
}

local RingsView = {}
RingsView.__index = RingsView

export type RingsView = typeof(setmetatable(
	{} :: {
		_parent: Instance,
		_band: Ring?,
		_edge: Ring?,
		_edgeTransparency: number,
	},
	RingsView
))

local function buildRing(
	parent: Instance,
	name: string,
	radius: number,
	width: number,
	color: Color3,
	neon: boolean
): Ring
	local model = Instance.new("Model")
	model.Name = name
	local segments = math.clamp(math.floor(radius * 1.5), 48, 128)
	local length = 2 * math.pi * radius / segments * 1.04
	local parts: { BasePart } = {}
	for i = 1, segments do
		local angle = (i - 0.5) / segments * 2 * math.pi
		local position = Vector2.new(math.cos(angle), math.sin(angle)) * radius
		local tangent = Vector2.new(-math.sin(angle), math.cos(angle))
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.Color = color
		part.Size = Vector3.new(width, 0.15, length)
		part.CFrame = ArenaSpace.CFrameAt(position, tangent, LIFT)
		part.Parent = model
		table.insert(parts, part)
	end
	model.Parent = parent
	return { model = model, parts = parts, radius = radius }
end

local function setTransparency(ring: Ring, transparency: number)
	for _, part in ring.parts do
		part.Transparency = transparency
	end
end

function RingsView.new(parent: Instance): RingsView
	return setmetatable({ _parent = parent, _band = nil, _edge = nil, _edgeTransparency = -1 }, RingsView)
end

-- The ring if it's still at `radius`, otherwise a new one built there.
local function ringAt(
	parent: Instance,
	ring: Ring?,
	name: string,
	radius: number,
	width: number,
	color: Color3,
	neon: boolean
): Ring
	if ring and ring.radius == radius then
		return ring
	end
	if ring then
		ring.model:Destroy()
	end
	return buildRing(parent, name, radius, width, color, neon)
end

function RingsView.Update(self: RingsView, shipPosition: Vector2, arena: ArenaConfig.ArenaConfig)
	local oldBand = self._band
	local band =
		ringAt(self._parent, oldBand, "OrbitBand", arena.PlanetRadius + arena.OrbitBandTop, 0.35, BAND_COLOR, true)
	if band ~= oldBand then
		setTransparency(band, BAND_TRANSPARENCY)
		self._band = band
	end

	local oldEdge = self._edge
	local edge = ringAt(self._parent, oldEdge, "ArenaEdge", arena.ArenaRadius, 0.5, EDGE_COLOR, false)
	if edge ~= oldEdge then
		self._edge = edge
		self._edgeTransparency = -1
	end

	local visibility = ViewMath.EdgeVisibility(arena, shipPosition)
	local transparency = 1 - visibility * EDGE_MAX_OPACITY
	if math.abs(transparency - self._edgeTransparency) > 0.01 then
		setTransparency(edge, transparency)
		self._edgeTransparency = transparency
	end
end

function RingsView.Destroy(self: RingsView)
	if self._band then
		self._band.model:Destroy()
	end
	if self._edge then
		self._edge.model:Destroy()
	end
end

return RingsView
