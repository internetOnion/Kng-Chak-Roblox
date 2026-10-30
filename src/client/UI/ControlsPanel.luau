--!strict
--[[
	ControlsPanel: visual Controls & Core Moves card, shown before the first call
	and reopenable anytime from Start or Pause.

	    local panel = ControlsPanel.new(playerGui)
	    panel:Show("START CALL", function() ... end)
	    panel:Update(os.clock()) -- every frame: animates the mini diagrams while open

	Auto-selects Touch or PC diagrams from the player's active input device, with a
	top-right toggle pill so testers on PC can also inspect Touch controls.
]]

local UserInputService = game:GetService("UserInputService")

local Fonts = require(script.Parent.Fonts)

type Scheme = "Touch" | "PC"

local PANEL_SIZE = Vector2.new(736, 356)
local BACKDROP = Color3.fromHex("#14133d")
local CARD = Color3.fromHex("#1b1a5c")
local STAGE = Color3.fromHex("#12113a")
local STAGE_BORDER = Color3.fromHex("#2f2d80")
local OUTLINE = Color3.fromHex("#000000")
local GOLD = Color3.fromHex("#ffe066")
local WHITE = Color3.fromHex("#ffffff")
local SUBTEXT = Color3.fromHex("#d0ceff")
local RED = Color3.fromHex("#ff3b3b")
local STRIPE = Color3.fromHex("#ffd400")
local WINDOW = Color3.fromHex("#8fe3ff")
local HELMET = Color3.fromHex("#fff1b8")
local SPEAR = Color3.fromHex("#f4f6ff")
local FLAME_EDGE = Color3.fromHex("#ff4a1c")
local FLAME_MID = Color3.fromHex("#ff9a1f")
local BOOST_EDGE = Color3.fromHex("#ffa030")
local BOOST_MID = Color3.fromHex("#ffe08a")
local ROCK_BROWN = Color3.fromHex("#c98b55")
local PRIMED = Color3.fromHex("#ff4fd8")
local ORBIT_CYAN = Color3.fromHex("#6ff3ff")
local DIVE_BLUE = Color3.fromHex("#2f7dff")
local PLANET_OCEAN = Color3.fromHex("#2fc4ff")
local PLANET_LAND = Color3.fromHex("#5ee05e")
local PERIOD = 1.8
local SLINGSHOT_PERIOD = 2.4
local ORBIT_CENTER = Vector2.new(30, 58)
local ORBIT_RADIUS = 20
local DIVE_EXIT_DEG = 30
local DIVE_HEADING_DEG = DIVE_EXIT_DEG - 90 -- -60°, true counter-clockwise tangent at 30°

type MiniShip = {
	root: Frame,
	helmet: Frame,
	spear: Frame,
	flameEdge: Frame,
	flameMid: Frame,
}

local ControlsPanel = {}
ControlsPanel.__index = ControlsPanel

export type ControlsPanel = typeof(setmetatable(
	{} :: {
		_gui: ScreenGui,
		_scheme: Scheme,
		_manualScheme: boolean,
		_suppressed: boolean,
		_onDone: (() -> ())?,
		_ctaLabel: TextLabel,
		_touchTab: TextButton,
		_pcTab: TextButton,
		-- Input row labels
		_steerTitle: TextLabel,
		_steerBody: TextLabel,
		_boostTitle: TextLabel,
		_boostBody: TextLabel,
		-- Input row visual containers
		_touchSteer: Frame,
		_pcSteer: Frame,
		_touchBoost: Frame,
		_pcBoost: Frame,
		-- Animated parts
		_stickKnob: Frame,
		_touchSteerShip: MiniShip,
		_cursorReticle: Frame,
		_pcSteerShip: MiniShip,
		_tapRipple: Frame,
		_tapRippleStroke: UIStroke,
		_touchBoostShip: MiniShip,
		_clickCap: Frame,
		_spaceCap: Frame,
		_pcBoostShip: MiniShip,
		_pushFlame: Frame,
		_pushRock: Frame,
		_pushRockStroke: UIStroke,
		_breakShip: MiniShip,
		_breakRock: Frame,
		_breakHeal: Frame,
		_orbitStroke: UIStroke,
		_diveStreak: Frame,
		_diveStreakCore: Frame,
		_diveShip: MiniShip,
		_diveRock: Frame,
		_divePlus: Frame,
		_diveHeal: TextLabel,
	},
	ControlsPanel
))

