--!strict
--[[
	UpgradeCards: the visual upgrade cards offered after a wave. Tap one to pick it.

	    local cards = UpgradeCards.new(playerGui, function(index) run:PickUpgrade(index) end)
	    cards:Update(snapshot, active, os.clock(), tuning.Waves.SurgeHeal)

	Each card leads with an animated 2D Toy Box diagram (UpgradeVisuals), a bold
	stat pill ("+20% REACH"), visual stack pips in the header, and a 1-line caption.
	The heading celebrates the cleared wave (or Surge Survived + heal %) so no
	separate wave-clear banner needs to stack behind the modal.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local KngChak = ReplicatedStorage.KngChak
local Run = require(KngChak.Run.Run)
local Upgrades = require(KngChak.Data.Upgrades)

local Fonts = require(script.Parent.Fonts)
local UpgradeVisuals = require(script.Parent.UpgradeVisuals)

local FAMILY_COLORS: { [string]: Color3 } = {
	Flame = Color3.fromHex("#ff4a1c"),
	Spear = Color3.fromHex("#f4f6ff"),
	Orbit = Color3.fromHex("#6ff3ff"),
	Any = Color3.fromHex("#ffd400"),
}
local FAMILY_LABELS: { [string]: string } = {
	Flame = "FLAME",
	Spear = "SPEAR",
	Orbit = "ORBIT",
	Any = "SHIELD",
}

local BACKDROP = Color3.fromHex("#14133d")
local CARD = Color3.fromHex("#1b1a5c")
local STAGE = Color3.fromHex("#12113a")
local OUTLINE = Color3.fromHex("#000000")
local GOLD = Color3.fromHex("#ffe066")
local SURGE_COLOR = Color3.fromHex("#ff9a1f")
local TEXT = Color3.fromHex("#ffffff")
local SUBTEXT = Color3.fromHex("#cbc9ff")
local PIP_EMPTY = Color3.fromHex("#2c2a75")

local CARD_SIZE = Vector2.new(204, 270)
local GAP = 18
local MAX_PIPS = 3
local LOOP_PERIOD = 1.6

type Card = {
	button: TextButton,
	border: UIStroke,
	family: TextLabel,
	pips: { Frame },
	pipStrokes: { UIStroke },
	stageBorder: UIStroke,
	visual: UpgradeVisuals.UpgradeVisuals,
	statPill: Frame,
	statText: TextLabel,
	name: TextLabel,
	caption: TextLabel,
	scale: UIScale,
	taken: number,
	maxStacks: number,
	color: Color3,
}

local UpgradeCards = {}
UpgradeCards.__index = UpgradeCards

export type UpgradeCards = typeof(setmetatable(
	{} :: {
		_gui: ScreenGui,
		_heading: TextLabel,
		_cards: { Card },
		_shown: string?, -- the offer on screen, as one key, so a new offer redraws
		_onPick: (index: number) -> (),
	},
	UpgradeCards
))

local function round(parent: Instance, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

local function makeBorder(parent: Instance, thickness: number, color: Color3): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = color
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function makeLabel(
	parent: Instance,
	name: string,
	font: Font,
	size: number,
	color: Color3,
	pos: UDim2,
	area: UDim2,
	alignX: Enum.TextXAlignment
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
	label.TextXAlignment = alignX
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	return label
end

local function makeCard(parent: Instance, index: number, onPick: (number) -> ()): Card
	local button = Instance.new("TextButton")
	button.Name = `Card{index}`
	button.Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y)
	button.BackgroundColor3 = CARD
	button.AutoButtonColor = true
	button.Text = ""
	button.LayoutOrder = index
	round(button, UDim.new(0, 16))
	local cardBorder = makeBorder(button, 4, OUTLINE)

	local scale = Instance.new("UIScale")
	scale.Parent = button

	-- Header row: family label on the left, visual stack pips on the right
	local family = makeLabel(
		button,
		"Family",
		Fonts.TextBold,
		14,
		GOLD,
		UDim2.fromOffset(14, 10),
		UDim2.fromOffset(96, 20),
		Enum.TextXAlignment.Left
	)

	local pipRow = Instance.new("Frame")
	pipRow.Name = "Pips"
	pipRow.AnchorPoint = Vector2.new(1, 0)
	pipRow.Position = UDim2.new(1, -14, 0, 12)
	pipRow.Size = UDim2.fromOffset(64, 16)
	pipRow.BackgroundTransparency = 1
	pipRow.Parent = button

	local pipLayout = Instance.new("UIListLayout")
	pipLayout.FillDirection = Enum.FillDirection.Horizontal
	pipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	pipLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	pipLayout.Padding = UDim.new(0, 6)
	pipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pipLayout.Parent = pipRow

	local pips: { Frame } = {}
	local pipStrokes: { UIStroke } = {}
	for p = 1, MAX_PIPS do
		local pip = Instance.new("Frame")
		pip.Name = `Pip{p}`
		pip.LayoutOrder = p
		pip.Size = UDim2.fromOffset(12, 12)
		pip.BackgroundColor3 = PIP_EMPTY
		pip.BorderSizePixel = 0
		round(pip, UDim.new(0.5, 0))
		local pipStroke = makeBorder(pip, 2, OUTLINE)
		pip.Parent = pipRow
		table.insert(pips, pip)
		table.insert(pipStrokes, pipStroke)
	end

	-- Hero diagram stage
	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.Position = UDim2.fromOffset(12, 34)
	stage.Size = UDim2.fromOffset(180, 110)
	stage.BackgroundColor3 = STAGE
	stage.BorderSizePixel = 0
	stage.ClipsDescendants = true
	round(stage, UDim.new(0, 12))
	local stageBorder = makeBorder(stage, 2, GOLD)
	stage.Parent = button

	-- High-contrast stat badge pill right under the diagram
	local statPill = Instance.new("Frame")
	statPill.Name = "StatPill"
	statPill.AnchorPoint = Vector2.new(0.5, 0)
	statPill.Position = UDim2.new(0.5, 0, 0, 152)
	statPill.Size = UDim2.fromOffset(172, 30)
	statPill.BackgroundColor3 = GOLD
	statPill.BorderSizePixel = 0
	round(statPill, UDim.new(0.5, 0))
	makeBorder(statPill, 2.5, OUTLINE)
	statPill.Parent = button

	local statText = makeLabel(
		statPill,
		"Stat",
		Fonts.Display,
		17,
		CARD,
		UDim2.fromOffset(0, 0),
		UDim2.fromScale(1, 1),
		Enum.TextXAlignment.Center
	)

	-- Upgrade title + concise 1-line caption
	local name = makeLabel(
		button,
		"Name",
		Fonts.Display,
		22,
		TEXT,
		UDim2.fromOffset(12, 190),
		UDim2.new(1, -24, 0, 30),
		Enum.TextXAlignment.Center
	)
	local caption = makeLabel(
		button,
		"Caption",
		Fonts.Text,
		15,
		SUBTEXT,
		UDim2.fromOffset(10, 222),
		UDim2.new(1, -20, 0, 36),
		Enum.TextXAlignment.Center
	)

	button.Activated:Connect(function()
		onPick(index)
	end)
	button.Parent = parent

	return {
		button = button,
		border = cardBorder,
		family = family,
		pips = pips,
		pipStrokes = pipStrokes,
		stageBorder = stageBorder,
		visual = UpgradeVisuals.new(stage),
		statPill = statPill,
		statText = statText,
		name = name,
		caption = caption,
		scale = scale,
		taken = 0,
		maxStacks = 1,
		color = GOLD,
	}
end

function UpgradeCards.new(parent: Instance, onPick: (index: number) -> ()): UpgradeCards
	local gui = Instance.new("ScreenGui")
	gui.Name = "UpgradeCards"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.ScreenInsets = Enum.ScreenInsets.None -- the dim covers the whole screen; the container fits mid-screen
	gui.Enabled = false

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = BACKDROP
	dim.BackgroundTransparency = 0.35
	dim.BorderSizePixel = 0
	dim.Parent = gui

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.Size = UDim2.fromOffset(CARD_SIZE.X * 3 + GAP * 2, CARD_SIZE.Y + 56)
	container.BackgroundTransparency = 1
	container.Parent = gui

	local fit = Instance.new("UIScale")
	fit.Parent = container

	local heading = Instance.new("TextLabel")
	heading.Name = "Heading"
	heading.AnchorPoint = Vector2.new(0.5, 0)
	heading.Position = UDim2.fromScale(0.5, 0)
	heading.Size = UDim2.new(1, 0, 0, 42)
	heading.BackgroundTransparency = 1
	heading.FontFace = Fonts.Display
	heading.TextSize = 32
	heading.TextColor3 = GOLD
	heading.TextStrokeTransparency = 0.25
	heading.Text = "PICK AN UPGRADE"
	heading.Parent = container

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.fromScale(0.5, 1)
	row.Size = UDim2.fromOffset(CARD_SIZE.X * 3 + GAP * 2, CARD_SIZE.Y)
	row.BackgroundTransparency = 1
	row.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local self = setmetatable({
		_gui = gui,
		_heading = heading,
		_cards = {},
		_shown = nil :: string?,
		_onPick = onPick,
	}, UpgradeCards)

	for index = 1, Upgrades.OfferSize do
		table.insert(
			self._cards,
			makeCard(row, index, function(i)
				if self._gui.Enabled then
					self._onPick(i)
				end
			end)
		)
	end

	local function refit()
		local size = gui.AbsoluteSize
		local wide = (CARD_SIZE.X * 3 + GAP * 2 + 32) / math.max(1, size.X)
		local tall = (CARD_SIZE.Y + 84) / math.max(1, size.Y)
		fit.Scale = math.min(1, 1 / math.max(wide, tall))
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	refit()
	gui.Parent = parent
	return self
end

function UpgradeCards.Update(
	self: UpgradeCards,
	snapshot: Run.Snapshot,
	active: boolean,
	now: number,
	surgeHeal: number
)
	local offer = if active and snapshot.Phase == "UpgradePick" then snapshot.Offer else nil
	if not offer then
		self._shown = nil
		self._gui.Enabled = false
		return
	end

	local key = `{snapshot.Wave}:{table.concat(offer, ",")}`
	if self._shown ~= key then
		self._shown = key
		if snapshot.IsSurge then
			self._heading.Text = `SURGE SURVIVED (+{surgeHeal}% HP) · PICK AN UPGRADE`
			self._heading.TextColor3 = SURGE_COLOR
		elseif snapshot.Wave > 0 then
			self._heading.Text = `WAVE {snapshot.Wave} CLEAR · PICK AN UPGRADE`
			self._heading.TextColor3 = GOLD
		else
			self._heading.Text = "PICK AN UPGRADE"
			self._heading.TextColor3 = GOLD
		end

		for index, drawn in self._cards do
			local id = offer[index]
			drawn.button.Visible = id ~= nil
			if id then
				local upgrade = Upgrades.ById[id]
				local color = FAMILY_COLORS[upgrade.Family]
				drawn.color = color
				drawn.taken = snapshot.Upgrades[id] or 0
				drawn.maxStacks = upgrade.MaxStacks

				drawn.family.Text = FAMILY_LABELS[upgrade.Family] or string.upper(upgrade.Family)
				drawn.family.TextColor3 = color
				drawn.stageBorder.Color = color
				drawn.statPill.BackgroundColor3 = color
				drawn.statText.Text = upgrade.Stat
				drawn.name.Text = upgrade.Name
				drawn.caption.Text = upgrade.Text
				drawn.visual:SetUpgrade(id)

				for p = 1, MAX_PIPS do
					local pip = drawn.pips[p]
					pip.Visible = p <= upgrade.MaxStacks
				end

				drawn.scale.Scale = 0.65
				TweenService:Create(
					drawn.scale,
					TweenInfo.new(0.22 + 0.05 * index, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = 1 }
				):Play()
			end
		end
		self._gui.Enabled = true
	end

	-- Animate each visible card's diagram and pulse the stack pip this pick grants
	local phase = (now % LOOP_PERIOD) / LOOP_PERIOD
	local pipPulse = 0.5 + 0.5 * math.sin(phase * 2 * math.pi)
	for _, drawn in self._cards do
		if drawn.button.Visible then
			drawn.visual:Animate(phase)
			local nextPip = drawn.taken + 1
			for p = 1, drawn.maxStacks do
				local pip = drawn.pips[p]
				local pipStroke = drawn.pipStrokes[p]
				if p <= drawn.taken then
					pip.BackgroundColor3 = drawn.color
					pip.BackgroundTransparency = 0
					pipStroke.Color = OUTLINE
				elseif p == nextPip then
					pip.BackgroundColor3 = drawn.color
					pip.BackgroundTransparency = 0.45 * (1 - pipPulse)
					pipStroke.Color = GOLD
				else
					pip.BackgroundColor3 = PIP_EMPTY
					pip.BackgroundTransparency = 0
					pipStroke.Color = OUTLINE
				end
			end
		end
	end
end

return UpgradeCards
