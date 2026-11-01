--!strict
--[[
	VfxView: pooled Toy Box visual effects driven purely by RunEvents and snapshots (#44).

	    local vfx = VfxView.new(folder)
	    vfx:Listen(run.Events)
	    vfx:Update(snapshot, tuning, dt, playing) -- every frame, after the Run steps

	Covers:
	  - Break burst: 3D tumbling debris chunks tinted to the rock + Neon sparks + pop ring
	  - PERFECT flash: gold/white bloom flash + starburst + Shockwave prime ring (when stacked)
	  - Sparks: pink prime pop, cyan-pink orbit flare pop, molten core-crack burst
	  - Ignition rings: nozzle shock ring on boost, slingshot and orbit lock
	  - Clang & bump: white-gold metallic cross-sparks + shock ring at contact point
	  - Planet & boss impact: fiery shockwave + surface sparks
	  - Shield hit ripple: cyan bead wave sweeping outward from the impact angle
	  - Slingshot trail & arena edge ripple: electric blue ribbon + rim arc ripple

	Every instance is pre-allocated once per session and parked off-screen when idle,
	so waves and boss fights trigger zero Instance.new / Destroy / Parent churn on phones.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local Districts = require(KngChak.Data.Districts)
local Rock = require(KngChak.Rocks.Rock)
local Run = require(KngChak.Run.Run)
local RunEvents = require(KngChak.Run.RunEvents)
local Signal = require(KngChak.Util.Signal)
local Threat = require(KngChak.Rocks.Threat)
local Tuning = require(KngChak.Run.Tuning)

local HIDDEN_CF = CFrame.new(0, -500, 0)
local FLAT_RING_ROT = CFrame.Angles(math.pi / 2, 0, 0)

-- Pool budgets tuned for low-end mobile phones:
local DEBRIS_POOL = 24
local SPARK_POOL = 44
local RING_POOL = 14
local FLASH_POOL = 6
local ARC_POOL = 6
local ARC_BEADS = 7

local ROCK_LIFT = 2.0
local SHIP_LIFT = 3.0
local RING_LIFT = 1.2
local SHIELD_GAP = 1.2

local COLOR_GOLD = Color3.fromHex("#ffe066")
local COLOR_WHITE = Color3.fromHex("#ffffff")
local COLOR_AMBER = Color3.fromHex("#ffa030")
local COLOR_ORANGE = Color3.fromHex("#ff6a1f")
local COLOR_RED = Color3.fromHex("#ff4d5e")
local COLOR_BLUE = Color3.fromHex("#2f7dff")
local COLOR_CYAN = Color3.fromHex("#7fe6ff")
local COLOR_ORBIT = Color3.fromHex("#6ff3ff")
local COLOR_SHIELD = Color3.fromHex("#bff6ff")

type DebrisPart = {
	part: BasePart,
	isBody: boolean,
	baseSize: Vector3,
	localRot: CFrame,
	localPos: Vector3,
}

type DebrisSlot = {
	parts: { DebrisPart },
	active: boolean,
	age: number,
	duration: number,
	pos: Vector2,
	vel: Vector2,
	lift: number,
	velY: number,
	baseScale: number,
	rot: Vector3,
	spin: Vector3,
}

type SparkSlot = {
	part: BasePart,
	active: boolean,
	age: number,
	duration: number,
	pos: Vector2,
	vel: Vector2,
	drag: number,
	lift: number,
	width: number,
	length: number,
}

type RingSlot = {
	adorn: CylinderHandleAdornment,
	active: boolean,
	age: number,
	duration: number,
	pos: Vector2,
	lift: number,
	r0: number,
	r1: number,
	thickness: number,
	startAlpha: number,
}

type FlashSlot = {
	part: BasePart,
	active: boolean,
	age: number,
	duration: number,
	pos: Vector2,
	lift: number,
	s0: number,
	s1: number,
}

type ArcSlot = {
	beads: { BasePart },
	active: boolean,
	age: number,
	duration: number,
	centre: Vector2,
	radius: number,
	lift: number,
	angle: number,
	span0: number,
	span1: number,
}

local VfxView = {}
VfxView.__index = VfxView

export type VfxView = typeof(setmetatable(
	{} :: {
		_folder: Folder,
		_anchor: BasePart,
		_debris: { DebrisSlot },
		_nextDebris: number,
		_sparks: { SparkSlot },
		_nextSpark: number,
		_rings: { RingSlot },
		_nextRing: number,
		_flashes: { FlashSlot },
		_nextFlash: number,
		_arcs: { ArcSlot },
		_nextArc: number,
		_trailCarrier: BasePart,
		_trail: Trail,
		_rng: Random,
		_shipPos: Vector2,
		_shipFacing: Vector2,
		_shipFlameDir: Vector2,
		_bossPos: Vector2,
		_planetRadius: number,
		_arenaRadius: number,
		_shockwaveRadius: number,
		_lastImpactAngle: number,
		_edgeRippleCooldown: number,
		_connections: { Signal.Connection },
	},
	VfxView
))

local function makeNeonPart(name: string, parent: Instance, sphereMesh: boolean, ballShape: boolean): BasePart
	local part = Instance.new("Part")
	part.Name = name
	if ballShape then
		part.Shape = Enum.PartType.Ball
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.CFrame = HIDDEN_CF
	part:SetAttribute("NoOutline", true)
	if sphereMesh then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	part.Parent = parent
	return part
end

local function collectDebrisPrefabs(): { Model }
	local list: { Model } = {}
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local debrisFolder = if assets then assets:FindFirstChild("Debris") else nil
	if debrisFolder then
		for _, child in debrisFolder:GetChildren() do
			if child:IsA("Model") then
				table.insert(list, child)
			end
		end
		table.sort(list, function(a: Model, b: Model): boolean
			return a.Name < b.Name
		end)
	end
	return list
end

local function buildDebrisSlot(prefab: Model?, index: number, parent: Instance): DebrisSlot
	local parts: { DebrisPart } = {}
	if prefab then
		local clone = prefab:Clone()
		clone.Name = `Debris{index}`
		for _, desc in clone:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.Anchored = true
				desc.CanCollide = false
				desc.CanTouch = false
				desc.CanQuery = false
				desc.CastShadow = false
				desc:SetAttribute("NoOutline", true)
				local localPos = desc.CFrame.Position
				local localRot = desc.CFrame.Rotation
				local baseSize = desc.Size
				desc.Transparency = 1
				desc.CFrame = HIDDEN_CF
				desc.Parent = parent
				table.insert(parts, {
					part = desc,
					isBody = string.sub(desc.Name, 1, 4) == "Body",
					baseSize = baseSize,
					localRot = localRot,
					localPos = localPos,
				})
			end
		end
		clone:Destroy()
	else
		local fallback = Instance.new("Part")
		fallback.Name = `Debris{index}`
		fallback.Anchored = true
		fallback.CanCollide = false
		fallback.CanTouch = false
		fallback.CanQuery = false
		fallback.CastShadow = false
		fallback.Material = Enum.Material.SmoothPlastic
		fallback.Size = Vector3.new(0.9, 0.65, 0.8)
		fallback.Transparency = 1
		fallback.CFrame = HIDDEN_CF
		fallback:SetAttribute("NoOutline", true)
		fallback.Parent = parent
		table.insert(parts, {
			part = fallback :: BasePart,
			isBody = true,
			baseSize = fallback.Size,
			localRot = CFrame.identity,
			localPos = Vector3.zero,
		})
	end

	return {
		parts = parts,
		active = false,
		age = 0,
		duration = 0.5,
		pos = Vector2.zero,
		vel = Vector2.zero,
		lift = ROCK_LIFT,
		velY = 0,
		baseScale = 1,
		rot = Vector3.zero,
		spin = Vector3.zero,
	}
end

function VfxView.new(parent: Instance): VfxView
	local folder = Instance.new("Folder")
	folder.Name = "Vfx"

	local anchor = Instance.new("Part")
	anchor.Name = "AdornAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.identity
	anchor:SetAttribute("NoOutline", true)
	anchor.Parent = folder

	local prefabs = collectDebrisPrefabs()
	local debris: { DebrisSlot } = {}
	for i = 1, DEBRIS_POOL do
		local prefab = if #prefabs > 0 then prefabs[(i - 1) % #prefabs + 1] else nil
		table.insert(debris, buildDebrisSlot(prefab, i, folder))
	end

	local sparks: { SparkSlot } = {}
	for i = 1, SPARK_POOL do
		table.insert(sparks, {
			part = makeNeonPart(`Spark{i}`, folder, true, false),
			active = false,
			age = 0,
			duration = 0.25,
			pos = Vector2.zero,
			vel = Vector2.zero,
			drag = 5,
			lift = ROCK_LIFT,
			width = 0.24,
			length = 0.9,
		})
	end

	local rings: { RingSlot } = {}
	for i = 1, RING_POOL do
		local adorn = Instance.new("CylinderHandleAdornment")
		adorn.Name = `Ring{i}`
		adorn.Adornee = anchor
		adorn.Angle = 360
		adorn.Height = 0.18
		adorn.Shading = Enum.AdornShading.Default
		adorn.Visible = false
		adorn.Transparency = 1
		adorn.Parent = folder
		table.insert(rings, {
			adorn = adorn,
			active = false,
			age = 0,
			duration = 0.3,
			pos = Vector2.zero,
			lift = RING_LIFT,
			r0 = 0.5,
			r1 = 3.0,
			thickness = 0.35,
			startAlpha = 0.05,
		})
	end

	local flashes: { FlashSlot } = {}
	for i = 1, FLASH_POOL do
		table.insert(flashes, {
			part = makeNeonPart(`Flash{i}`, folder, false, true),
			active = false,
			age = 0,
			duration = 0.18,
			pos = Vector2.zero,
			lift = ROCK_LIFT,
			s0 = 1.0,
			s1 = 3.2,
		})
	end

	local arcs: { ArcSlot } = {}
	for i = 1, ARC_POOL do
		local beads: { BasePart } = {}
		for b = 1, ARC_BEADS do
			table.insert(beads, makeNeonPart(`Arc{i}_{b}`, folder, true, false))
		end
		table.insert(arcs, {
			beads = beads,
			active = false,
			age = 0,
			duration = 0.32,
			centre = Vector2.zero,
			radius = 11.2,
			lift = 0.7,
			angle = 0,
			span0 = 0.18,
			span1 = 0.65,
		})
	end

	-- Slingshot ribbon trail carrier
	local carrier = Instance.new("Part")
	carrier.Name = "SlingshotTrailCarrier"
	carrier.Anchored = true
	carrier.CanCollide = false
	carrier.CanTouch = false
	carrier.CanQuery = false
	carrier.CastShadow = false
	carrier.Transparency = 1
	carrier.Size = Vector3.one * 0.2
	carrier.CFrame = HIDDEN_CF
	carrier:SetAttribute("NoOutline", true)

	local attLeft = Instance.new("Attachment")
	attLeft.Position = Vector3.new(-0.62, 0, 0)
	attLeft.Parent = carrier
	local attRight = Instance.new("Attachment")
	attRight.Position = Vector3.new(0.62, 0, 0)
	attRight.Parent = carrier

	local trail = Instance.new("Trail")
	trail.Name = "SlingshotTrail"
	trail.Attachment0 = attLeft
	trail.Attachment1 = attRight
	trail.Color = ColorSequence.new(COLOR_CYAN, COLOR_BLUE)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.55, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Brightness = 2
	trail.Lifetime = 0.26
	trail.MinLength = 0.2
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = carrier
	carrier.Parent = folder

	folder.Parent = parent

	return setmetatable({
		_folder = folder,
		_anchor = anchor :: BasePart,
		_debris = debris,
		_nextDebris = 1,
		_sparks = sparks,
		_nextSpark = 1,
		_rings = rings,
		_nextRing = 1,
		_flashes = flashes,
		_nextFlash = 1,
		_arcs = arcs,
		_nextArc = 1,
		_trailCarrier = carrier :: BasePart,
		_trail = trail,
		_rng = Random.new(),
		_shipPos = Vector2.zero,
		_shipFacing = Vector2.new(0, -1),
		_shipFlameDir = Vector2.new(0, 1),
		_bossPos = Vector2.new(0, 50),
		_planetRadius = 10,
		_arenaRadius = 66,
		_shockwaveRadius = 0,
		_lastImpactAngle = math.pi / 2,
		_edgeRippleCooldown = 0,
		_connections = {} :: { Signal.Connection },
	}, VfxView)
end

local function spawnRing(
	self: VfxView,
	pos: Vector2,
	lift: number,
	r0: number,
	r1: number,
	thickness: number,
	duration: number,
	color: Color3,
	startAlpha: number?
)
	local slot = self._rings[self._nextRing]
	self._nextRing = self._nextRing % #self._rings + 1
	slot.active = true
	slot.age = 0
	slot.duration = duration
	slot.pos = pos
	slot.lift = lift
	slot.r0 = r0
	slot.r1 = r1
	slot.thickness = thickness
	slot.startAlpha = startAlpha or 0.05
	slot.adorn.Color3 = color
	slot.adorn.Radius = r0
	slot.adorn.InnerRadius = math.max(0.05, r0 - thickness)
	slot.adorn.Transparency = slot.startAlpha
	slot.adorn.CFrame = CFrame.new(ArenaSpace.ToWorld(pos, lift)) * FLAT_RING_ROT
	slot.adorn.Visible = true
end

local function spawnFlash(
	self: VfxView,
	pos: Vector2,
	lift: number,
	s0: number,
	s1: number,
	duration: number,
	color: Color3
)
	local slot = self._flashes[self._nextFlash]
	self._nextFlash = self._nextFlash % #self._flashes + 1
	slot.active = true
	slot.age = 0
	slot.duration = duration
	slot.pos = pos
	slot.lift = lift
	slot.s0 = s0
	slot.s1 = s1
	slot.part.Color = color
	slot.part.Size = Vector3.one * s0
	slot.part.Transparency = 0.05
	slot.part.CFrame = CFrame.new(ArenaSpace.ToWorld(pos, lift))
end

local function spawnSpark(
	self: VfxView,
	pos: Vector2,
	vel: Vector2,
	lift: number,
	width: number,
	length: number,
	duration: number,
	color: Color3,
	drag: number?
)
	local slot = self._sparks[self._nextSpark]
	self._nextSpark = self._nextSpark % #self._sparks + 1
	slot.active = true
	slot.age = 0
	slot.duration = duration
	slot.pos = pos
	slot.vel = vel
	slot.drag = drag or 5.5
	slot.lift = lift
	slot.width = width
	slot.length = length
	slot.part.Color = color
	slot.part.Size = Vector3.new(width, width, length)
	slot.part.Transparency = 0
	slot.part.CFrame = ArenaSpace.CFrameAt(pos, vel, lift)
end

local function burstSparks(
	self: VfxView,
	pos: Vector2,
	count: number,
	minSpeed: number,
	maxSpeed: number,
	lift: number,
	width: number,
	length: number,
	duration: number,
	primary: Color3,
	secondary: Color3?,
	baseAngle: number?,
	coneHalf: number?
)
	local rng = self._rng
	for i = 1, count do
		local angle: number
		if baseAngle and coneHalf then
			angle = baseAngle + rng:NextNumber(-coneHalf, coneHalf)
		else
			angle = (i - 1) / count * 2 * math.pi + rng:NextNumber(-0.25, 0.25)
		end
		local speed = rng:NextNumber(minSpeed, maxSpeed)
		local vel = Vector2.new(math.cos(angle), math.sin(angle)) * speed
		local color = if secondary and i % 2 == 0 then secondary else primary
		spawnSpark(self, pos, vel, lift, width, length, duration * rng:NextNumber(0.85, 1.15), color)
	end
end

local function spawnDebrisBurst(
	self: VfxView,
	pos: Vector2,
	radius: number,
	tint: Color3,
	count: number,
	speedMult: number
)
	local rng = self._rng
	for i = 1, count do
		local slot = self._debris[self._nextDebris]
		self._nextDebris = self._nextDebris % #self._debris + 1
		local angle = (i - 1) / count * 2 * math.pi + rng:NextNumber(-0.35, 0.35)
		local speed = rng:NextNumber(7, 15) * speedMult
		local scale = math.clamp(radius * rng:NextNumber(0.34, 0.48), 0.35, 1.05)

		slot.active = true
		slot.age = 0
		slot.duration = rng:NextNumber(0.42, 0.58)
		slot.pos = pos + Vector2.new(math.cos(angle), math.sin(angle)) * (radius * 0.25)
		slot.vel = Vector2.new(math.cos(angle), math.sin(angle)) * speed
		slot.lift = ROCK_LIFT
		slot.velY = rng:NextNumber(3.5, 6.5)
		slot.baseScale = scale
		slot.rot = Vector3.new(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
		slot.spin = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-9, 9), rng:NextNumber(-9, 9))

		for _, dp in slot.parts do
			if dp.isBody then
				dp.part.Color = tint
			end
			dp.part.Transparency = 0
		end
	end
end

local function spawnArc(
	self: VfxView,
	centre: Vector2,
	radius: number,
	angle: number,
	span0: number,
	span1: number,
	duration: number,
	color: Color3,
	lift: number
)
	local slot = self._arcs[self._nextArc]
	self._nextArc = self._nextArc % #self._arcs + 1
	slot.active = true
	slot.age = 0
	slot.duration = duration
	slot.centre = centre
	slot.radius = radius
	slot.lift = lift
	slot.angle = angle
	slot.span0 = span0
	slot.span1 = span1
	for _, bead in slot.beads do
		bead.Color = color
		bead.Transparency = 0.05
	end
end

function VfxView.Listen(self: VfxView, events: RunEvents.RunEvents)
	local function connect(sig: Signal.Signal, fn: (...any) -> ())
		table.insert(self._connections, sig:Connect(fn))
	end

	connect(events.RockBroken, function(rock: Rock.Rock, cause: string)
		local isPerfect = cause == "Perfect"
		local isPrimedBreak = cause == "PushBreak" or isPerfect
		local ringColor = if isPerfect
			then COLOR_GOLD
			elseif rock.IsPrimed then Districts.Primed
			else (rock.Type.Glow or rock.Type.Tint)

		spawnDebrisBurst(
			self,
			rock.Position,
			rock.Type.Radius,
			rock.Type.Tint,
			if isPerfect then 5 else 4,
			if isPerfect then 1.35 else 1.0
		)
		spawnRing(
			self,
			rock.Position,
			ROCK_LIFT - 0.3,
			rock.Type.Radius * 0.55,
			rock.Type.Radius * (if isPerfect then 3.2 else 2.4),
			if isPerfect then 0.48 else 0.34,
			if isPerfect then 0.34 else 0.26,
			ringColor
		)
		burstSparks(
			self,
			rock.Position,
			if isPerfect then 10 else 6,
			9,
			19,
			ROCK_LIFT + 0.2,
			0.26,
			1.05,
			0.26,
			ringColor,
			if isPrimedBreak then Districts.Primed else COLOR_WHITE
		)
		spawnFlash(self, rock.Position, ROCK_LIFT, rock.Type.Radius * 0.9, rock.Type.Radius * 2.2, 0.16, ringColor)

		-- Shockwave upgrade ring: show the exact chain-prime radius when breaking a primed rock!
		if isPrimedBreak and self._shockwaveRadius > 0 then
			local reach = rock.Type.Radius + self._shockwaveRadius
			spawnRing(self, rock.Position, ROCK_LIFT - 0.4, rock.Type.Radius, reach, 0.42, 0.34, Districts.Primed, 0.08)
		end
	end)

	connect(events.RockSplit, function(rock: Rock.Rock)
		spawnRing(
			self,
			rock.Position,
			ROCK_LIFT - 0.2,
			rock.Type.Radius * 0.6,
			rock.Type.Radius * 2.6,
			0.36,
			0.28,
			rock.Type.Tint
		)
	end)

	connect(events.Perfect, function(rock: Rock.Rock)
		spawnFlash(self, rock.Position, ROCK_LIFT + 0.3, 1.2, rock.Type.Radius * 3.8, 0.24, COLOR_WHITE)
		spawnRing(self, rock.Position, ROCK_LIFT, 0.7, rock.Type.Radius * 4.2, 0.55, 0.40, COLOR_GOLD, 0)
		burstSparks(self, rock.Position, 10, 14, 28, ROCK_LIFT + 0.4, 0.32, 1.45, 0.34, COLOR_GOLD, Districts.Primed)
	end)

	connect(events.CoreCracked, function(rock: Rock.Rock)
		spawnFlash(self, rock.Position, ROCK_LIFT + 0.4, 1.5, rock.Type.Radius * 4.2, 0.26, COLOR_GOLD)
		spawnRing(self, rock.Position, ROCK_LIFT, 0.9, rock.Type.Radius * 4.6, 0.6, 0.42, COLOR_AMBER, 0)
		burstSparks(self, rock.Position, 12, 14, 28, ROCK_LIFT + 0.4, 0.34, 1.5, 0.36, COLOR_GOLD, COLOR_WHITE)
	end)

	connect(events.RockPrimed, function(rock: Rock.Rock)
		spawnRing(
			self,
			rock.Position,
			ROCK_LIFT - 0.2,
			rock.Type.Radius * 0.7,
			rock.Type.Radius * 1.9,
			0.28,
			0.22,
			Districts.Primed,
			0.12
		)
		burstSparks(self, rock.Position, 6, 6, 13, ROCK_LIFT + 0.2, 0.22, 0.85, 0.22, Districts.Primed, COLOR_GOLD)
	end)

	connect(events.RockFlared, function(rock: Rock.Rock)
		spawnRing(
			self,
			rock.Position,
			ROCK_LIFT - 0.1,
			rock.Type.Radius * 0.6,
			rock.Type.Radius * 2.2,
			0.34,
			0.26,
			COLOR_ORBIT,
			0.08
		)
		burstSparks(self, rock.Position, 8, 7, 15, ROCK_LIFT + 0.3, 0.24, 0.95, 0.26, COLOR_ORBIT, Districts.Primed)
	end)

	connect(events.Boosted, function()
		local nozzle = self._shipPos + self._shipFlameDir * 1.5
		spawnRing(self, nozzle, SHIP_LIFT - 0.2, 0.5, 3.2, 0.36, 0.22, COLOR_AMBER, 0.08)
		burstSparks(self, nozzle, 5, 8, 16, SHIP_LIFT, 0.22, 0.9, 0.18, COLOR_GOLD, COLOR_AMBER)
	end)

	connect(events.Slingshot, function()
		local at = self._shipPos - self._shipFacing * 1.2
		spawnRing(self, at, SHIP_LIFT - 0.2, 0.7, 4.2, 0.44, 0.28, COLOR_CYAN, 0.04)
		spawnFlash(self, at, SHIP_LIFT, 0.9, 2.6, 0.16, COLOR_WHITE)
		burstSparks(self, at, 8, 10, 22, SHIP_LIFT + 0.1, 0.26, 1.2, 0.24, COLOR_CYAN, COLOR_WHITE)
	end)

	connect(events.OrbitLocked, function()
		spawnRing(self, self._shipPos, SHIP_LIFT - 0.3, 0.6, 2.6, 0.28, 0.20, COLOR_ORBIT, 0.15)
	end)

	connect(events.RockClanged, function(rock: Rock.Rock)
		local dir = rock.Position - self._shipPos
		local contact = if dir.Magnitude > 1e-4
			then self._shipPos + dir.Unit * math.min(dir.Magnitude, 2.2)
			else self._shipPos + self._shipFacing * 2.0
		spawnFlash(self, contact, SHIP_LIFT, 0.8, 2.4, 0.14, COLOR_WHITE)
		spawnRing(self, contact, SHIP_LIFT - 0.1, 0.4, 2.8, 0.36, 0.20, COLOR_GOLD, 0.04)
		burstSparks(self, contact, 8, 11, 22, SHIP_LIFT + 0.2, 0.26, 1.15, 0.22, COLOR_WHITE, COLOR_GOLD)
	end)

	connect(events.ShipBumped, function(rock: Rock.Rock)
		local contact = (self._shipPos + rock.Position) * 0.5
		spawnRing(self, contact, SHIP_LIFT - 0.2, 0.5, 2.7, 0.34, 0.22, COLOR_ORANGE, 0.08)
		burstSparks(self, contact, 6, 8, 17, SHIP_LIFT, 0.24, 0.95, 0.22, COLOR_ORANGE, COLOR_RED)
	end)

	connect(events.PlanetHit, function(rock: Rock.Rock)
		local landing = Threat.ImpactPoint(rock, self._planetRadius)
		local angle = math.atan2(landing.Y, landing.X)
		self._lastImpactAngle = angle
		spawnFlash(self, landing, 1.4, 1.2, 4.2, 0.24, COLOR_ORANGE)
		spawnRing(self, landing, 1.0, 0.8, 5.2, 0.52, 0.36, COLOR_RED, 0.04)
		burstSparks(self, landing, 10, 9, 21, 1.5, 0.28, 1.25, 0.32, COLOR_RED, COLOR_AMBER, angle, 1.15)
	end)

	connect(events.BossHit, function()
		local angle = if self._bossPos.Magnitude > 1e-4
			then math.atan2(self._bossPos.Y, self._bossPos.X)
			else math.pi / 2
		self._lastImpactAngle = angle
		local landing = Vector2.new(math.cos(angle), math.sin(angle)) * self._planetRadius
		spawnFlash(self, landing, 1.8, 2.0, 7.2, 0.32, COLOR_GOLD)
		spawnRing(self, landing, 1.2, 1.4, 8.6, 0.75, 0.46, COLOR_RED, 0)
		burstSparks(self, landing, 14, 12, 26, 1.8, 0.34, 1.5, 0.38, COLOR_RED, COLOR_GOLD, angle, 1.35)
	end)

	connect(events.ShieldChanged, function(_shield: number, delta: number)
		local shieldRadius = self._planetRadius + SHIELD_GAP
		if delta < 0 then
			-- Shield absorbed part or all of a PlanetHit / BossHit right before this event.
			local angle = self._lastImpactAngle
			local hitAt = Vector2.new(math.cos(angle), math.sin(angle)) * shieldRadius
			spawnArc(self, Vector2.zero, shieldRadius, angle, 0.16, 0.88, 0.36, COLOR_SHIELD, 0.8)
			spawnRing(self, hitAt, 0.9, 0.6, 3.8, 0.36, 0.26, COLOR_SHIELD, 0.06)
			burstSparks(self, hitAt, 7, 8, 18, 1.0, 0.24, 1.0, 0.24, COLOR_SHIELD, COLOR_WHITE, angle, 1.1)
		elseif delta > 0 then
			spawnRing(self, Vector2.zero, 0.6, shieldRadius - 0.5, shieldRadius + 1.4, 0.32, 0.30, COLOR_SHIELD, 0.28)
		end
	end)
end

function VfxView.Update(self: VfxView, snapshot: Run.Snapshot, tuning: Tuning.Tuning, dt: number, active: boolean)
	local ship = snapshot.Ship
	self._shipPos = ship.Position
	self._shipFacing = ship.Facing
	self._shipFlameDir = ship.FlameDirection
	if snapshot.Boss then
		self._bossPos = snapshot.Boss.Position
	end
	self._planetRadius = tuning.Arena.PlanetRadius
	self._arenaRadius = tuning.Arena.ArenaRadius
	self._shockwaveRadius = tuning.Combo.ShockwaveRadius

	-- Slingshot trail follows the Lancer's tail continuously
	local tailPos = ship.Position - ship.Facing * 1.1
	self._trailCarrier.CFrame = ArenaSpace.CFrameAt(tailPos, ship.Facing, SHIP_LIFT - 0.15)
	self._trail.Enabled = active and ship.IsSlingshotting

	if not active or dt <= 0 then
		return
	end

	-- Arena edge ripple when the Lancer skims along the outer boundary
	if self._edgeRippleCooldown > 0 then
		self._edgeRippleCooldown = math.max(0, self._edgeRippleCooldown - dt)
	end
	if
		ship.Position.Magnitude >= self._arenaRadius - 0.65
		and ship.Velocity.Magnitude > 4
		and self._edgeRippleCooldown <= 0
	then
		self._edgeRippleCooldown = 0.18
		local edgeAngle = math.atan2(ship.Position.Y, ship.Position.X)
		spawnArc(self, Vector2.zero, self._arenaRadius, edgeAngle, 0.06, 0.26, 0.30, COLOR_CYAN, 0.65)
	end

	-- Step 3D debris chunks
	for _, slot in self._debris do
		if slot.active then
			slot.age += dt
			if slot.age >= slot.duration then
				slot.active = false
				for _, dp in slot.parts do
					dp.part.Transparency = 1
					dp.part.CFrame = HIDDEN_CF
				end
			else
				local t = slot.age / slot.duration
				slot.pos += slot.vel * dt
				slot.vel *= math.exp(-3.2 * dt)
				slot.lift += slot.velY * dt
				slot.velY -= 18 * dt
				slot.rot += slot.spin * dt
				local scale = slot.baseScale * (1 - t * 0.72)
				local fade = if t > 0.65 then (t - 0.65) / 0.35 else 0
				local chunkCF = CFrame.new(ArenaSpace.ToWorld(slot.pos, math.max(0.2, slot.lift)))
					* CFrame.Angles(slot.rot.X, slot.rot.Y, slot.rot.Z)
				for _, dp in slot.parts do
					dp.part.Size = dp.baseSize * scale
					dp.part.Transparency = fade
					dp.part.CFrame = chunkCF * CFrame.new(dp.localPos * scale) * dp.localRot
				end
			end
		end
	end

	-- Step Neon spark streaks
	for _, slot in self._sparks do
		if slot.active then
			slot.age += dt
			if slot.age >= slot.duration then
				slot.active = false
				slot.part.Transparency = 1
				slot.part.CFrame = HIDDEN_CF
			else
				local t = slot.age / slot.duration
				slot.pos += slot.vel * dt
				slot.vel *= math.exp(-slot.drag * dt)
				local shrink = 1 - t * 0.75
				slot.part.Size =
					Vector3.new(slot.width * shrink, slot.width * shrink, math.max(0.15, slot.length * shrink))
				slot.part.Transparency = t * t
				slot.part.CFrame = ArenaSpace.CFrameAt(slot.pos, slot.vel, slot.lift)
			end
		end
	end

	-- Step hollow shockwave rings
	for _, slot in self._rings do
		if slot.active then
			slot.age += dt
			if slot.age >= slot.duration then
				slot.active = false
				slot.adorn.Visible = false
			else
				local t = slot.age / slot.duration
				local ease = 1 - (1 - t) * (1 - t)
				local radius = slot.r0 + (slot.r1 - slot.r0) * ease
				local width = slot.thickness * (1 - t * 0.65)
				slot.adorn.Radius = radius
				slot.adorn.InnerRadius = math.max(0.05, radius - width)
				slot.adorn.Transparency = slot.startAlpha + (1 - slot.startAlpha) * t
			end
		end
	end

	-- Step Neon bloom flashes
	for _, slot in self._flashes do
		if slot.active then
			slot.age += dt
			if slot.age >= slot.duration then
				slot.active = false
				slot.part.Transparency = 1
				slot.part.CFrame = HIDDEN_CF
			else
				local t = slot.age / slot.duration
				local ease = 1 - (1 - t) * (1 - t)
				local s = slot.s0 + (slot.s1 - slot.s0) * ease
				slot.part.Size = Vector3.one * s
				slot.part.Transparency = 0.08 + 0.92 * t
			end
		end
	end

	-- Step curved bead ripples (shield impacts & arena edge skims)
	for _, slot in self._arcs do
		if slot.active then
			slot.age += dt
			if slot.age >= slot.duration then
				slot.active = false
				for _, bead in slot.beads do
					bead.Transparency = 1
					bead.CFrame = HIDDEN_CF
				end
			else
				local t = slot.age / slot.duration
				local ease = 1 - (1 - t) * (1 - t)
				local span = slot.span0 + (slot.span1 - slot.span0) * ease
				local count = #slot.beads
				local segLen = math.max(0.55, (2 * span * slot.radius) / count * 0.92)
				local thick = 0.46 * (1 - t * 0.55)
				for i, bead in slot.beads do
					local frac = (i - 1) / (count - 1) * 2 - 1
					local a = slot.angle + span * frac
					local at = slot.centre + Vector2.new(math.cos(a), math.sin(a)) * slot.radius
					local tangent = Vector2.new(-math.sin(a), math.cos(a))
					local edgeFade = 0.35 * math.abs(frac)
					bead.Size = Vector3.new(thick, thick * 0.8, segLen)
					bead.Transparency = math.clamp(0.05 + t * 0.95 + edgeFade * t, 0, 1)
					bead.CFrame = ArenaSpace.CFrameAt(at, tangent, slot.lift)
				end
			end
		end
	end
end

function VfxView.Destroy(self: VfxView)
	for _, conn in self._connections do
		conn:Disconnect()
	end
	table.clear(self._connections)
	self._folder:Destroy()
end

return VfxView