local function round(parent: Instance, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

local function border(parent: Instance, thickness: number, color: Color3, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = color
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function box(
	parent: Instance,
	name: string,
	pos: UDim2,
	size: UDim2,
	color: Color3,
	transparency: number?,
	anchor: Vector2?
): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = anchor or Vector2.zero
	frame.Position = pos
	frame.Size = size
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function makeText(
	parent: Instance,
	name: string,
	font: Font,
	size: number,
	color: Color3,
	pos: UDim2,
	area: UDim2,
	alignX: Enum.TextXAlignment?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = pos
	label.Size = area
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextWrapped = true
	label.TextXAlignment = alignX or Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = parent
	return label
end

-- Mini 2D Toy Box Lancer facing right (+X) around its centre.
local function makeMiniShip(parent: Instance, pos: UDim2, scale: number): MiniShip
	local root = box(parent, "Ship", pos, UDim2.fromOffset(30, 18), WHITE, 1, Vector2.new(0.5, 0.5))
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = scale
	uiScale.Parent = root

	local flameEdge =
		box(root, "FlameEdge", UDim2.new(0, 2, 0.5, 0), UDim2.fromOffset(14, 10), FLAME_EDGE, 0.05, Vector2.new(1, 0.5))
	round(flameEdge, UDim.new(0.5, 0))
	local flameMid =
		box(root, "FlameMid", UDim2.new(0, 2, 0.5, 0), UDim2.fromOffset(9, 6), FLAME_MID, 0, Vector2.new(1, 0.5))
	round(flameMid, UDim.new(0.5, 0))

	local finTop = box(root, "FinTop", UDim2.fromOffset(2, 0), UDim2.fromOffset(8, 5), WHITE, 0)
	round(finTop, UDim.new(0, 2))
	border(finTop, 1.5, OUTLINE)
	local finBot = box(root, "FinBot", UDim2.fromOffset(2, 13), UDim2.fromOffset(8, 5), WHITE, 0)
	round(finBot, UDim.new(0, 2))
	border(finBot, 1.5, OUTLINE)

	local helmet =
		box(root, "Helmet", UDim2.new(0, 20, 0.5, 0), UDim2.fromOffset(11, 11), HELMET, 0, Vector2.new(0.5, 0.5))
	round(helmet, UDim.new(0.5, 0))
	border(helmet, 1.5, OUTLINE)

	local spear = box(root, "Spear", UDim2.new(0, 19, 0.5, 0), UDim2.fromOffset(16, 7), SPEAR, 0, Vector2.new(0, 0.5))
	round(spear, UDim.new(0.5, 0))
	border(spear, 1.5, OUTLINE)
	local tip = box(spear, "Tip", UDim2.fromScale(1, 0.5), UDim2.fromOffset(6, 7), RED, 0, Vector2.new(1, 0.5))
	round(tip, UDim.new(0.5, 0))
	spear.Visible = false

	local body = box(root, "Hull", UDim2.new(0, 4, 0.5, 0), UDim2.fromOffset(18, 12), RED, 0, Vector2.new(0, 0.5))
	round(body, UDim.new(0.5, 0))
	border(body, 2, OUTLINE)
	box(body, "Stripe", UDim2.fromOffset(5, 0), UDim2.new(0, 3, 1, 0), STRIPE, 0)
	local win = box(body, "Window", UDim2.new(0, 12, 0.5, 0), UDim2.fromOffset(5, 5), WINDOW, 0, Vector2.new(0.5, 0.5))
	round(win, UDim.new(0.5, 0))

	return {
		root = root,
		helmet = helmet,
		spear = spear,
		flameEdge = flameEdge,
		flameMid = flameMid,
	}
end

local function setShipBoost(ship: MiniShip, boosting: boolean, flameLen: number, slingshot: boolean?)
	ship.helmet.Visible = not boosting
	ship.spear.Visible = boosting
	local edgeColor = if slingshot then DIVE_BLUE elseif boosting then BOOST_EDGE else FLAME_EDGE
	local midColor = if slingshot then ORBIT_CYAN elseif boosting then BOOST_MID else FLAME_MID
	ship.flameEdge.BackgroundColor3 = edgeColor
	ship.flameMid.BackgroundColor3 = midColor
	ship.flameEdge.Size = UDim2.fromOffset(flameLen, if boosting then 12 else 9)
	ship.flameMid.Size = UDim2.fromOffset(math.round(flameLen * 0.65), if boosting then 7 else 5)
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

-- Crisp geometric "+" icon built from two rounded bars (no unicode stand-ins).
local function makePlus(parent: Instance, pos: UDim2, size: number, color: Color3): Frame
	local holder = box(parent, "Plus", pos, UDim2.fromOffset(size, size), color, 1, Vector2.new(0.5, 0.5))
	local thick = math.max(3, math.round(size * 0.32))
	local h =
		box(holder, "H", UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(size, thick), color, 0, Vector2.new(0.5, 0.5))
	round(h, UDim.new(0.5, 0))
	local v =
		box(holder, "V", UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(thick, size), color, 0, Vector2.new(0.5, 0.5))
	round(v, UDim.new(0.5, 0))
	return holder
end

local function defaultScheme(): Scheme
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Touch"
	end
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return "Touch"
	end
	return "PC"
end

local function applyScheme(self: ControlsPanel, scheme: Scheme)
	self._scheme = scheme
	local touch = scheme == "Touch"
	self._touchTab.BackgroundColor3 = if touch then GOLD else STAGE
	self._touchTab.TextColor3 = if touch then CARD else SUBTEXT
	self._pcTab.BackgroundColor3 = if not touch then GOLD else STAGE
	self._pcTab.TextColor3 = if not touch then CARD else SUBTEXT

	self._touchSteer.Visible = touch
	self._pcSteer.Visible = not touch
	self._touchBoost.Visible = touch
	self._pcBoost.Visible = not touch

	if touch then
		self._steerTitle.Text = "LEFT HALF · STEER"
		self._steerBody.Text = "Drag anywhere on left side.\nRelease to brake."
		self._boostTitle.Text = "RIGHT HALF · BOOST"
		self._boostBody.Text = "Tap right side to spear.\nHold to keep pushing."
	else
		self._steerTitle.Text = "CURSOR · STEER"
		self._steerBody.Text = "Point cursor to steer.\nRight-click or Shift brakes."
		self._boostTitle.Text = "CLICK / SPACE · BOOST"
		self._boostBody.Text = "Click or Space to spear.\nHold to keep pushing."
	end
end

function ControlsPanel.new(parent: Instance): ControlsPanel
	local gui = Instance.new("ScreenGui")
	gui.Name = "ControlsPanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 11
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.Enabled = false

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = BACKDROP
	backdrop.BackgroundTransparency = 0.35
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = gui

	-- Sink clicks inside the card so tapping the card surface doesn't trigger backdrop close
	local card = Instance.new("TextButton")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y)
	card.BackgroundColor3 = CARD
	card.Text = ""
	card.AutoButtonColor = false
	round(card, UDim.new(0, 16))
	border(card, 4, OUTLINE)
	card.Parent = backdrop

	local fit = Instance.new("UIScale")
	fit.Parent = card

	-- Header + Touch/PC switcher
	local heading =
		makeText(card, "Heading", Fonts.Display, 26, GOLD, UDim2.fromOffset(20, 14), UDim2.fromOffset(420, 32))
	heading.Text = "CONTROLS & CORE MOVES"

	local switcher =
		box(card, "Switcher", UDim2.new(1, -20, 0, 14), UDim2.fromOffset(176, 32), STAGE, 0, Vector2.new(1, 0))
	round(switcher, UDim.new(0.5, 0))
	border(switcher, 2, OUTLINE)

	local function tabButton(name: string, labelText: string, xScale: number): TextButton
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.Position = UDim2.new(xScale, 2, 0, 2)
		btn.Size = UDim2.new(0.5, -4, 1, -4)
		btn.FontFace = Fonts.TextBold
		btn.TextSize = 14
		btn.Text = labelText
		btn.AutoButtonColor = false
		round(btn, UDim.new(0.5, 0))
		btn.Parent = switcher
		return btn
	end
	local touchTab = tabButton("TouchTab", "TOUCH", 0)
	local pcTab = tabButton("PcTab", "MOUSE / KB", 0.5)

	-- Row 1: Steer & Boost boxes (2 × 342 × 114)
	local steerCard = box(card, "SteerCard", UDim2.fromOffset(20, 56), UDim2.fromOffset(342, 114), STAGE, 0)
	round(steerCard, UDim.new(0, 12))
	border(steerCard, 2, STAGE_BORDER)

	local boostCard = box(card, "BoostCard", UDim2.fromOffset(374, 56), UDim2.fromOffset(342, 114), STAGE, 0)
	round(boostCard, UDim.new(0, 12))
	border(boostCard, 2, STAGE_BORDER)

	local steerStage = box(steerCard, "Stage", UDim2.fromOffset(10, 10), UDim2.fromOffset(132, 94), BACKDROP, 0)
	round(steerStage, UDim.new(0, 10))
	steerStage.ClipsDescendants = true

	local boostStage = box(boostCard, "Stage", UDim2.fromOffset(10, 10), UDim2.fromOffset(132, 94), BACKDROP, 0)
	round(boostStage, UDim.new(0, 10))
	boostStage.ClipsDescendants = true

	local steerTitle =
		makeText(steerCard, "Title", Fonts.Display, 19, WHITE, UDim2.fromOffset(152, 16), UDim2.fromOffset(180, 24))
	local steerBody =
		makeText(steerCard, "Body", Fonts.Text, 15, SUBTEXT, UDim2.fromOffset(152, 44), UDim2.fromOffset(180, 58))

	local boostTitle =
		makeText(boostCard, "Title", Fonts.Display, 19, GOLD, UDim2.fromOffset(152, 16), UDim2.fromOffset(180, 24))
	local boostBody =
		makeText(boostCard, "Body", Fonts.Text, 15, SUBTEXT, UDim2.fromOffset(152, 44), UDim2.fromOffset(180, 58))

	-- Touch Steer diagram: left-half highlight + floating stick + ship
	local touchSteer = box(steerStage, "TouchSteer", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), WHITE, 1)
	box(touchSteer, "LeftTint", UDim2.fromOffset(0, 0), UDim2.fromScale(0.5, 1), ORBIT_CYAN, 0.9)
	box(touchSteer, "Split", UDim2.fromScale(0.5, 0.1), UDim2.new(0, 2, 0.8, 0), WHITE, 0.75)
	local stickBase = box(
		touchSteer,
		"StickBase",
		UDim2.fromOffset(34, 54),
		UDim2.fromOffset(38, 38),
		WHITE,
		0.78,
		Vector2.new(0.5, 0.5)
	)
	round(stickBase, UDim.new(0.5, 0))
	border(stickBase, 2, WHITE, 0.35)
	local stickKnob =
		box(stickBase, "Knob", UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(16, 16), WHITE, 0.15, Vector2.new(0.5, 0.5))
	round(stickKnob, UDim.new(0.5, 0))
	local touchSteerShip = makeMiniShip(touchSteer, UDim2.fromOffset(96, 46), 0.9)

	-- PC Steer diagram: ship following cursor reticle + RMB tag
	local pcSteer = box(steerStage, "PcSteer", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), WHITE, 1)
	local pcSteerShip = makeMiniShip(pcSteer, UDim2.fromOffset(42, 50), 0.9)
	local reticle =
		box(pcSteer, "Reticle", UDim2.fromOffset(98, 36), UDim2.fromOffset(22, 22), GOLD, 1, Vector2.new(0.5, 0.5))
	round(reticle, UDim.new(0.5, 0))
	border(reticle, 2, GOLD, 0.1)
	local retDot =
		box(reticle, "Dot", UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(5, 5), GOLD, 0, Vector2.new(0.5, 0.5))
	round(retDot, UDim.new(0.5, 0))
	local rmbBadge = box(pcSteer, "Rmb", UDim2.fromOffset(8, 68), UDim2.fromOffset(58, 20), CARD, 0)
	round(rmbBadge, UDim.new(0, 6))
	border(rmbBadge, 1.5, SUBTEXT, 0.3)
	local rmbText = makeText(
		rmbBadge,
		"Text",
		Fonts.TextBold,
		11,
		SUBTEXT,
		UDim2.fromOffset(0, 3),
		UDim2.fromScale(1, 1),
		Enum.TextXAlignment.Center
	)
	rmbText.Text = "RMB BRAKE"

	-- Touch Boost diagram: right-half highlight + tap ripple + spear ship
	local touchBoost = box(boostStage, "TouchBoost", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), WHITE, 1)
	box(touchBoost, "RightTint", UDim2.fromScale(0.5, 0), UDim2.fromScale(0.5, 1), GOLD, 0.9)
	box(touchBoost, "Split", UDim2.fromScale(0.5, 0.1), UDim2.new(0, 2, 0.8, 0), WHITE, 0.75)
	local tapRipple =
		box(touchBoost, "Ripple", UDim2.fromOffset(98, 60), UDim2.fromOffset(28, 28), GOLD, 0.65, Vector2.new(0.5, 0.5))
	round(tapRipple, UDim.new(0.5, 0))
	local tapRippleStroke = border(tapRipple, 2.5, GOLD, 0.1)
	local touchBoostShip = makeMiniShip(touchBoost, UDim2.fromOffset(44, 34), 0.95)

	-- PC Boost diagram: LMB / SPACE keycaps + spear ship
	local pcBoost = box(boostStage, "PcBoost", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), WHITE, 1)
	local pcBoostShip = makeMiniShip(pcBoost, UDim2.fromOffset(66, 30), 0.95)
	local clickCap = box(pcBoost, "Click", UDim2.fromOffset(12, 60), UDim2.fromOffset(48, 24), CARD, 0)
	round(clickCap, UDim.new(0, 6))
	border(clickCap, 2, GOLD, 0.15)
	local clickText = makeText(
		clickCap,
		"Text",
		Fonts.TextBold,
		12,
		WHITE,
		UDim2.fromOffset(0, 4),
		UDim2.fromScale(1, 1),
		Enum.TextXAlignment.Center
	)
	clickText.Text = "CLICK"
	local spaceCap = box(pcBoost, "Space", UDim2.fromOffset(66, 60), UDim2.fromOffset(56, 24), CARD, 0)
	round(spaceCap, UDim.new(0, 6))
	border(spaceCap, 2, GOLD, 0.15)
	local spaceText = makeText(
		spaceCap,
		"Text",
		Fonts.TextBold,
		12,
		WHITE,
		UDim2.fromOffset(0, 4),
		UDim2.fromScale(1, 1),
		Enum.TextXAlignment.Center
	)
	spaceText.Text = "SPACE"

	-- Row 2: 3 Core Moves (3 × 224 × 106)
	local function moveCard(index: number, titleText: string, titleColor: Color3, bodyText: string): Frame
		local x = 20 + (index - 1) * (224 + 12)
		local tile = box(card, `Move{index}`, UDim2.fromOffset(x, 180), UDim2.fromOffset(224, 106), STAGE, 0)
		round(tile, UDim.new(0, 12))
		border(tile, 2, STAGE_BORDER)

		local stage = box(tile, "Stage", UDim2.fromOffset(8, 8), UDim2.fromOffset(92, 90), BACKDROP, 0)
		round(stage, UDim.new(0, 9))
		stage.ClipsDescendants = true

		local t =
			makeText(tile, "Title", Fonts.Display, 19, titleColor, UDim2.fromOffset(108, 13), UDim2.fromOffset(110, 24))
		t.Text = titleText
		local b = makeText(tile, "Body", Fonts.Text, 13, SUBTEXT, UDim2.fromOffset(108, 39), UDim2.fromOffset(110, 58))
		b.Text = bodyText
		return stage
	end

	-- Move 1: PUSH (flame washes rock -> turns pink)
	local pushStage = moveCard(1, "PUSH", FLAME_MID, "Exhaust primes\nrocks pink")
	local pushShip = makeMiniShip(pushStage, UDim2.fromOffset(28, 45), 0.78)
	pushShip.root.Rotation = 180 -- nose left so exhaust streams right onto the rock
	pushShip.flameEdge.Visible = false
	pushShip.flameMid.Visible = false
	local pushFlame = box(
		pushStage,
		"Cone",
		UDim2.fromOffset(38, 45),
		UDim2.fromOffset(34, 18),
		FLAME_EDGE,
		0.15,
		Vector2.new(0, 0.5)
	)
	round(pushFlame, UDim.new(0.5, 0))
	local pushRock =
		box(pushStage, "Rock", UDim2.fromOffset(72, 45), UDim2.fromOffset(20, 20), ROCK_BROWN, 0, Vector2.new(0.5, 0.5))
	round(pushRock, UDim.new(0.5, 0))
	local pushRockStroke = border(pushRock, 2.5, OUTLINE)

	-- Move 2: BREAK (spear breaks pink rock -> green +3% heal)
	local breakStage = moveCard(2, "BREAK", SPEAR, "Spear pink rocks\nto repair +3%")
	local breakRock =
		box(breakStage, "Rock", UDim2.fromOffset(66, 48), UDim2.fromOffset(20, 20), PRIMED, 0, Vector2.new(0.5, 0.5))
	round(breakRock, UDim.new(0.5, 0))
	border(breakRock, 2.5, PRIMED)
	local breakShip = makeMiniShip(breakStage, UDim2.fromOffset(30, 48), 0.8)
	setShipBoost(breakShip, true, 14)
	local breakHeal = makePlus(breakStage, UDim2.fromOffset(66, 22), 14, PLANET_LAND)

	-- Move 3: SLINGSHOT (skim planet onto cyan orbit -> launch blue spear dive into pink rock -> +6%)
	local diveStage = moveCard(3, "SLINGSHOT", ORBIT_CYAN, "Skim planet, then\naim out to dive\npink rocks (+6%)")
	local orbitRing = box(
		diveStage,
		"Orbit",
		UDim2.fromOffset(ORBIT_CENTER.X, ORBIT_CENTER.Y),
		UDim2.fromOffset(ORBIT_RADIUS * 2, ORBIT_RADIUS * 2),
		ORBIT_CYAN,
		1,
		Vector2.new(0.5, 0.5)
	)
	round(orbitRing, UDim.new(0.5, 0))
	local orbitStroke = border(orbitRing, 2, ORBIT_CYAN, 0.15)
	local miniPlanet = box(
		diveStage,
		"Planet",
		UDim2.fromOffset(ORBIT_CENTER.X, ORBIT_CENTER.Y),
		UDim2.fromOffset(24, 24),
		PLANET_OCEAN,
		0,
		Vector2.new(0.5, 0.5)
	)
	round(miniPlanet, UDim.new(0.5, 0))
	border(miniPlanet, 2, OUTLINE)
	local land = box(miniPlanet, "Land", UDim2.fromOffset(5, 6), UDim2.fromOffset(10, 8), PLANET_LAND, 0)
	round(land, UDim.new(0.5, 0))

	local diveStreak = box(
		diveStage,
		"Streak",
		UDim2.fromOffset(47, 68),
		UDim2.fromOffset(20, 7),
		DIVE_BLUE,
		0.15,
		Vector2.new(0.5, 0.5)
	)
	round(diveStreak, UDim.new(0.5, 0))
	local diveStreakCore = box(
		diveStage,
		"StreakCore",
		UDim2.fromOffset(47, 68),
		UDim2.fromOffset(14, 3),
		ORBIT_CYAN,
		0.05,
		Vector2.new(0.5, 0.5)
	)
	round(diveStreakCore, UDim.new(0.5, 0))

	local exitRad = math.rad(DIVE_EXIT_DEG)
	local headRad = math.rad(DIVE_HEADING_DEG)
	local rockX = ORBIT_CENTER.X + ORBIT_RADIUS * math.cos(exitRad) + 48 * math.cos(headRad)
	local rockY = ORBIT_CENTER.Y + ORBIT_RADIUS * math.sin(exitRad) + 48 * math.sin(headRad)
	local diveRock = box(
		diveStage,
		"Rock",
		UDim2.fromOffset(rockX, rockY),
		UDim2.fromOffset(18, 18),
		PRIMED,
		0,
		Vector2.new(0.5, 0.5)
	)
	round(diveRock, UDim.new(0.5, 0))
	border(diveRock, 2, PRIMED)
	local rockDot =
		box(diveRock, "Dot", UDim2.fromScale(0.36, 0.38), UDim2.fromOffset(4, 4), WHITE, 0.5, Vector2.new(0.5, 0.5))
	round(rockDot, UDim.new(0.5, 0))

	local diveShip = makeMiniShip(diveStage, UDim2.fromOffset(30, 78), 0.68)
	local divePlus = makePlus(diveStage, UDim2.fromOffset(55, 14), 11, PLANET_LAND)
	local diveHeal = makeText(
		diveStage,
		"PerfectTag",
		Fonts.Display,
		13,
		GOLD,
		UDim2.fromOffset(63, 6),
		UDim2.fromOffset(26, 16),
		Enum.TextXAlignment.Left
	)
	diveHeal.Text = "+6%"

	-- Primary CTA button
	local cta = Instance.new("TextButton")
	cta.Name = "Action"
	cta.AnchorPoint = Vector2.new(0.5, 1)
	cta.Position = UDim2.new(0.5, 0, 1, -14)
	cta.Size = UDim2.fromOffset(230, 46)
	cta.BackgroundColor3 = GOLD
	cta.Text = ""
	cta.AutoButtonColor = true
	round(cta, UDim.new(0.5, 0))
	border(cta, 3, OUTLINE)
	cta.Parent = card

	local ctaLabel = makeText(
		cta,
		"Label",
		Fonts.Display,
		22,
		CARD,
		UDim2.fromOffset(0, 10),
		UDim2.new(1, 0, 0, 26),
		Enum.TextXAlignment.Center
	)

	local self = setmetatable({
		_gui = gui,
		_scheme = defaultScheme(),
		_manualScheme = false,
		_suppressed = false,
		_onDone = nil :: (() -> ())?,
		_ctaLabel = ctaLabel,
		_touchTab = touchTab,
		_pcTab = pcTab,
		_steerTitle = steerTitle,
		_steerBody = steerBody,
		_boostTitle = boostTitle,
		_boostBody = boostBody,
		_touchSteer = touchSteer,
		_pcSteer = pcSteer,
		_touchBoost = touchBoost,
		_pcBoost = pcBoost,
		_stickKnob = stickKnob,
		_touchSteerShip = touchSteerShip,
		_cursorReticle = reticle,
		_pcSteerShip = pcSteerShip,
		_tapRipple = tapRipple,
		_tapRippleStroke = tapRippleStroke,
		_touchBoostShip = touchBoostShip,
		_clickCap = clickCap,
		_spaceCap = spaceCap,
		_pcBoostShip = pcBoostShip,
		_pushFlame = pushFlame,
		_pushRock = pushRock,
		_pushRockStroke = pushRockStroke,
		_breakShip = breakShip,
		_breakRock = breakRock,
		_breakHeal = breakHeal,
		_orbitStroke = orbitStroke,
		_diveStreak = diveStreak,
		_diveStreakCore = diveStreakCore,
		_diveShip = diveShip,
		_diveRock = diveRock,
		_divePlus = divePlus,
		_diveHeal = diveHeal,
	}, ControlsPanel)

	local function finish()
		local callback = self._onDone
		if callback then
			self._onDone = nil
			self._gui.Enabled = false
			callback()
		end
	end

	cta.Activated:Connect(finish)
	backdrop.Activated:Connect(finish)

	touchTab.Activated:Connect(function()
		self._manualScheme = true
		applyScheme(self, "Touch")
	end)
	pcTab.Activated:Connect(function()
		self._manualScheme = true
		applyScheme(self, "PC")
	end)

	UserInputService.LastInputTypeChanged:Connect(function(last: Enum.UserInputType)
		if self._manualScheme then
			return
		end
		if last == Enum.UserInputType.Touch then
			applyScheme(self, "Touch")
		elseif last == Enum.UserInputType.MouseMovement or last == Enum.UserInputType.Keyboard then
			applyScheme(self, "PC")
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not self._gui.Enabled or processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			finish()
		end
	end)

	local function refit()
		local size = gui.AbsoluteSize
		local wide = (PANEL_SIZE.X + 28) / math.max(1, size.X)
		local tall = (PANEL_SIZE.Y + 24) / math.max(1, size.Y)
		fit.Scale = math.min(1, 1 / math.max(wide, tall))
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	refit()
	applyScheme(self, self._scheme)
	gui.Parent = parent
	return self
