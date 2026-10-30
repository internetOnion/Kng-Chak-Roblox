--!strict
--[[
	UpgradeVisuals: animated 2D Toy Box mini-diagrams for the 10 upgrades.

	    local visual = UpgradeVisuals.new(stageFrame)
	    visual:SetUpgrade("Shockwave")
	    visual:Animate(phase) -- phase in [0, 1)

	Built entirely from crisp GUI shapes in the Toy Box palette (docs/art-guide.md)
	so every upgrade's effect reads at a glance on a phone without asset uploads.
]]

type Animator = (phase: number) -> ()

local OUTLINE = Color3.fromHex("#000000")
local WHITE = Color3.fromHex("#ffffff")
local GOLD = Color3.fromHex("#ffe066")
local RED = Color3.fromHex("#ff3b3b")
local STRIPE = Color3.fromHex("#ffd400")
local WINDOW = Color3.fromHex("#8fe3ff")
local HELMET = Color3.fromHex("#fff1b8")
local SPEAR = Color3.fromHex("#f4f6ff")
local FLAME_EDGE = Color3.fromHex("#ff4a1c")
local FLAME_MID = Color3.fromHex("#ff9a1f")
local FUEL_ORANGE = Color3.fromHex("#ff8a3d")
local ROCK_BROWN = Color3.fromHex("#c98b55")
local CRATER = Color3.fromHex("#8f5c34")
local PRIMED = Color3.fromHex("#ff4fd8")
local ORBIT_CYAN = Color3.fromHex("#6ff3ff")
local SHIELD_CYAN = Color3.fromHex("#bff6ff")
local DIVE_BLUE = Color3.fromHex("#2f7dff")
local DIVE_MID = Color3.fromHex("#7fe6ff")
local PLANET_OCEAN = Color3.fromHex("#2fc4ff")
local PLANET_LAND = Color3.fromHex("#5ee05e")
local MUTED_LINE = Color3.fromHex("#4a479e")

local UpgradeVisuals = {}
UpgradeVisuals.__index = UpgradeVisuals

export type UpgradeVisuals = typeof(setmetatable(
	{} :: {
		_stage: Frame,
		_id: string?,
		_animate: Animator?,
	},
	UpgradeVisuals
))

