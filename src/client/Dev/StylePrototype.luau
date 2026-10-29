--!nonstrict
--[[
	PROTOTYPE, throwaway (branch prototype/art-style). Never merge to main.

	Question: what should a brighter, cartoonish, Roblox-feeling Kng Chak look like?
	Three style tiles of the same scene, switchable with the bottom bar or ← / →:

	    A  Toy Box        smooth chunky toys, black outlines, bright sky, drop shadows, slight tilt
	    B  Brick Classic  everything built from studded blocks, classic Roblox, stronger tilt
	    C  Neon Arcade    dark sky, candy-neon glow, colour-coded outlines, straight-down camera

	Scene (arena units, same scale as the game): Ember planet, orbit band, the Lancer
	cruising (soft nose) and boosting (spear), each rock type, and one primed rock.
	Drive it from the command bar too: workspace:SetAttribute("StyleVariant", "B").
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ArenaSpace = require(ReplicatedStorage.KngChak.Arena.ArenaSpace)
local RockTypes = require(ReplicatedStorage.KngChak.Data.RockTypes)

local PLANET_RADIUS = 10
local ORBIT_RADIUS = 14.5

-- The scene layout, shared by every variant.
local SHIP_CRUISE = { at = Vector2.new(-17, 13), facing = Vector2.new(1, -0.35).Unit }
local SHIP_BOOST = { at = Vector2.new(6, 21), facing = Vector2.new(1, 0) }
local ROCKS = {
	{ id = "Shard", at = Vector2.new(21, 7) },
	{ id = "Rock", at = Vector2.new(22, -5) },
	{ id = "Comet", at = Vector2.new(15, -15) },
	{ id = "Iron", at = Vector2.new(2, -21) },
	{ id = "Cluster", at = Vector2.new(-11, -19) },
	{ id = "Gold", at = Vector2.new(-21, -6) },
	{ id = "Rock", at = Vector2.new(15, 21), primed = true },
}
local VIEW_CENTER = Vector2.new(0, -1.5)
local VIEW_HALF_HEIGHT = 28
local FOV = 20

local function hex(s)
	return Color3.fromHex(s)
end

local function part(parent, props)
	local p = Instance.new(props.ClassName or "Part")
	props.ClassName = nil
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function ball(parent, cf, size, color, material, transparency)
	return part(parent, {
		Shape = Enum.PartType.Ball,
		Size = typeof(size) == "number" and Vector3.one * size or Vector3.one * size.X,
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Transparency = transparency or 0,
	})
end

-- An ellipsoid (a ball part can't be stretched, so use a sphere mesh on a block).
local function blob(parent, cf, size, color, material, transparency)
	local p = part(parent, {
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Transparency = transparency or 0,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- A cylinder whose axis runs along local Z (Roblox cylinders run along X).
local function tube(parent, cf, length, diameter, color, material)
	return part(parent, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		CFrame = cf * CFrame.Angles(0, math.rad(90), 0),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

local function model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function outline(target, color, fill, fillTransparency)
	local h = Instance.new("Highlight")
	h.OutlineColor = color
	h.OutlineTransparency = 0
	h.FillColor = fill or color
	h.FillTransparency = fillTransparency or 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = target
	return h
end

local function place(m, at, facing, lift)
	m.WorldPivot = CFrame.identity
	m:PivotTo(ArenaSpace.CFrameAt(at, facing, lift))
end

local function W(x, y, lift)
	return ArenaSpace.ToWorld(Vector2.new(x, y), lift)
end

local rng = Random.new(7)

-- Height of the planet's surface above the play plane, at distance d from its centre.
local function surface(d)
	return math.sqrt(math.max(0, PLANET_RADIUS ^ 2 - d ^ 2))
end

----------------------------------------------------------------------------------------------
-- A · Toy Box
----------------------------------------------------------------------------------------------

local TOY = {
	sky = hex("#3d3ad8"),
	ocean = hex("#2fc4ff"),
	land = hex("#5ee05e"),
	landDark = hex("#3fb34a"),
	ice = hex("#ffffff"),
	orbit = hex("#6ff3ff"),
	body = hex("#ff3b3b"),
	stripe = hex("#ffd400"),
	helmet = hex("#fff1b8"),
	spear = hex("#f4f6ff"),
	fin = hex("#ffffff"),
	grille = hex("#3a3a4a"),
	window = hex("#8fe3ff"),
	soft = { hex("#ff4a1c"), hex("#ff9a1f"), hex("#ffe066") },
	boost = { hex("#ffa030"), hex("#ffe08a"), hex("#ffffff") },
	primed = hex("#ff4fd8"),
	rock = hex("#c98b55"),
	rockDark = hex("#8f5c34"),
	shard = hex("#e8b27a"),
	comet = hex("#c9f7ff"),
	cometTail = hex("#7fe6ff"),
	iron = hex("#7487a3"),
	rivet = hex("#3c4658"),
	cluster = hex("#b25fd0"),
	gold = hex("#ffcf2e"),
}

local function toyShip(parent, boosting)
	local m = model(parent, if boosting then "LancerBoost" else "LancerCruise")
	tube(m, CFrame.new(0, 0, 0), 2.2, 1.25, TOY.body)
	tube(m, CFrame.new(0, 0, 0.25), 0.35, 1.32, TOY.stripe)
	tube(m, CFrame.new(0, 0, 1.25), 0.4, 0.95, TOY.grille)
	ball(m, CFrame.new(0, 0.5, -0.45), 0.55, TOY.window)
	for side = -1, 1, 2 do
		part(m, {
			Size = Vector3.new(0.9, 0.25, 0.8),
			CFrame = CFrame.new(side * 0.85, -0.1, 0.85) * CFrame.Angles(0, math.rad(side * 25), 0),
			Color = TOY.fin,
		})
	end
	if boosting then
		blob(m, CFrame.new(0, 0, -1.7), Vector3.new(0.95, 0.95, 2.2), TOY.spear)
		ball(m, CFrame.new(0, 0, -2.75), 0.35, TOY.body)
	else
		ball(m, CFrame.new(0, 0, -1.1), 1.3, TOY.helmet)
	end
	-- Flame: three nested glowing bands behind the engine.
	local colors = if boosting then TOY.boost else TOY.soft
	local length = if boosting then 6 else 3.2
	for i, color in colors do
		local k = 1 - (i - 1) * 0.28
		blob(
			m,
			CFrame.new(0, 0, 1.45 + length * k / 2),
			Vector3.new(1.1 * k, 0.6 * k, length * k),
			color,
			Enum.Material.Neon,
			0.05
		)
	end
	outline(m, Color3.new(0, 0, 0))
	return m
end

local function toyRock(parent, id, primed)
	local r = RockTypes[id].Radius
	local m = model(parent, id)
	if id == "Rock" then
		ball(m, CFrame.new(), r * 2, TOY.rock)
		for i = 1, 3 do
			local a = i * 2.1
			ball(m, CFrame.new(math.cos(a) * r * 0.75, 0.1, math.sin(a) * r * 0.75), r * 0.9, TOY.rock)
		end
		ball(m, CFrame.new(r * 0.3, r * 0.85, -r * 0.2), r * 0.45, TOY.rockDark)
		ball(m, CFrame.new(-r * 0.35, r * 0.8, r * 0.3), r * 0.3, TOY.rockDark)
	elseif id == "Shard" then
		part(m, {
			Size = Vector3.new(r * 2.2, r, r * 1.1),
			CFrame = CFrame.Angles(0, math.rad(35), math.rad(15)),
			Color = TOY.shard,
		})
		part(m, {
			ClassName = "WedgePart",
			Size = Vector3.new(r * 1.1, r, r * 1.2),
			CFrame = CFrame.new(r * 1.1, 0, -r * 0.6) * CFrame.Angles(0, math.rad(35), 0),
			Color = TOY.shard,
		})
	elseif id == "Comet" then
		ball(m, CFrame.new(), r * 2, TOY.comet)
		for i = 1, 6 do
			ball(m, CFrame.new(0, 0, i * r * 0.75), r * 2 * (1 - i * 0.13), TOY.cometTail, Enum.Material.Neon, 0.15 + i * 0.1)
		end
	elseif id == "Iron" then
		part(m, {
			Size = Vector3.one * r * 1.7,
			CFrame = CFrame.Angles(0, math.rad(30), 0),
			Color = TOY.iron,
		})
		for _, c in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
			local offset = CFrame.Angles(0, math.rad(30), 0) * Vector3.new(c[1] * r * 0.55, r * 0.85, c[2] * r * 0.55)
			ball(m, CFrame.new(offset), r * 0.35, TOY.rivet)
		end
	elseif id == "Cluster" then
		for i = 1, 4 do
			local a = i * 1.57 + 0.4
			ball(m, CFrame.new(math.cos(a) * r * 0.5, (i % 2) * 0.3, math.sin(a) * r * 0.5), r * 1.05, TOY.cluster)
		end
	elseif id == "Gold" then
		ball(m, CFrame.new(), r * 2, TOY.gold)
		ball(m, CFrame.new(-r * 0.35, r * 0.7, -r * 0.35), r * 0.5, Color3.new(1, 1, 1))
		local s = Instance.new("Sparkles")
		s.SparkleColor = TOY.gold
		s.Parent = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
	end
	if primed then
		outline(m, TOY.primed, TOY.primed, 0.45)
	else
		outline(m, Color3.new(0, 0, 0))
	end
	return m
end

local function buildToy(root)
	part(root, {
		Name = "Backdrop",
		Size = Vector3.new(400, 1, 400),
		CFrame = CFrame.new(W(0, 0, -16)),
		Color = TOY.sky,
		CastShadow = false,
	})
	for _ = 1, 90 do
		local color = if rng:NextNumber() < 0.8 then Color3.new(1, 1, 1) else hex("#ffe066")
		ball(root, CFrame.new(W(rng:NextNumber(-70, 70), rng:NextNumber(-45, 45), -15)), rng:NextNumber(0.3, 0.9), color, Enum.Material.Neon)
	end

	local planet = model(root, "Planet")
	ball(planet, CFrame.new(W(0, 0)), PLANET_RADIUS * 2, TOY.ocean)
	for i = 1, 7 do
		local a = i * 0.9 + 0.3
		local size = rng:NextNumber(3.5, 5.5)
		local d = rng:NextNumber(3.5, 9.6 - size / 2)
		ball(planet, CFrame.new(W(math.cos(a) * d, math.sin(a) * d, surface(d) - size * 0.32)), size, if i % 2 == 0 then TOY.land else TOY.landDark)
	end
	ball(planet, CFrame.new(W(0, 7.2, surface(7.2) - 1.4)), 4.6, TOY.ice)
	outline(planet, Color3.new(0, 0, 0))

	for i = 1, 36 do
		local a = i / 36 * math.pi * 2
		local at = Vector2.new(math.cos(a), math.sin(a)) * ORBIT_RADIUS
		blob(root, ArenaSpace.CFrameAt(at, Vector2.new(-math.sin(a), math.cos(a))), Vector3.new(0.45, 0.3, 1.4), TOY.orbit, Enum.Material.Neon, 0.25)
	end

	place(toyShip(root, false), SHIP_CRUISE.at, SHIP_CRUISE.facing, 3)
	place(toyShip(root, true), SHIP_BOOST.at, SHIP_BOOST.facing, 3)
	for _, r in ROCKS do
		local facing = if r.id == "Comet" then -r.at.Unit else nil
		place(toyRock(root, r.id, r.primed), r.at, facing, 2)
	end
end

----------------------------------------------------------------------------------------------
-- B · Brick Classic
----------------------------------------------------------------------------------------------

local BRICK = {
	sky = hex("#1b2b6b"),
	ocean = hex("#1e90ff"),
	oceanDeep = hex("#1565c0"),
	land = hex("#4cbb17"),
	ice = hex("#f2f2f2"),
	orbit = hex("#00e5ff"),
	body = hex("#e53935"),
	stripe = hex("#ffd600"),
	white = hex("#f5f5f5"),
	grille = hex("#424242"),
	window = hex("#4fc3f7"),
	soft = { hex("#ff5722"), hex("#ff9800"), hex("#ffeb3b") },
	boost = { hex("#ffb300"), hex("#fff176"), hex("#ffffff") },
	primed = hex("#ff4fd8"),
	rock = hex("#a1683a"),
	shard = hex("#d7a26b"),
	comet = hex("#b3f5ff"),
	cometTail = hex("#4dd0e1"),
	iron = hex("#78909c"),
	ironDark = hex("#455a64"),
	cluster = hex("#9c4dcc"),
	gold = hex("#ffc107"),
}

local function brick(parent, cf, size, color, material, transparency)
	local b = part(parent, {
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.Plastic,
		Transparency = transparency or 0,
	})
	b.TopSurface = Enum.SurfaceType.Studs
	return b
end

local function brickShip(parent, boosting)
	local m = model(parent, if boosting then "LancerBoost" else "LancerCruise")
	brick(m, CFrame.new(0, 0, 0), Vector3.new(1.2, 1, 2.2), BRICK.body)
	brick(m, CFrame.new(0, 0.05, 0.3), Vector3.new(1.3, 1.05, 0.4), BRICK.stripe)
	brick(m, CFrame.new(0, 0.6, -0.4), Vector3.new(0.6, 0.3, 0.6), BRICK.window, Enum.Material.Glass, 0.2)
	brick(m, CFrame.new(0, 0, 1.3), Vector3.new(0.9, 0.8, 0.4), BRICK.grille)
	for side = -1, 1, 2 do
		part(m, {
			ClassName = "WedgePart",
			Size = Vector3.new(0.4, 0.8, 1),
			CFrame = CFrame.new(side * 0.8, -0.1, 0.7) * CFrame.Angles(0, math.rad(180), 0),
			Color = BRICK.white,
			Material = Enum.Material.Plastic,
		})
	end
	if boosting then
		part(m, {
			ClassName = "WedgePart",
			Size = Vector3.new(1, 0.9, 1.8),
			CFrame = CFrame.new(0, 0, -2),
			Color = BRICK.white,
			Material = Enum.Material.Plastic,
		})
	else
		brick(m, CFrame.new(0, 0, -1.4), Vector3.new(1.2, 1, 0.6), BRICK.stripe)
	end
	-- Pixel flame: shrinking neon cubes.
	local colors = if boosting then BRICK.boost else BRICK.soft
	local steps = if boosting then 6 else 4
	for i = 1, steps do
		local k = 1 - (i - 1) / steps
		local color = colors[math.min(3, 1 + math.floor((1 - k) * 3))]
		brick(m, CFrame.new(0, 0, 1.6 + i * 0.75), Vector3.one * (0.9 * k + 0.2), color, Enum.Material.Neon)
	end
	return m
end

local function brickRock(parent, id, primed)
	local r = RockTypes[id].Radius
	local m = model(parent, id)
	local s = math.max(0.6, r * 0.75)
	local function cube(x, y, z, color, material, transparency)
		return brick(m, CFrame.new(x * s, y * s, z * s), Vector3.one * s, color, material, transparency)
	end
	if id == "Rock" then
		for x = -1, 1 do
			for z = -1, 1 do
				if math.abs(x) + math.abs(z) < 2 then
					cube(x, 0, z, BRICK.rock)
				end
			end
		end
		cube(0, 1, 0, BRICK.rock)
	elseif id == "Shard" then
		cube(-0.5, 0, 0.5, BRICK.shard)
		cube(0.5, 0, -0.5, BRICK.shard)
		cube(1.5, 0, -1.5, BRICK.shard)
	elseif id == "Comet" then
		cube(0, 0, 0, BRICK.comet)
		for i = 1, 4 do
			brick(m, CFrame.new(0, 0, i * s), Vector3.one * s * (1 - i * 0.18), BRICK.cometTail, Enum.Material.Neon, i * 0.15)
		end
	elseif id == "Iron" then
		brick(m, CFrame.new(), Vector3.one * r * 1.6, BRICK.iron, Enum.Material.DiamondPlate)
		for _, c in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
			brick(m, CFrame.new(c[1] * r * 0.8, r * 0.5, c[2] * r * 0.8), Vector3.one * 0.6, BRICK.ironDark)
		end
	elseif id == "Cluster" then
		cube(0, 0, 0, BRICK.cluster)
		cube(1.1, 0.2, 0.3, BRICK.cluster)
		cube(-0.4, 0.4, 1.1, BRICK.cluster)
		cube(-0.8, -0.2, -0.9, BRICK.cluster)
	elseif id == "Gold" then
		local b = brick(m, CFrame.Angles(0, math.rad(45), 0), Vector3.one * r * 1.5, BRICK.gold, Enum.Material.Foil)
		local sp = Instance.new("Sparkles")
		sp.SparkleColor = BRICK.gold
		sp.Parent = b
	end
	if primed then
		outline(m, BRICK.primed, BRICK.primed, 0.4)
	end
	return m
end

local function buildBrick(root)
	local back = part(root, {
		Name = "Backdrop",
		Size = Vector3.new(400, 1, 400),
		CFrame = CFrame.new(W(0, 0, -14)),
		Color = BRICK.sky,
		Material = Enum.Material.Plastic,
		CastShadow = false,
	})
	back.TopSurface = Enum.SurfaceType.Studs
	for _ = 1, 60 do
		brick(root, CFrame.new(W(rng:NextNumber(-70, 70), rng:NextNumber(-45, 45), -13)), Vector3.one * 0.6, Color3.new(1, 1, 0.85), Enum.Material.Neon)
	end

	local planet = model(root, "Planet")
	local size = 2
	for x = -5, 4 do
		for y = -5, 4 do
			for z = -5, 4 do
				local c = Vector3.new(x + 0.5, y + 0.5, z + 0.5) * size
				local d = c.Magnitude
				if d <= PLANET_RADIUS and d >= PLANET_RADIUS - 2.6 then
					local n = math.noise(c.X / 7, c.Z / 7, 0.37)
					local color = if c.Z < -7 then BRICK.ice elseif n > 0.08 then BRICK.land elseif d < 8.5 then BRICK.oceanDeep else BRICK.ocean
					brick(planet, CFrame.new(W(c.X, -c.Z, c.Y)), Vector3.one * size, color)
				end
			end
		end
	end

	for i = 1, 56 do
		local a = i / 56 * math.pi * 2
		if i % 2 == 0 then
			brick(root, CFrame.new(W(math.cos(a) * ORBIT_RADIUS, math.sin(a) * ORBIT_RADIUS)), Vector3.new(0.6, 0.4, 0.6), BRICK.orbit, Enum.Material.Neon, 0.1)
		end
	end

	place(brickShip(root, false), SHIP_CRUISE.at, SHIP_CRUISE.facing, 3)
	place(brickShip(root, true), SHIP_BOOST.at, SHIP_BOOST.facing, 3)
	for _, r in ROCKS do
		local facing = if r.id == "Comet" then -r.at.Unit else nil
		place(brickRock(root, r.id, r.primed), r.at, facing, 2)
	end
end

----------------------------------------------------------------------------------------------
-- C · Neon Arcade
----------------------------------------------------------------------------------------------

local NEON = {
	sky = hex("#0d0820"),
	planet = hex("#1fb5c9"),
	land = hex("#7cff6b"),
	atmosphere = hex("#4fd8e8"),
	orbit = hex("#4fd8e8"),
	hull = hex("#f5f5ff"),
	stripe = hex("#ff3fd2"),
	window = hex("#3ff3ff"),
	soft = { hex("#ff3d00"), hex("#ff8a00"), hex("#ffd54f") },
	boost = { hex("#ffa030"), hex("#ffe08a"), hex("#ffffff") },
	primed = hex("#ff3fd2"),
	body = hex("#2a2440"),
	type = {
		Rock = hex("#ffb066"),
		Shard = hex("#ffd29a"),
		Comet = hex("#7ff3ff"),
		Iron = hex("#a9c4ff"),
		Cluster = hex("#ff7ae0"),
		Gold = hex("#ffd23f"),
	},
}

local function neonShip(parent, boosting)
	local m = model(parent, if boosting then "LancerBoost" else "LancerCruise")
	blob(m, CFrame.new(), Vector3.new(1.3, 0.9, 2.6), NEON.hull)
	blob(m, CFrame.new(0, 0.3, -0.3), Vector3.new(0.5, 0.4, 0.7), NEON.window, Enum.Material.Neon)
	tube(m, CFrame.new(0, 0, 0.45), 0.25, 1.15, NEON.stripe, Enum.Material.Neon)
	for side = -1, 1, 2 do
		part(m, {
			Size = Vector3.new(0.8, 0.15, 0.7),
			CFrame = CFrame.new(side * 0.8, 0, 0.8) * CFrame.Angles(0, math.rad(side * 30), 0),
			Color = NEON.stripe,
			Material = Enum.Material.Neon,
		})
	end
	if boosting then
		blob(m, CFrame.new(0, 0, -1.9), Vector3.new(0.6, 0.6, 1.8), NEON.hull, Enum.Material.Neon)
	else
		ball(m, CFrame.new(0, 0, -1.2), 1.1, NEON.hull)
	end
	local colors = if boosting then NEON.boost else NEON.soft
	local length = if boosting then 7 else 3.6
	for i, color in colors do
		local k = 1 - (i - 1) * 0.3
		blob(m, CFrame.new(0, 0, 1.2 + length * k / 2), Vector3.new(1.4 * k, 0.5 * k, length * k), color, Enum.Material.Neon, 0.1 * (3 - i))
	end
	local light = Instance.new("PointLight")
	light.Color = colors[2]
	light.Range = 12
	light.Brightness = 3
	light.Parent = m:FindFirstChildWhichIsA("BasePart")
	return m
end

local function neonRock(parent, id, primed)
	local r = RockTypes[id].Radius
	local m = model(parent, id)
	local glow = if primed then NEON.primed else NEON.type[id]
	local bodyColor = glow:Lerp(NEON.body, 0.45)
	if id == "Shard" then
		part(m, { Size = Vector3.new(r * 2.2, r * 0.8, r), CFrame = CFrame.Angles(0, math.rad(35), 0), Color = bodyColor })
	elseif id == "Iron" then
		part(m, { Size = Vector3.one * r * 1.7, CFrame = CFrame.Angles(0, math.rad(30), 0), Color = bodyColor })
	elseif id == "Cluster" then
		for i = 1, 4 do
			local a = i * 1.57 + 0.4
			ball(m, CFrame.new(math.cos(a) * r * 0.5, 0, math.sin(a) * r * 0.5), r * 1.05, bodyColor)
		end
	else
		ball(m, CFrame.new(), r * 2, bodyColor)
	end
	if id == "Comet" then
		for i = 1, 6 do
			ball(m, CFrame.new(0, 0, i * r * 0.8), r * 2 * (1 - i * 0.13), glow, Enum.Material.Neon, 0.1 + i * 0.12)
		end
	end
	outline(m, glow, glow, if primed then 0.3 else 0.65)
	return m
end

local function buildNeon(root)
	part(root, {
		Name = "Backdrop",
		Size = Vector3.new(400, 1, 400),
		CFrame = CFrame.new(W(0, 0, -20)),
		Color = NEON.sky,
		CastShadow = false,
	})
	local starColors = { "#ffffff", "#ff7ae0", "#7ff3ff", "#ffe066" }
	for _ = 1, 110 do
		ball(root, CFrame.new(W(rng:NextNumber(-70, 70), rng:NextNumber(-45, 45), -18)), rng:NextNumber(0.2, 0.6), hex(starColors[rng:NextInteger(1, 4)]), Enum.Material.Neon)
	end

	local planet = model(root, "Planet")
	ball(planet, CFrame.new(W(0, 0)), PLANET_RADIUS * 2, NEON.planet)
	for i = 1, 6 do
		local a = i * 1.05
		local d = rng:NextNumber(3, 6.5)
		local size = rng:NextNumber(4, 7)
		ball(planet, CFrame.new(W(math.cos(a) * d, math.sin(a) * d, surface(d) - size * 0.36)), size, NEON.land)
	end
	ball(root, CFrame.new(W(0, 0, -2)), PLANET_RADIUS * 2 + 1.8, NEON.atmosphere, Enum.Material.Neon, 0.35)

	for i = 1, 90 do
		local a = i / 90 * math.pi * 2
		local at = Vector2.new(math.cos(a), math.sin(a)) * ORBIT_RADIUS
		part(root, {
			Size = Vector3.new(0.18, 0.1, ORBIT_RADIUS * math.pi * 2 / 90 + 0.05),
			CFrame = ArenaSpace.CFrameAt(at, Vector2.new(-math.sin(a), math.cos(a))),
			Color = NEON.orbit,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
		})
	end

	place(neonShip(root, false), SHIP_CRUISE.at, SHIP_CRUISE.facing, 2)
	place(neonShip(root, true), SHIP_BOOST.at, SHIP_BOOST.facing, 2)
	for _, r in ROCKS do
		local facing = if r.id == "Comet" then -r.at.Unit else nil
		place(neonRock(root, r.id, r.primed), r.at, facing, 1)
	end
end

----------------------------------------------------------------------------------------------
-- Variants, lighting, camera and the switcher bar
----------------------------------------------------------------------------------------------

local VARIANTS = {
	{
		key = "A",
		name = "Toy Box",
		build = buildToy,
		tilt = 18,
		lighting = { ClockTime = 13.5, GeographicLatitude = 20, Brightness = 2.6, Ambient = hex("#8c86c8"), OutdoorAmbient = hex("#b8b2ff"), GlobalShadows = true },
		bloom = { Intensity = 0.35, Size = 18, Threshold = 1.4 },
		grade = { Saturation = 0.25, Contrast = 0.12, Brightness = 0.04 },
	},
	{
		key = "B",
		name = "Brick Classic",
		build = buildBrick,
		tilt = 32,
		lighting = { ClockTime = 14, GeographicLatitude = 35, Brightness = 3, Ambient = hex("#7a7a90"), OutdoorAmbient = hex("#9fa4c0"), GlobalShadows = true },
		bloom = { Intensity = 0.25, Size = 14, Threshold = 1.6 },
		grade = { Saturation = 0.15, Contrast = 0.08, Brightness = 0.02 },
	},
	{
		key = "C",
		name = "Neon Arcade",
		build = buildNeon,
		tilt = 0,
		lighting = { ClockTime = 0, GeographicLatitude = 0, Brightness = 1, Ambient = hex("#5a4f86"), OutdoorAmbient = hex("#3a3060"), GlobalShadows = false },
		bloom = { Intensity = 1.1, Size = 28, Threshold = 0.75 },
		grade = { Saturation = 0.35, Contrast = 0.2, Brightness = 0 },
	},
}

local function effect(className, name)
	local e = Lighting:FindFirstChild(name) or Instance.new(className)
	e.Name = name
	e.Parent = Lighting
	return e
end

return function()
	for _, name in { "Baseplate", "SpawnLocation" } do
		local thing = workspace:FindFirstChild(name)
		if thing then
			thing:Destroy()
		end
	end

	local scenes = {}
	for _, v in VARIANTS do
		local root = Instance.new("Folder")
		root.Name = `StylePrototype_{v.key}`
		v.build(root)
		scenes[v.key] = root
	end

	local bloom = effect("BloomEffect", "StylePrototypeBloom")
	local grade = effect("ColorCorrectionEffect", "StylePrototypeGrade")
	local camera = workspace.CurrentCamera

	local gui = Instance.new("ScreenGui")
	gui.Name = "StylePrototypeSwitcher"
	gui.DisplayOrder = 100
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -16)
	bar.Size = UDim2.fromOffset(340, 44)
	bar.BackgroundColor3 = Color3.new(0.08, 0.08, 0.1)
	bar.BackgroundTransparency = 0.1
	bar.Parent = gui
	Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -100, 1, 0)
	label.Position = UDim2.fromOffset(50, 0)
	label.Font = Enum.Font.BuilderSansBold
	label.TextSize = 18
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = bar
	local function arrow(text, x)
		local b = Instance.new("TextButton")
		b.Text = text
		b.Font = Enum.Font.BuilderSansBold
		b.TextSize = 20
		b.TextColor3 = Color3.new(1, 1, 1)
		b.BackgroundTransparency = 1
		b.Size = UDim2.fromOffset(50, 44)
		b.Position = UDim2.fromOffset(x, 0)
		b.Parent = bar
		return b
	end
	local prev = arrow("◀", 0)
	local nextButton = arrow("▶", 290)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local index = 1
	local function show(i)
		index = (i - 1) % #VARIANTS + 1
		local v = VARIANTS[index]
		for key, root in scenes do
			root.Parent = if key == v.key then workspace else nil
		end
		for k, value in v.lighting do
			Lighting[k] = value
		end
		for k, value in v.bloom do
			bloom[k] = value
		end
		for k, value in v.grade do
			grade[k] = value
		end
		local tilt = math.rad(v.tilt)
		local target = ArenaSpace.ToWorld(VIEW_CENTER, 2)
		local distance = VIEW_HALF_HEIGHT / math.tan(math.rad(FOV / 2))
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = FOV
		camera.CFrame = CFrame.lookAt(target + Vector3.new(0, math.cos(tilt), math.sin(tilt)) * distance, target, -Vector3.zAxis)
		label.Text = `{v.key} · {v.name}`
		if workspace:GetAttribute("StyleVariant") ~= v.key then
			workspace:SetAttribute("StyleVariant", v.key)
		end
	end

	prev.Activated:Connect(function()
		show(index - 1)
	end)
	nextButton.Activated:Connect(function()
		show(index + 1)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Left then
			show(index - 1)
		elseif input.KeyCode == Enum.KeyCode.Right then
			show(index + 1)
		end
	end)
	workspace:GetAttributeChangedSignal("StyleVariant"):Connect(function()
		for i, v in VARIANTS do
			if v.key == workspace:GetAttribute("StyleVariant") and i ~= index then
				show(i)
			end
		end
	end)

	show(1)
end