end

function ControlsPanel.Show(self: ControlsPanel, actionText: string, onDone: () -> ())
	self._manualScheme = false
	applyScheme(self, defaultScheme())
	self._ctaLabel.Text = actionText
	self._onDone = onDone
	self._gui.Enabled = not self._suppressed
end

function ControlsPanel.Hide(self: ControlsPanel)
	self._onDone = nil
	self._gui.Enabled = false
end

function ControlsPanel.Close(self: ControlsPanel)
	local callback = self._onDone
	if callback then
		self._onDone = nil
		self._gui.Enabled = false
		callback()
	end
end

function ControlsPanel.IsOpen(self: ControlsPanel): boolean
	return self._onDone ~= nil
end

function ControlsPanel.SetSuppressed(self: ControlsPanel, suppressed: boolean)
	self._suppressed = suppressed
	self._gui.Enabled = not suppressed and self._onDone ~= nil
end

function ControlsPanel.Update(self: ControlsPanel, now: number)
	if not self._gui.Enabled then
		return
	end
	local phase = (now % PERIOD) / PERIOD
	local wave = math.sin(phase * 2 * math.pi)
	local pulse = 0.5 + 0.5 * wave

	-- Steer animations
	local drag = math.clamp(phase / 0.7, 0, 1)
	local eased = 1 - (1 - drag) ^ 2
	self._stickKnob.Position = UDim2.new(0.5, 11 * eased, 0.5, -5 * eased)
	setShipBoost(self._touchSteerShip, false, 8 + 7 * eased)
	self._touchSteerShip.root.Position = UDim2.fromOffset(86 + 18 * eased, 52 - 10 * eased)
	self._touchSteerShip.root.Rotation = -18

	local cursorY = 47 + 16 * wave
	self._cursorReticle.Position = UDim2.fromOffset(102, cursorY)
	self._pcSteerShip.root.Position = UDim2.fromOffset(48, 47 + 11 * wave)
	self._pcSteerShip.root.Rotation = 14 * math.cos(phase * 2 * math.pi)
	setShipBoost(self._pcSteerShip, false, 12)

	-- Boost animations
	local boosting = phase < 0.55
	local boostDash = if boosting then math.min(1, phase / 0.35) else 0
	local rippleSize = 18 + 24 * math.min(1, phase / 0.5)
	self._tapRipple.Size = UDim2.fromOffset(rippleSize, rippleSize)
	self._tapRipple.BackgroundTransparency = if boosting then 0.5 + 0.45 * boostDash else 1
	self._tapRippleStroke.Transparency = if boosting then 0.85 * boostDash else 1
	setShipBoost(self._touchBoostShip, boosting, if boosting then 20 else 9)
	self._touchBoostShip.root.Position = UDim2.fromOffset(34 + 24 * boostDash, 36)

	self._clickCap.BackgroundColor3 = if boosting then GOLD else CARD
	self._spaceCap.BackgroundColor3 = if boosting then GOLD else CARD
	local clickLabel = self._clickCap:FindFirstChild("Text") :: TextLabel
	local spaceLabel = self._spaceCap:FindFirstChild("Text") :: TextLabel
	clickLabel.TextColor3 = if boosting then CARD else WHITE
	spaceLabel.TextColor3 = if boosting then CARD else WHITE
	setShipBoost(self._pcBoostShip, boosting, if boosting then 20 else 9)
	self._pcBoostShip.root.Position = UDim2.fromOffset(52 + 28 * boostDash, 30)

	-- Core move 1: Push primes rock pink
	local primed = phase > 0.35 and phase < 0.9
	self._pushFlame.Size = UDim2.fromOffset(24 + 14 * pulse, 14 + 6 * pulse)
	self._pushRock.BackgroundColor3 = if primed then PRIMED else ROCK_BROWN
	self._pushRockStroke.Color = if primed then PRIMED else OUTLINE
	self._pushRock.Position = UDim2.fromOffset(if primed then 76 else 70, 45)

	-- Core move 2: Spear breaks pink rock -> green + rises
	local hit = phase > 0.45
	local approach = math.clamp(phase / 0.45, 0, 1)
	self._breakShip.root.Position = UDim2.fromOffset(22 + 34 * approach, 50)
	self._breakRock.Visible = not hit
	self._breakHeal.Visible = hit
	local rise = math.clamp((phase - 0.45) / 0.45, 0, 1)
	self._breakHeal.Position = UDim2.fromOffset(68, 34 - 14 * rise)

	-- Core move 3: Slingshot (skim onto cyan orbit -> tangent blue spear dive -> +6% break)
	local sPhase = (now % SLINGSHOT_PERIOD) / SLINGSHOT_PERIOD
	local exitRad = math.rad(DIVE_EXIT_DEG)
	local exitX = ORBIT_CENTER.X + ORBIT_RADIUS * math.cos(exitRad)
	local exitY = ORBIT_CENTER.Y + ORBIT_RADIUS * math.sin(exitRad)
	local headRad = math.rad(DIVE_HEADING_DEG)
	local dirX = math.cos(headRad)
	local dirY = math.sin(headRad)

	if sPhase < 0.42 then
		local orbitT = sPhase / 0.42
		local thetaDeg = 135 - (135 - DIVE_EXIT_DEG) * orbitT
		local thetaRad = math.rad(thetaDeg)
		self._diveShip.root.Position = UDim2.fromOffset(
			ORBIT_CENTER.X + ORBIT_RADIUS * math.cos(thetaRad),
			ORBIT_CENTER.Y + ORBIT_RADIUS * math.sin(thetaRad)
		)
		self._diveShip.root.Rotation = thetaDeg - 90
		setShipBoost(self._diveShip, false, 10, false)
		self._orbitStroke.Transparency = 0.08
		self._diveStreak.Visible = false
		self._diveStreakCore.Visible = false
		self._diveRock.Visible = true
		self._divePlus.Visible = false
		self._diveHeal.Visible = false
	elseif sPhase < 0.74 then
		local diveU = (sPhase - 0.42) / 0.32
		local dash = 1 - (1 - diveU) ^ 2
		local s = 40 * dash
		self._diveShip.root.Position = UDim2.fromOffset(exitX + s * dirX, exitY + s * dirY)
		self._diveShip.root.Rotation = DIVE_HEADING_DEG
		setShipBoost(self._diveShip, true, 15, true)
		self._orbitStroke.Transparency = 0.42
		local len = math.max(3, s - 4)
		self._diveStreak.Visible = s > 4
		self._diveStreakCore.Visible = s > 8
		placeRay(self._diveStreak, exitX, exitY, len, 7, DIVE_HEADING_DEG)
		placeRay(self._diveStreakCore, exitX + 2 * dirX, exitY + 2 * dirY, math.max(2, len - 4), 3, DIVE_HEADING_DEG)
		self._diveRock.Visible = true
		self._divePlus.Visible = false
		self._diveHeal.Visible = false
	else
		local hitT = (sPhase - 0.74) / 0.26
		local s = 40 + 5 * hitT
		local stillSpearing = hitT < 0.55
		self._diveShip.root.Position = UDim2.fromOffset(exitX + s * dirX, exitY + s * dirY)
		self._diveShip.root.Rotation = DIVE_HEADING_DEG
		setShipBoost(self._diveShip, stillSpearing, if stillSpearing then 12 else 8, stillSpearing)
		self._orbitStroke.Transparency = 0.45

		local zip = math.min(1, hitT * 2)
		local startS = 36 * zip
		local remLen = 36 - startS
		self._diveStreak.Visible = remLen > 3
		self._diveStreakCore.Visible = remLen > 6
		if remLen > 3 then
			placeRay(self._diveStreak, exitX + startS * dirX, exitY + startS * dirY, remLen, 7, DIVE_HEADING_DEG)
		end
		if remLen > 6 then
			placeRay(
				self._diveStreakCore,
				exitX + (startS + 2) * dirX,
				exitY + (startS + 2) * dirY,
				remLen - 4,
				3,
				DIVE_HEADING_DEG
			)
		end

		self._diveRock.Visible = false
		self._divePlus.Visible = true
		self._diveHeal.Visible = true
		self._divePlus.Position = UDim2.fromOffset(55, 16 - 6 * hitT)
		self._diveHeal.Position = UDim2.fromOffset(63, 8 - 6 * hitT)
	end
end

return ControlsPanel
