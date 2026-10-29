--!strict
--[[
	RingsView: the orbit band and the arena edge, drawn from the arena data.

	    local rings = RingsView.new(folder)
	    rings:Update(snapshot.Ship, run:GetTuning().Arena) -- every frame

	Each ring is a loop of parts at a radius taken from the arena values, so
	changing a value moves its ring. The orbit band is a dashed loop of glowing
	toy beads (it's energy), turning red while the ship is captured in orbit (only
	a boost gets it out); the edge is a thin solid line that stays hidden until
	the ship is within EdgeShowDist of it, then fades in.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaConfig = require(KngChak.Data.ArenaConfig)
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local ViewMath = require(KngChak.Arena.ViewMath)

local LIFT = 0.5 -- studs above the play plane
local BAND_COLOR = Color3.fromHex("#6ff3ff")
local CAPTURED_COLOR = Color3.fromHex("#ff4d5e")
local BAND_TRANSPARENCY = 0.25
local BAND_DASHES = 36
local BAND_DASH = Vector3.new(0.45, 0.3, 1.4) -- each bead's width, height and length
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
		_centre: Vector2,
		_band: Ring?,
		_edge: Ring?,
		_edgeTransparency: number,
		_bandColor: Color3?,
	},
	RingsView
))

-- A ring of `segments` parts; with `dash` set, beads of that size with gaps, otherwise a solid line.
local function buildRing(
	parent: Instance,
	centre: Vector2,
	name: string,
	radius: number,
	width: number,
	color: Color3,
	neon: boolean,
	dash: Vector3?,
	dashes: number?
): Ring
	local model = Instance.new("Model")
	model.Name = name
	local segments = dashes or math.clamp(math.floor(radius * 1.5), 48, 128)
	local length = 2 * math.pi * radius / segments * 1.04
	local parts: { BasePart } = {}
	for i = 1, segments do
		local angle = (i - 0.5) / segments * 2 * math.pi
		local position = centre + Vector2.new(math.cos(angle), math.sin(angle)) * radius
		local tangent = Vector2.new(-math.sin(angle), math.cos(angle))
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.Color = color
		if dash then
			part.Size = dash
			local bead = Instance.new("SpecialMesh")
			bead.MeshType = Enum.MeshType.Sphere
			bead.Parent = part
		else
			part.Size = Vector3.new(width, 0.15, length)
		end
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

-- Rings around `centre` (default: the arena's centre).
function RingsView.new(parent: Instance, centre: Vector2?): RingsView
	return setmetatable({
		_parent = parent,
		_centre = centre or Vector2.zero,
		_band = nil,
		_edge = nil,
		_edgeTransparency = -1,
		_bandColor = nil,
	}, RingsView)
end

-- The ring if it's still at `radius`, otherwise a new one built there.
local function ringAt(ring: Ring?, radius: number, build: () -> Ring): Ring
	if ring and ring.radius == radius then
		return ring
	end
	if ring then
		ring.model:Destroy()
	end
	return build()
end

-- The fields the view reads. A Run snapshot's Ship has them all.
export type ShipPlace = {
	Position: Vector2,
	IsCaptured: boolean,
}

function RingsView.Update(self: RingsView, ship: ShipPlace, arena: ArenaConfig.ArenaConfig)
	local shipPosition = ship.Position
	local oldBand = self._band
	local bandRadius = arena.PlanetRadius + arena.OrbitBandTop
	local band = ringAt(oldBand, bandRadius, function()
		return buildRing(
			self._parent,
			self._centre,
			"OrbitBand",
			bandRadius,
			0,
			BAND_COLOR,
			true,
			BAND_DASH,
			BAND_DASHES
		)
	end)
	if band ~= oldBand then
		setTransparency(band, BAND_TRANSPARENCY)
		self._band = band
		self._bandColor = nil
	end
	local color = if ship.IsCaptured then CAPTURED_COLOR else BAND_COLOR
	if color ~= self._bandColor then
		for _, part in band.parts do
			part.Color = color
		end
		self._bandColor = color
	end

	local oldEdge = self._edge
	local edge = ringAt(oldEdge, arena.ArenaRadius, function()
		return buildRing(self._parent, self._centre, "ArenaEdge", arena.ArenaRadius, 0.5, EDGE_COLOR, false)
	end)
	if edge ~= oldEdge then
		self._edge = edge
		self._edgeTransparency = -1
	end

	local visibility = ViewMath.EdgeVisibility(arena, shipPosition - self._centre)
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