local function round(parent: Instance, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

local function stroke(parent: Instance, thickness: number, color: Color3, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function box(
	parent: Instance,
	pos: UDim2,
	size: UDim2,
	color: Color3,
	transparency: number?,
	anchor: Vector2?
): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = anchor or Vector2.new(0.5, 0.5)
	frame.Position = pos
	frame.Size = size
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

-- Toy Box rocket facing right (+X) by default; set `spearOut` for the white/red spear nose.
local function makeRocket(
	parent: Instance,
	x: number,
	y: number,
	rotation: number,
	scale: number,
	spearOut: boolean
): Frame
	local root = box(parent, UDim2.fromOffset(x, y), UDim2.fromOffset(30, 18), WHITE, 1)
	root.Rotation = rotation
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = scale
	uiScale.Parent = root

	local finTop = box(root, UDim2.fromOffset(6, 2), UDim2.fromOffset(8, 5), WHITE, 0)
	round(finTop, UDim.new(0, 2))
	stroke(finTop, 1.5, OUTLINE)
	local finBot = box(root, UDim2.fromOffset(6, 16), UDim2.fromOffset(8, 5), WHITE, 0)
	round(finBot, UDim.new(0, 2))
	stroke(finBot, 1.5, OUTLINE)

	if spearOut then
		local spear = box(root, UDim2.fromOffset(27, 9), UDim2.fromOffset(18, 7), SPEAR, 0)
		round(spear, UDim.new(0.5, 0))
		stroke(spear, 1.5, OUTLINE)
		local tip = box(spear, UDim2.new(1, -3, 0.5, 0), UDim2.fromOffset(6, 7), RED, 0)
		round(tip, UDim.new(0.5, 0))
	else
		local helmet = box(root, UDim2.fromOffset(22, 9), UDim2.fromOffset(11, 11), HELMET, 0)
		round(helmet, UDim.new(0.5, 0))
		stroke(helmet, 1.5, OUTLINE)
	end

	local hull = box(root, UDim2.fromOffset(13, 9), UDim2.fromOffset(18, 12), RED, 0)
	round(hull, UDim.new(0.5, 0))
	stroke(hull, 2, OUTLINE)
	box(hull, UDim2.fromOffset(6, 6), UDim2.fromOffset(3, 12), STRIPE, 0)
	local win = box(hull, UDim2.fromOffset(12, 6), UDim2.fromOffset(5, 5), WINDOW, 0)
	round(win, UDim.new(0.5, 0))

	return root
end

local function makeRock(parent: Instance, x: number, y: number, diameter: number, primed: boolean): (Frame, UIStroke)
	local rock = box(
		parent,
		UDim2.fromOffset(x, y),
		UDim2.fromOffset(diameter, diameter),
		if primed then PRIMED else ROCK_BROWN,
		0
	)
	round(rock, UDim.new(0.5, 0))
	local outline = stroke(rock, 2.5, if primed then PRIMED else OUTLINE)
	local dot = box(
		rock,
		UDim2.fromScale(0.36, 0.38),
		UDim2.fromOffset(math.max(4, math.round(diameter * 0.22)), math.max(4, math.round(diameter * 0.22))),
		if primed then WHITE else CRATER,
		if primed then 0.55 else 0
	)
	round(dot, UDim.new(0.5, 0))
	return rock, outline
end

local function makePlanet(parent: Instance, x: number, y: number, diameter: number): Frame
	local planet = box(parent, UDim2.fromOffset(x, y), UDim2.fromOffset(diameter, diameter), PLANET_OCEAN, 0)
	round(planet, UDim.new(0.5, 0))
	stroke(planet, 2.5, OUTLINE)
	local ice = box(
		planet,
		UDim2.new(0.5, 0, 0, math.round(diameter * 0.14)),
		UDim2.fromOffset(math.round(diameter * 0.48), math.round(diameter * 0.2)),
		WHITE,
		0
	)
	round(ice, UDim.new(0.5, 0))
	local landA = box(
		planet,
		UDim2.fromScale(0.36, 0.56),
		UDim2.fromOffset(math.round(diameter * 0.36), math.round(diameter * 0.26)),
		PLANET_LAND,
		0
	)
	round(landA, UDim.new(0.5, 0))
	local landB = box(
		planet,
		UDim2.fromScale(0.7, 0.66),
		UDim2.fromOffset(math.round(diameter * 0.24), math.round(diameter * 0.2)),
		PLANET_LAND,
		0
	)
	round(landB, UDim.new(0.5, 0))
	return planet
end

local function makePlus(parent: Instance, x: number, y: number, size: number, color: Color3): Frame
	local holder = box(parent, UDim2.fromOffset(x, y), UDim2.fromOffset(size, size), color, 1)
	local thick = math.max(3, math.round(size * 0.32))
	local h = box(holder, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(size, thick), color, 0)
	round(h, UDim.new(0.5, 0))
	local v = box(holder, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(thick, size), color, 0)
	round(v, UDim.new(0.5, 0))
	return holder
end

-- Positions a centre-anchored Frame as a ray starting at (x0, y0) along `deg` (GuiObject.Rotation always pivots around centre).
local function placeRay(frame: Frame, x0: number, y0: number, length: number, thickness: number, deg: number)
	local rad = math.rad(deg)
	local midX = x0 + math.cos(rad) * length * 0.5
	local midY = y0 + math.sin(rad) * length * 0.5
	frame.Position = UDim2.fromOffset(midX, midY)
	frame.Size = UDim2.fromOffset(length, thickness)
	frame.Rotation = deg
end

local BUILDERS: { [string]: (stage: Frame) -> Animator } = {
	-- 1. Long Hose: flame stretches past baseline to prime a distant rock
	LongHose = function(stage: Frame): Animator
		-- Baseline reach marker
		for i = 1, 5 do
			local dash = box(stage, UDim2.fromOffset(96, 16 + i * 14), UDim2.fromOffset(2, 8), MUTED_LINE, 0.2)
			round(dash, UDim.new(0.5, 0))
		end
		local edge =
			box(stage, UDim2.fromOffset(44, 55), UDim2.fromOffset(52, 22), FLAME_EDGE, 0.1, Vector2.new(0, 0.5))
		round(edge, UDim.new(0.5, 0))
		local mid = box(stage, UDim2.fromOffset(44, 55), UDim2.fromOffset(36, 14), FLAME_MID, 0.05, Vector2.new(0, 0.5))
		round(mid, UDim.new(0.5, 0))
		local core = box(stage, UDim2.fromOffset(44, 55), UDim2.fromOffset(20, 8), GOLD, 0, Vector2.new(0, 0.5))
		round(core, UDim.new(0.5, 0))
		makeRocket(stage, 32, 55, 180, 0.9, false)
		local rock, outline = makeRock(stage, 146, 55, 22, false)

		return function(phase: number)
			local reach = 0.5 + 0.5 * math.sin(phase * 2 * math.pi)
			local len = 50 + 46 * reach
			edge.Size = UDim2.fromOffset(len, 22)
			mid.Size = UDim2.fromOffset(len * 0.72, 14)
			core.Size = UDim2.fromOffset(len * 0.44, 8)
			local hit = reach > 0.55
			rock.BackgroundColor3 = if hit then PRIMED else ROCK_BROWN
			outline.Color = if hit then PRIMED else OUTLINE
		end
	end,

	-- 2. Wide Nozzle: flame cone fans wider to prime two angled rocks
	WideNozzle = function(stage: Frame): Animator
		local topRay = box(stage, UDim2.fromOffset(80, 55), UDim2.fromOffset(88, 16), FLAME_EDGE, 0.15)
		round(topRay, UDim.new(0.5, 0))
		local botRay = box(stage, UDim2.fromOffset(80, 55), UDim2.fromOffset(88, 16), FLAME_EDGE, 0.15)
		round(botRay, UDim.new(0.5, 0))
		local midRay =
			box(stage, UDim2.fromOffset(42, 55), UDim2.fromOffset(74, 18), FLAME_MID, 0.05, Vector2.new(0, 0.5))
		round(midRay, UDim.new(0.5, 0))
		local coreRay = box(stage, UDim2.fromOffset(42, 55), UDim2.fromOffset(42, 10), GOLD, 0, Vector2.new(0, 0.5))
		round(coreRay, UDim.new(0.5, 0))
		makeRocket(stage, 30, 55, 180, 0.9, false)

		local rockTop, strokeTop = makeRock(stage, 136, 26, 20, false)
		local rockBot, strokeBot = makeRock(stage, 136, 84, 20, false)

		return function(phase: number)
			local spread = 0.5 + 0.5 * math.sin(phase * 2 * math.pi)
			local angle = 6 + 13 * spread
			placeRay(topRay, 42, 55, 88, 16, -angle)
			placeRay(botRay, 42, 55, 88, 16, angle)
			midRay.Size = UDim2.fromOffset(74, 16 + 12 * spread)
			local hit = spread > 0.5
			rockTop.BackgroundColor3 = if hit then PRIMED else ROCK_BROWN
			strokeTop.Color = if hit then PRIMED else OUTLINE
			rockBot.BackgroundColor3 = if hit then PRIMED else ROCK_BROWN
			strokeBot.Color = if hit then PRIMED else OUTLINE
		end
	end,

	-- 3. Sticky Heat: glowing pink primed rock surrounded by a long-lasting pink timer ring
	StickyHeat = function(stage: Frame): Animator
		local halo = box(stage, UDim2.fromOffset(90, 55), UDim2.fromOffset(62, 62), PRIMED, 0.78)
		round(halo, UDim.new(0.5, 0))
		makeRock(stage, 90, 55, 34, true)

		local beads: { Frame } = {}
		local count = 12
		for i = 1, count do
			local a = (i - 1) / count * 2 * math.pi - math.pi / 2
			local bx = 90 + math.cos(a) * 38
			local by = 55 + math.sin(a) * 38
			local bead = box(stage, UDim2.fromOffset(bx, by), UDim2.fromOffset(8, 8), PRIMED, 0)
			round(bead, UDim.new(0.5, 0))
			table.insert(beads, bead)
		end

		return function(phase: number)
			local pulse = 0.5 + 0.5 * math.sin(phase * 2 * math.pi)
			halo.Size = UDim2.fromOffset(56 + 10 * pulse, 56 + 10 * pulse)
			local litCount = count - math.floor(phase * 4) -- stays lit across most of the cycle
			for i, bead in beads do
				local on = i <= litCount
				bead.BackgroundColor3 = if i > count - 3 and on then GOLD else PRIMED
				bead.BackgroundTransparency = if on then 0 else 0.75
			end
		end
	end,

	-- 4. Tempered Tip: extended white/red spear + bonus duration bar below
	TemperedTip = function(stage: Frame): Animator
		local glow = box(stage, UDim2.fromOffset(112, 42), UDim2.fromOffset(38, 22), GOLD, 0.72)
		round(glow, UDim.new(0.5, 0))
		local rocket = makeRocket(stage, 78, 42, 0, 1.15, true)

		local track = box(stage, UDim2.fromOffset(90, 84), UDim2.fromOffset(132, 12), MUTED_LINE, 0.45)
		round(track, UDim.new(0.5, 0))
		local baseBar = box(track, UDim2.fromOffset(0, 6), UDim2.fromOffset(82, 12), SPEAR, 0, Vector2.new(0, 0.5))
		round(baseBar, UDim.new(0.5, 0))
		local bonusBar = box(track, UDim2.fromOffset(80, 6), UDim2.fromOffset(52, 12), GOLD, 0, Vector2.new(0, 0.5))
		round(bonusBar, UDim.new(0.5, 0))
		local marker = box(track, UDim2.fromOffset(0, 6), UDim2.fromOffset(6, 18), WHITE, 0)
		round(marker, UDim.new(0.5, 0))
		stroke(marker, 1.5, OUTLINE)

		return function(phase: number)
			local sweep = math.clamp(phase / 0.85, 0, 1)
			marker.Position = UDim2.fromOffset(132 * sweep, 6)
			local inBonus = sweep > 0.6
			bonusBar.BackgroundTransparency = if inBonus then 0 else 0.25
			glow.BackgroundTransparency = if inBonus then 0.45 else 0.78
			rocket.Position = UDim2.fromOffset(70 + 16 * sweep, 42)
		end
	end,

	-- 5. Extra Tank: curved 4-segment fuel arc with the 4th segment glowing gold + plus icon
	ExtraTank = function(stage: Frame): Animator
		makeRocket(stage, 90, 34, -90, 0.95, false)
		local segments: { Frame } = {}
		local angles = { -48, -16, 16, 48 }
		for i, deg in angles do
			local rad = math.rad(deg)
			local sx = 90 + math.sin(rad) * 44
			local sy = 38 + math.cos(rad) * 44
			local seg =
				box(stage, UDim2.fromOffset(sx, sy), UDim2.fromOffset(22, 8), if i == 4 then GOLD else FUEL_ORANGE, 0)
			seg.Rotation = -deg
			round(seg, UDim.new(0.5, 0))
			stroke(seg, 1.5, OUTLINE)
			table.insert(segments, seg)
		end
		local plus = makePlus(stage, 148, 56, 14, GOLD)

		return function(phase: number)
			local pulse = 0.5 + 0.5 * math.sin(phase * 2 * math.pi)
			local fourth = segments[4]
			fourth.Size = UDim2.fromOffset(22 + 4 * pulse, 8 + 3 * pulse)
			fourth.BackgroundTransparency = 0.25 * (1 - pulse)
			plus.Position = UDim2.fromOffset(148, 58 - 4 * pulse)
		end
	end,

	-- 6. Shockwave: breaking center pink rock sends a pink ring that primes nearby brown rocks
	Shockwave = function(stage: Frame): Animator
		local ring = box(stage, UDim2.fromOffset(90, 55), UDim2.fromOffset(24, 24), PRIMED, 1)
		round(ring, UDim.new(0.5, 0))
		local ringStroke = stroke(ring, 3, PRIMED, 0)

		local centerRock = box(stage, UDim2.fromOffset(90, 55), UDim2.fromOffset(22, 22), PRIMED, 0)
		round(centerRock, UDim.new(0.5, 0))
		stroke(centerRock, 2.5, PRIMED)

		local leftRock, leftStroke = makeRock(stage, 36, 34, 20, false)
		local rightRock, rightStroke = makeRock(stage, 144, 74, 20, false)

		return function(phase: number)
			local burst = math.clamp((phase - 0.18) / 0.65, 0, 1)
			centerRock.Visible = phase < 0.22
			ring.Visible = phase >= 0.18
			local diameter = 22 + 108 * burst
			ring.Size = UDim2.fromOffset(diameter, diameter)
			ringStroke.Transparency = burst ^ 1.5

			local chained = burst > 0.45
			leftRock.BackgroundColor3 = if chained then PRIMED else ROCK_BROWN
			leftStroke.Color = if chained then PRIMED else OUTLINE
			rightRock.BackgroundColor3 = if chained then PRIMED else ROCK_BROWN
			rightStroke.Color = if chained then PRIMED else OUTLINE
		end
	end,

	-- 7. Quick Release: orbit arc + fast-recharging cyan/gold cooldown ring
	QuickRelease = function(stage: Frame): Animator
		makePlanet(stage, 54, 62, 34)
		local orbit = box(stage, UDim2.fromOffset(54, 62), UDim2.fromOffset(56, 56), ORBIT_CYAN, 1)
		round(orbit, UDim.new(0.5, 0))
		stroke(orbit, 2, ORBIT_CYAN, 0.35)

		local dots: { Frame } = {}
		local count = 8
		for i = 1, count do
			local a = (i - 1) / count * 2 * math.pi - math.pi / 2
			local dx = 132 + math.cos(a) * 24
			local dy = 55 + math.sin(a) * 24
			local dot = box(stage, UDim2.fromOffset(dx, dy), UDim2.fromOffset(8, 8), ORBIT_CYAN, 0)
			round(dot, UDim.new(0.5, 0))
			table.insert(dots, dot)
		end
		local readyGlow = box(stage, UDim2.fromOffset(132, 55), UDim2.fromOffset(22, 22), GOLD, 0.2)
		round(readyGlow, UDim.new(0.5, 0))

		return function(phase: number)
			-- Fills twice per cycle to communicate fast recharge
			local fast = (phase * 2) % 1
			local lit = math.ceil(fast * count)
			for i, dot in dots do
				local on = i <= lit
				dot.BackgroundColor3 = if fast > 0.8 then GOLD else ORBIT_CYAN
				dot.BackgroundTransparency = if on then 0 else 0.78
			end
			readyGlow.BackgroundTransparency = if fast > 0.78 then 0.1 else 0.85
		end
	end,

	-- 8. Long Dive: fast blue slingshot streak launching rocket tangentially across the stage
	LongDive = function(stage: Frame): Animator
		local cx, cy, r = 36, 70, 22
		makePlanet(stage, cx, cy, 28)
		local orbit = box(stage, UDim2.fromOffset(cx, cy), UDim2.fromOffset(r * 2, r * 2), ORBIT_CYAN, 1)
		round(orbit, UDim.new(0.5, 0))
		stroke(orbit, 2, ORBIT_CYAN, 0.35)

		local exitDeg = 55
		local headingDeg = exitDeg - 90 -- -35° true tangent
		local exitRad = math.rad(exitDeg)
		local headRad = math.rad(headingDeg)
		local exitX = cx + r * math.cos(exitRad)
		local exitY = cy + r * math.sin(exitRad)
		local dirX = math.cos(headRad)
		local dirY = math.sin(headRad)

		local streakOuter = box(stage, UDim2.fromOffset(exitX, exitY), UDim2.fromOffset(18, 12), DIVE_BLUE, 0.2)
		round(streakOuter, UDim.new(0.5, 0))
		local streakInner = box(stage, UDim2.fromOffset(exitX, exitY), UDim2.fromOffset(12, 6), DIVE_MID, 0.05)
		round(streakInner, UDim.new(0.5, 0))

		local rocket = makeRocket(stage, exitX, exitY, headingDeg, 0.88, true)

		return function(phase: number)
			local dash = 1 - (1 - math.clamp(phase / 0.72, 0, 1)) ^ 3
			local dist = 10 + 92 * dash
			placeRay(streakOuter, exitX, exitY, math.max(8, dist - 4), 12, headingDeg)
			placeRay(streakInner, exitX + 3 * dirX, exitY + 3 * dirY, math.max(6, (dist - 8) * 0.88), 6, headingDeg)
			rocket.Position = UDim2.fromOffset(exitX + dist * dirX, exitY + dist * dirY)
		end
	end,

	-- 9. Firebreak: blue PERFECT dive hits pink rock -> green "+" heals rise from planet
	Firebreak = function(stage: Frame): Animator
		local healGlow = box(stage, UDim2.fromOffset(54, 64), UDim2.fromOffset(58, 58), PLANET_LAND, 0.75)
		round(healGlow, UDim.new(0.5, 0))
		makePlanet(stage, 54, 64, 42)

		local startX, startY = 84, 55
		local headingDeg = -27
		local headRad = math.rad(headingDeg)
		local dirX = math.cos(headRad)
		local dirY = math.sin(headRad)

		local streak = box(stage, UDim2.fromOffset(startX, startY), UDim2.fromOffset(20, 8), DIVE_MID, 0.15)
		round(streak, UDim.new(0.5, 0))
		local rock = box(stage, UDim2.fromOffset(138, 28), UDim2.fromOffset(20, 20), PRIMED, 0)
		round(rock, UDim.new(0.5, 0))
		stroke(rock, 2.5, PRIMED)
		local rocket = makeRocket(stage, startX, startY, headingDeg, 0.78, true)

		local plusA = makePlus(stage, 40, 28, 15, PLANET_LAND)
		local plusB = makePlus(stage, 70, 22, 13, GOLD)

		return function(phase: number)
			local strike = math.clamp(phase / 0.35, 0, 1)
			local diving = phase < 0.42
			local dist = 48 * strike
			streak.Visible = diving
			rocket.Visible = phase < 0.5
			placeRay(streak, startX, startY, math.max(6, dist - 4), 8, headingDeg)
			rocket.Position = UDim2.fromOffset(startX + dist * dirX, startY + dist * dirY)
			rock.Visible = phase < 0.36
			local healPhase = math.clamp((phase - 0.32) / 0.62, 0, 1)
			local showHeal = phase >= 0.32
			plusA.Visible = showHeal
			plusB.Visible = showHeal
			plusA.Position = UDim2.fromOffset(38, 38 - 18 * healPhase)
			plusB.Position = UDim2.fromOffset(70, 32 - 18 * healPhase)
			healGlow.BackgroundTransparency = if showHeal then 0.55 + 0.35 * healPhase else 0.85
		end
	end,

	-- 10. Shield Plating: planet wrapped in an expanding bright cyan bead shield ring
	ShieldPlating = function(stage: Frame): Animator
		local outerHalo = box(stage, UDim2.fromOffset(90, 55), UDim2.fromOffset(84, 84), ORBIT_CYAN, 0.82)
		round(outerHalo, UDim.new(0.5, 0))
		makePlanet(stage, 90, 55, 42)

		local beads: { { frame: Frame, angle: number } } = {}
		local count = 16
		for i = 1, count do
			local a = (i - 1) / count * 2 * math.pi
			local bead = box(stage, UDim2.fromOffset(90, 55), UDim2.fromOffset(8, 8), SHIELD_CYAN, 0.1)
			round(bead, UDim.new(0.5, 0))
			table.insert(beads, { frame = bead, angle = a })
		end

		return function(phase: number)
			local grow = 0.5 + 0.5 * math.sin(phase * 2 * math.pi)
			local r = 30 + 8 * grow
			outerHalo.Size = UDim2.fromOffset(r * 2 + 10, r * 2 + 10)
			for _, item in beads do
				local a = item.angle + phase * 0.8
				item.frame.Position = UDim2.fromOffset(90 + math.cos(a) * r, 55 + math.sin(a) * r)
				item.frame.Size = UDim2.fromOffset(6 + 3 * grow, 6 + 3 * grow)
				item.frame.BackgroundColor3 = if grow > 0.6 then ORBIT_CYAN else SHIELD_CYAN
			end
		end
	end,
}

function UpgradeVisuals.new(stage: Frame): UpgradeVisuals
	return setmetatable({
		_stage = stage,
		_id = nil :: string?,
		_animate = nil :: Animator?,
	}, UpgradeVisuals)
end

function UpgradeVisuals.SetUpgrade(self: UpgradeVisuals, id: string)
	if self._id == id then
		return
	end
	self._id = id
	self._stage:ClearAllChildren()
	round(self._stage, UDim.new(0, 12))
	local builder = BUILDERS[id]
	self._animate = if builder then builder(self._stage) else nil
	if self._animate then
		(self._animate :: Animator)(0)
	end
end

function UpgradeVisuals.Animate(self: UpgradeVisuals, phase: number)
	local anim = self._animate
	if anim then
		anim(phase)
	end
end

return UpgradeVisuals
