--!strict
--[[
	FlameView: the Lancer's 3-band Neon engine plume and sparks (#43).

	    local flame = FlameView.new(parent)
	    flame:Listen(GameEvents)          -- optional: flashes clank heat on RockClanged
	    flame:Update(ship, dt, active)    -- every frame, after ShipView moves the hull

	Three nested Neon bands (edge, mid, core) stream out from the engine grille
	to ship.FlameReach so the visible flame matches the push zone at every throttle,
	widening laterally while locked into orbit (50 deg flare vs 42 deg cruise).
	Each band is articulated across three overlapping segments whose outer joints
	lag slightly behind turns, bending the plume smoothly on sharp curves.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local RunEvents = require(KngChak.Run.RunEvents)
local Signal = require(KngChak.Util.Signal)

local LIFT = 3 -- matches ShipView's height above the play plane
local FLAME_START = 1.45 -- studs behind the ship's centre: back of the engine grille
local PILOT_LENGTH = 0.8 -- idle pilot flame length when FlameReach is 0
local FLAME_TRANSPARENCY = 0.04
local ORBIT_WIDTH_SCALE = 1.32 -- matches OrbitFlareAngle (50 deg) vs PushConeAngle (42 deg)
local CLANK_DURATION = 0.22 -- seconds the metallic clang flash holds on the plume
local MAX_BEND_RAD = math.rad(30) -- cap per-joint lag so instant flips stay cohesive

export type FlameState = "soft" | "boost" | "slingshot" | "stunned" | "clank"

export type FlameLook = {
	Position: Vector2,
	Facing: Vector2,
	FlameReach: number,
	FlameDirection: Vector2,
	IsBoosting: boolean,
	IsSlingshotting: boolean,
	IsStunned: boolean,
	Throttle: number?,
	IsInOrbit: boolean?,
}

-- Heat ladders from docs/art-guide.md (edge, mid, core) plus metallic clank flash.
local HEAT: { [FlameState]: { Color3 } } = {
	soft = { Color3.fromHex("#ff4a1c"), Color3.fromHex("#ff9a1f"), Color3.fromHex("#ffe066") },
	boost = { Color3.fromHex("#ffa030"), Color3.fromHex("#ffe08a"), Color3.fromHex("#ffffff") },
	slingshot = { Color3.fromHex("#2f7dff"), Color3.fromHex("#7fe6ff"), Color3.fromHex("#f2ffff") },
	stunned = { Color3.fromHex("#40444d"), Color3.fromHex("#6a707c"), Color3.fromHex("#9aa0aa") },
	clank = { Color3.fromHex("#ffe066"), Color3.fromHex("#fff6cf"), Color3.fromHex("#ffffff") },
}

local BAND_SPECS = {
	{ name = "Edge", scale = 1.00, width = Vector2.new(1.18, 0.68), liftOffset = -0.03 },
	{ name = "Mid", scale = 0.72, width = Vector2.new(0.82, 0.50), liftOffset = 0.00 },
	{ name = "Core", scale = 0.44, width = Vector2.new(0.46, 0.34), liftOffset = 0.03 },
}

local SEG_FRACTIONS = { 0.38, 0.34, 0.28 } -- sum to 1.00 so the outer tip lands at FlameReach
local SEG_TAPER = { 0.92, 1.00, 0.66 }

type BandSegments = {
	parts: { BasePart },
	scale: number,
	width: Vector2,
	liftOffset: number,
}

local FlameView = {}
FlameView.__index = FlameView

export type FlameView = typeof(setmetatable(
	{} :: {
		_folder: Folder,
		_bands: { BandSegments },
		_nozzle: BasePart,
		_emitter: ParticleEmitter,
		_dir1: Vector2?,
		_dir2: Vector2?,
		_state: FlameState?,
		_clankTimer: number,
		_clock: number,
		_connections: { Signal.Connection },
	},
	FlameView
))

local function safeUnit(v: Vector2, fallback: Vector2): Vector2
	if v.Magnitude > 1e-5 then
		return v.Unit
	end
	if fallback.Magnitude > 1e-5 then
		return fallback.Unit
	end
	return Vector2.new(0, -1)
end

local function stepLagDir(current: Vector2, target: Vector2, rate: number, dt: number): Vector2
	local alpha = 1 - math.exp(-rate * dt)
	local blended = current:Lerp(target, alpha)
	local unit = safeUnit(blended, target)
	-- Clamp lag angle so sudden orbit/boost snaps bend gracefully instead of folding back.
	local dot = math.clamp(unit:Dot(target), -1, 1)
	local angle = math.acos(dot)
	if angle > MAX_BEND_RAD then
		local cross = target.X * unit.Y - target.Y * unit.X
		local sign = if cross >= 0 then 1 else -1
		local c = math.cos(MAX_BEND_RAD * sign)
		local s = math.sin(MAX_BEND_RAD * sign)
		unit = Vector2.new(target.X * c - target.Y * s, target.X * s + target.Y * c)
	end
	return unit
end

local function makeSegmentPart(name: string, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = FLAME_TRANSPARENCY
	part:SetAttribute("NoOutline", true)

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part

	part.Parent = parent
	return part
end

function FlameView.new(parent: Instance): FlameView
	local folder = Instance.new("Folder")
	folder.Name = "ShipFlame"

	local bands: { BandSegments } = {}
	for _, spec in BAND_SPECS do
		local parts: { BasePart } = {}
		for seg = 1, 3 do
			table.insert(parts, makeSegmentPart(`{spec.name}{seg}`, folder))
		end
		table.insert(bands, {
			parts = parts,
			scale = spec.scale,
			width = spec.width,
			liftOffset = spec.liftOffset,
		})
	end

	local nozzle = Instance.new("Part")
	nozzle.Name = "FlameNozzle"
	nozzle.Anchored = true
	nozzle.CanCollide = false
	nozzle.CanTouch = false
	nozzle.CanQuery = false
	nozzle.CastShadow = false
	nozzle.Transparency = 1
	nozzle.Size = Vector3.new(0.4, 0.4, 0.4)
	nozzle:SetAttribute("NoOutline", true)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparks"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Brightness = 2
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.Lifetime = NumberRange.new(0.14, 0.25)
	emitter.Speed = NumberRange.new(8, 18)
	emitter.SpreadAngle = Vector2.new(14, 10)
	emitter.Drag = 3
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.34),
		NumberSequenceKeypoint.new(0.6, 0.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Rate = 0
	emitter.Parent = nozzle
	nozzle.Parent = folder

	folder.Parent = parent

	return setmetatable({
		_folder = folder,
		_bands = bands,
		_nozzle = nozzle :: BasePart,
		_emitter = emitter,
		_dir1 = nil :: Vector2?,
		_dir2 = nil :: Vector2?,
		_state = nil :: FlameState?,
		_clankTimer = 0,
		_clock = 0,
		_connections = {} :: { Signal.Connection },
	}, FlameView)
end

-- Flashes the white-gold metallic clang state briefly and pops nozzle sparks.
function FlameView.TriggerClank(self: FlameView)
	self._clankTimer = CLANK_DURATION
	self._emitter:Emit(8)
end

-- Subscribes to RockClanged so clanging off Iron or boss armour flashes the plume.
function FlameView.Listen(self: FlameView, events: RunEvents.RunEvents)
	table.insert(
		self._connections,
		events.RockClanged:Connect(function()
			self:TriggerClank()
		end)
	)
end

function FlameView.Update(self: FlameView, ship: FlameLook, dt: number?, active: boolean?)
	local stepDt = dt or 0
	local isActive = if active == nil then true else active
	if isActive and stepDt > 0 then
		self._clock += stepDt
		if self._clankTimer > 0 then
			self._clankTimer = math.max(0, self._clankTimer - stepDt)
		end
	end

	local dir0 = safeUnit(ship.FlameDirection, -ship.Facing)
	if not self._dir1 or not self._dir2 or stepDt <= 0 or not isActive then
		self._dir1 = self._dir1 or dir0
		self._dir2 = self._dir2 or dir0
		if stepDt <= 0 then
			self._dir1 = dir0
			self._dir2 = dir0
		end
	else
		self._dir1 = stepLagDir(self._dir1, dir0, 18, stepDt)
		self._dir2 = stepLagDir(self._dir2, self._dir1 :: Vector2, 12, stepDt)
	end
	local dir1 = self._dir1 :: Vector2
	local dir2 = self._dir2 :: Vector2

	local state: FlameState = if self._clankTimer > 0
		then "clank"
		elseif ship.IsStunned then "stunned"
		elseif ship.IsSlingshotting then "slingshot"
		elseif ship.IsBoosting then "boost"
		else "soft"
	local heat = HEAT[state]

	local totalLength = math.max(PILOT_LENGTH, ship.FlameReach - FLAME_START)
	local throttle = ship.Throttle or math.clamp((ship.FlameReach - 4) / 9, 0, 1)
	local powerScale =
		math.clamp(0.76 + throttle * 0.28 + (if ship.IsBoosting or ship.IsSlingshotting then 0.14 else 0), 0.72, 1.2)
	local orbitScale = if ship.IsInOrbit then ORBIT_WIDTH_SCALE else 1
	local flutter = if isActive and stepDt > 0 then math.sin(self._clock * 34) * 0.035 else 0

	local p0 = ship.Position + dir0 * FLAME_START
	for i, band in self._bands do
		local bandLength = totalLength * band.scale
		local c1 = bandLength * SEG_FRACTIONS[1]
		local c2 = bandLength * SEG_FRACTIONS[2]
		local c3 = bandLength * SEG_FRACTIONS[3]

		local p1 = p0 + dir0 * c1
		local p2 = p1 + dir1 * c2
		local p3 = p2 + dir2 * c3

		local wx = band.width.X * powerScale * orbitScale * (1 + flutter)
		local wy = band.width.Y * powerScale * (1 - flutter * 0.6)
		local lift = LIFT + band.liftOffset

		-- Seg 1: starts flush at p0, overlaps past p1
		local z1 = c1 * 1.20
		local seg1 = band.parts[1]
		seg1.Size = Vector3.new(wx * SEG_TAPER[1], wy * SEG_TAPER[1], z1)
		seg1.CFrame = ArenaSpace.CFrameAt(p0 + dir0 * (z1 * 0.5), dir0, lift)

		-- Seg 2: bridges p1..p2 along dir1
		local z2 = c2 * 1.34
		local seg2 = band.parts[2]
		seg2.Size = Vector3.new(wx * SEG_TAPER[2], wy * SEG_TAPER[2], z2)
		seg2.CFrame = ArenaSpace.CFrameAt((p1 + p2) * 0.5, dir1, lift)

		-- Seg 3: tapers to p3 so the outer tip sits right at ship.FlameReach
		local z3 = c3 * 1.24
		local seg3 = band.parts[3]
		seg3.Size = Vector3.new(wx * SEG_TAPER[3], wy * SEG_TAPER[3], z3)
		seg3.CFrame = ArenaSpace.CFrameAt(p3 - dir2 * (z3 * 0.5), dir2, lift)

		if state ~= self._state then
			local color = heat[i]
			seg1.Color = color
			seg2.Color = color
			seg3.Color = color
		end
	end

	self._nozzle.CFrame = ArenaSpace.CFrameAt(p0, dir0, LIFT)
	if state ~= self._state then
		self._emitter.Color = ColorSequence.new(heat[3], heat[1])
		self._state = state
	end

	if not isActive then
		self._emitter.Rate = 0
	elseif state == "stunned" then
		self._emitter.Rate = 4
		self._emitter.Speed = NumberRange.new(3, 7)
		self._emitter.SpreadAngle = Vector2.new(26, 18)
	else
		local boostBonus = if ship.IsBoosting or ship.IsSlingshotting then 14 else 0
		self._emitter.Rate = math.floor(5 + throttle * 15 + boostBonus)
		local baseSpeed = math.max(8, totalLength * 1.55)
		self._emitter.Speed = NumberRange.new(baseSpeed * 0.7, baseSpeed * 1.15)
		self._emitter.SpreadAngle = Vector2.new(if ship.IsInOrbit then 26 else 14, 10)
	end
end

function FlameView.Destroy(self: FlameView)
	for _, conn in self._connections do
		conn:Disconnect()
	end
	table.clear(self._connections)
	self._folder:Destroy()
end

return FlameView
