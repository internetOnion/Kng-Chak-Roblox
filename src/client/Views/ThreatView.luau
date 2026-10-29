--!strict
--[[
	ThreatView: where each rock will land, and which one lands first.

	    local threats = ThreatView.new(folder)
	    threats:Update(snapshot, run:GetTuning().Arena, os.clock()) -- every frame

	For every rock: a thin trajectory hint from the rock down to the planet and an
	impact mark on the planet's edge where it will land, in the rock's colour
	(pink while primed, red and pulsing once it's about to hit). The threat, the
	rock the Run says will hit soonest (Snapshot.ThreatId), also gets a pulsing
	glowing ring. The Inferno's plates and core get none. It only reads the snapshot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaConfig = require(KngChak.Data.ArenaConfig)
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local Rock = require(KngChak.Rocks.Rock)
local Run = require(KngChak.Run.Run)
local Threat = require(KngChak.Rocks.Threat)

local URGENT = Color3.fromHex("#ff4d5e")
local PRIMED = Color3.fromHex("#ff4fd8")
local RING_BEADS = 14
local RING_GAP = 0.9 -- studs out from the rock's edge
local RING_LIFT = 2 -- at the rocks' height (see the art guide's heights)
local HINT_LIFT = 0.3
local HINT_WIDTH = 0.18
local MARK_BEADS = 3
local MARK_LIFT = 0.4
local MARK_GAP = 0.6 -- studs out from the planet's surface
local PULSE = 6 -- radians per second of the shared pulse

type Marks = {
	hint: BasePart,
	marks: { BasePart },
}

local ThreatView = {}
ThreatView.__index = ThreatView

export type ThreatView = typeof(setmetatable(
	{} :: {
		_parent: Folder,
		_ring: { BasePart },
		_drawn: { [number]: Marks }, -- by rock Id
	},
	ThreatView
))

local function part(parent: Instance, name: string, neon: boolean, bead: boolean): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	if bead then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = parent
	return p
end

function ThreatView.new(parent: Instance): ThreatView
	local folder = Instance.new("Folder")
	folder.Name = "Threats"
	folder.Parent = parent
	local ring = {}
	for i = 1, RING_BEADS do
		local bead = part(folder, `ThreatRing{i}`, true, true)
		bead.Size = Vector3.new(0.4, 0.3, 0.9)
		bead.Color = URGENT
		bead.Transparency = 1
		table.insert(ring, bead)
	end
	return setmetatable({ _parent = folder, _ring = ring, _drawn = {} }, ThreatView)
end

-- The colour a rock's hints are drawn in, and whether it's about to hit.
function ThreatView.ColorOf(rock: Rock.Rock, planetRadius: number): (Color3, boolean)
	local urgent = Threat.Eta(rock, planetRadius) < Threat.UrgentEta
	if urgent then
		return URGENT, true
	elseif rock.IsPrimed then
		return PRIMED, false
	end
	return rock.Type.Tint, false
end

local function build(self: ThreatView): Marks
	local hint = part(self._parent, "Hint", false, false)
	local marks = {}
	for i = 1, MARK_BEADS do
		local mark = part(self._parent, `Mark{i}`, true, true)
		mark.Size = Vector3.new(0.5, 0.3, 0.9)
		table.insert(marks, mark)
	end
	return { hint = hint, marks = marks }
end

local function placeRing(self: ThreatView, rock: Rock.Rock?, pulse: number)
	if not rock then
		for _, bead in self._ring do
			bead.Transparency = 1
		end
		return
	end
	local radius = rock.Type.Radius + RING_GAP + 0.25 * pulse
	for i, bead in self._ring do
		local angle = (i - 0.5) / RING_BEADS * 2 * math.pi
		local at = rock.Position + Vector2.new(math.cos(angle), math.sin(angle)) * radius
		bead.CFrame = ArenaSpace.CFrameAt(at, Vector2.new(-math.sin(angle), math.cos(angle)), RING_LIFT)
		bead.Transparency = 0.45 - 0.4 * pulse
	end
end

function ThreatView.Update(self: ThreatView, snapshot: Run.Snapshot, arena: ArenaConfig.ArenaConfig, now: number)
	local planetRadius = arena.PlanetRadius
	local pulse = 0.5 + 0.5 * math.sin(now * PULSE)
	local seen = {}
	local threat: Rock.Rock? = nil
	for _, rock in snapshot.Rocks do
		if rock.Type.IsBossPart then
			continue -- the Inferno's parts ride on it and never land on their own
		end
		seen[rock.Id] = true
		if rock.Id == snapshot.ThreatId then
			threat = rock
		end
		local drawn = self._drawn[rock.Id]
		if not drawn then
			drawn = build(self)
			self._drawn[rock.Id] = drawn
		end
		local color, urgent = ThreatView.ColorOf(rock, planetRadius)

		-- trajectory hint: from the rock's edge down to where it lands
		local landing = Threat.ImpactPoint(rock, planetRadius)
		local from = rock.Position - rock.Position.Unit * rock.Type.Radius
		local length = math.max(0.05, (from - landing).Magnitude)
		local hint = drawn.hint
		hint.Size = Vector3.new(HINT_WIDTH, 0.05, length)
		hint.CFrame = ArenaSpace.CFrameAt((from + landing) / 2, landing - from, HINT_LIFT)
		hint.Color = color
		hint.Transparency = if urgent then 0.45 else 0.8

		-- impact mark: a short arc on the planet's edge, as wide as the rock
		local centre = math.atan2(landing.Y, landing.X)
		local span = rock.Type.Radius / planetRadius * 0.9
		for i, mark in drawn.marks do
			local angle = centre + span * ((i - 1) / (MARK_BEADS - 1) * 2 - 1)
			local at = Vector2.new(math.cos(angle), math.sin(angle)) * (planetRadius + MARK_GAP)
			mark.CFrame = ArenaSpace.CFrameAt(at, Vector2.new(-math.sin(angle), math.cos(angle)), MARK_LIFT)
			mark.Color = color
			mark.Transparency = if urgent then 0.6 * (1 - pulse) else 0.35
		end
	end
	for id, drawn in self._drawn do
		if not seen[id] then
			drawn.hint:Destroy()
			for _, mark in drawn.marks do
				mark:Destroy()
			end
			self._drawn[id] = nil
		end
	end
	placeRing(self, threat, pulse)
end

function ThreatView.Destroy(self: ThreatView)
	self._parent:Destroy()
end

return ThreatView
