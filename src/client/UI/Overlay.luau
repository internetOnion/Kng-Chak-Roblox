--!strict
--[[
	Overlay: Toy Box Title, Pause and Results menus in the brand fonts (#48).

	    local overlay = Overlay.new(playerGui, function() sounds:Play("UiClick") end)
	    overlay:ShowStart(onStart, onControls)
	    overlay:ShowPause(pauseStats, pauseActions)
	    overlay:ShowResults(summary, lastWave, resultsActions)
	    overlay:Hide()

	Uses Fonts.Display (FredokaOne, standing in for Atomic Age) with thick black
	strokes for headings, buttons and bold outlined stat numbers, and Fonts.TextBold
	(Montserrat, standing in for Jost) for crisp captions. Scales automatically via
	UIScale inside CoreUISafeInsets so small landscape phones stay spacious and clear
	of notches, Roblox's top-left button and the bottom DevBar.
]]

local Workspace = game:GetService("Workspace")

local Fonts = require(script.Parent.Fonts)

-- Toy Box UI palette from docs/art-guide.md
local SCRIM = Color3.fromHex("#14133d")
local CARD = Color3.fromHex("#1b1a5c")
local STAGE = Color3.fromHex("#12113a")
local STAGE_BORDER = Color3.fromHex("#2f2d80")
local OUTLINE = Color3.fromHex("#000000")
local WHITE = Color3.fromHex("#ffffff")
local SUBTEXT = Color3.fromHex("#d0ceff")
local GOLD = Color3.fromHex("#ffe066")
local RED = Color3.fromHex("#ff3b3b")
local CORAL = Color3.fromHex("#ff4d5e")
local GREEN = Color3.fromHex("#5ee05e")
local AMBER = Color3.fromHex("#ff9a1f")
local CYAN = Color3.fromHex("#6ff3ff")
local SHIELD_CYAN = Color3.fromHex("#bff6ff")
local PINK = Color3.fromHex("#ff4fd8")
local INDIGO = Color3.fromHex("#2f2d80")
local SLATE_INDIGO = Color3.fromHex("#23216b")

export type PauseInfo = {
	Wave: number,
	LastWave: number,
	IsBoss: boolean,
	PlanetHp: number,
	PlanetMaxHp: number,
	PlanetShield: number,
	Score: number,
}

export type PauseActions = {
	OnResume: () -> (),
	OnControls: () -> (),
	OnRestart: () -> (),
	OnTitle: () -> (),
}

export type ResultsSummary = {
	Won: boolean,
	Wave: number,
	Score: number,
	BestCombo: number,
	Perfects: number,
	Time: number,
}

export type ResultsActions = {
	OnPlayAgain: () -> (),
	OnControls: () -> (),
	OnTitle: () -> (),
}

type Mode = "None" | "Start" | "Pause" | "Results"

local Overlay = {}
Overlay.__index = Overlay

export type Overlay = typeof(setmetatable(
	{} :: {
		_scrimGui: ScreenGui,
		_safeGui: ScreenGui,
		_scrimButton: TextButton,
		_startView: Frame,
		_pauseCard: Frame,
		_resultsCard: Frame,
		_pauseWaveValue: TextLabel,
		_pauseHpValue: TextLabel,
		_pauseScoreValue: TextLabel,
		_resultsTitle: TextLabel,
		_resultsSub: TextLabel,
		_resultsScoreValue: TextLabel,
		_resultsComboValue: TextLabel,
		_resultsPerfectValue: TextLabel,
		_mode: Mode,
		_suppressed: boolean,
		_onClickSound: (() -> ())?,
		_onScrimTap: (() -> ())?,
		_actions: { [string]: (() -> ())? },
	},
	Overlay
))

local function round(parent: Instance, px: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, px)
	corner.Parent = parent
end

local function border(parent: Instance, thickness: number, color: Color3, mode: Enum.ApplyStrokeMode?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = color
	stroke.ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
	return stroke
end

local function formatInt(n: number): string
	local whole = tostring(math.floor(math.max(0, n) + 0.5))
	local formatted = string.gsub(whole, "^(-?%d+)(%d%d%d)", "%1,%2")
	while true do
		local nextStr, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = nextStr
		if count == 0 then
			break
		end
	end
	return formatted
end

local function formatClock(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

-- Builds a chunky Toy Box button with rounded corners, thick black border and glossy top sheen.
local function makeToyButton(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	fill: Color3,
	textSize: number,
	layoutOrder: number,
	onTap: () -> ()
): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.LayoutOrder = layoutOrder
	btn.Size = size
	btn.BackgroundColor3 = fill
	btn.AutoButtonColor = true
	btn.Text = ""
	round(btn, 14)
	border(btn, 3.5, OUTLINE, Enum.ApplyStrokeMode.Border)

	-- Moulded plastic top highlight strip
	local sheen = Instance.new("Frame")
	sheen.Name = "Sheen"
	sheen.AnchorPoint = Vector2.new(0.5, 0)
	sheen.Position = UDim2.new(0.5, 0, 0, 4)
	sheen.Size = UDim2.new(1, -16, 0, 6)
	sheen.BackgroundColor3 = WHITE
	sheen.BackgroundTransparency = 0.78
	sheen.BorderSizePixel = 0
	round(sheen, 4)
	sheen.Parent = btn

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = Fonts.Display
	label.Text = text
	label.TextSize = textSize
	label.TextColor3 = WHITE
	border(label, 2.5, OUTLINE, Enum.ApplyStrokeMode.Contextual)
	label.Parent = btn

	btn.Activated:Connect(onTap)
	btn.Parent = parent
	return btn
end

local function makeStatCell(
	parent: Instance,
	name: string,
	caption: string,
	valueColor: Color3,
	order: number
): TextLabel
	local cell = Instance.new("Frame")
	cell.Name = name
	cell.LayoutOrder = order
	cell.Size = UDim2.new(0.32, -6, 1, 0)
	cell.BackgroundColor3 = STAGE
	round(cell, 12)
	border(cell, 2, STAGE_BORDER, Enum.ApplyStrokeMode.Border)
	cell.Parent = parent

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.AnchorPoint = Vector2.new(0.5, 0)
	value.Position = UDim2.new(0.5, 0, 0, 8)
	value.Size = UDim2.new(1, -10, 0, 38)
	value.BackgroundTransparency = 1
	value.FontFace = Fonts.Display
	value.TextSize = 30
	value.TextScaled = true
	value.TextColor3 = valueColor
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 30
	constraint.MinTextSize = 16
	constraint.Parent = value
	border(value, 2.8, OUTLINE, Enum.ApplyStrokeMode.Contextual)
	value.Parent = cell

	local label = Instance.new("TextLabel")
	label.Name = "Caption"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -8)
	label.Size = UDim2.new(1, -8, 0, 18)
	label.BackgroundTransparency = 1
	label.FontFace = Fonts.TextBold
	label.Text = caption
	label.TextSize = 13
	label.TextColor3 = SUBTEXT
	label.Parent = cell

	return value
end

function Overlay.new(parent: Instance, onClickSound: (() -> ())?): Overlay
	-- Full-bleed scrim Gui (covers notches cleanly without shifting safe-inset layout)
	local scrimGui = Instance.new("ScreenGui")
	scrimGui.Name = "OverlayScrim"
	scrimGui.ResetOnSpawn = false
	scrimGui.DisplayOrder = 9
	scrimGui.ScreenInsets = Enum.ScreenInsets.None
	scrimGui.Enabled = false

	local scrimButton = Instance.new("TextButton")
	scrimButton.Name = "Scrim"
	scrimButton.Size = UDim2.fromScale(1, 1)
	scrimButton.BackgroundColor3 = SCRIM
	scrimButton.BackgroundTransparency = 0.68
	scrimButton.Text = ""
	scrimButton.AutoButtonColor = false
	scrimButton.Parent = scrimGui

	-- Safe-area Gui for crisp Toy Box menus and adaptive phone scaling
	local safeGui = Instance.new("ScreenGui")
	safeGui.Name = "Overlay"
	safeGui.ResetOnSpawn = false
	safeGui.DisplayOrder = 10
	safeGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	safeGui.Enabled = false

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = safeGui

	local uiScale = Instance.new("UIScale")
	uiScale.Parent = root

	local function updateScale()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local vp = cam.ViewportSize
		if vp.X > 0 and vp.Y > 0 then
			uiScale.Scale = math.clamp(math.min(vp.X / 812, vp.Y / 390), 0.72, 1.12)
		end
	end
	updateScale()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local cam = Workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
			updateScale()
		end
	end)
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	local actions: { [string]: (() -> ())? } = {}
	local self = setmetatable({
		_scrimGui = scrimGui,
		_safeGui = safeGui,
		_scrimButton = scrimButton,
		_startView = nil :: any,
		_pauseCard = nil :: any,
		_resultsCard = nil :: any,
		_pauseWaveValue = nil :: any,
		_pauseHpValue = nil :: any,
		_pauseScoreValue = nil :: any,
		_resultsTitle = nil :: any,
		_resultsSub = nil :: any,
		_resultsScoreValue = nil :: any,
		_resultsComboValue = nil :: any,
		_resultsPerfectValue = nil :: any,
		_mode = "None" :: Mode,
		_suppressed = false,
		_onClickSound = onClickSound,
		_onScrimTap = nil :: (() -> ())?,
		_actions = actions,
	}, Overlay)

	local function fire(key: string)
		local fn = self._actions[key]
		if not fn then
			return
		end
		if self._onClickSound then
			self._onClickSound()
		end
		fn()
	end

	scrimButton.Activated:Connect(function()
		local fn = self._onScrimTap
		if fn then
			if self._onClickSound then
				self._onClickSound()
			end
			fn()
		end
	end)

	-- =========================================================================
	-- 1. TITLE SCREEN (framed around the live spinning Ember globe in centre)
	-- =========================================================================
	local startView = Instance.new("Frame")
	startView.Name = "StartView"
	startView.Size = UDim2.fromScale(1, 1)
	startView.BackgroundTransparency = 1
	startView.Visible = false
	startView.Parent = root

	local heroHeader = Instance.new("Frame")
	heroHeader.Name = "HeroHeader"
	heroHeader.AnchorPoint = Vector2.new(0.5, 0)
	heroHeader.Position = UDim2.new(0.5, 0, 0, 10)
	heroHeader.Size = UDim2.fromOffset(520, 104)
	heroHeader.BackgroundTransparency = 1
	heroHeader.Parent = startView

	local brandTitle = Instance.new("TextLabel")
	brandTitle.Name = "BrandTitle"
	brandTitle.AnchorPoint = Vector2.new(0.5, 0)
	brandTitle.Position = UDim2.fromScale(0.5, 0)
	brandTitle.Size = UDim2.new(1, 0, 0, 66)
	brandTitle.BackgroundTransparency = 1
	brandTitle.FontFace = Fonts.Display
	brandTitle.Text = "KNG CHAK"
	brandTitle.TextSize = 60
	brandTitle.TextColor3 = GOLD
	border(brandTitle, 4.5, OUTLINE, Enum.ApplyStrokeMode.Contextual)
	brandTitle.Parent = heroHeader

	local brandTagline = Instance.new("TextLabel")
	brandTagline.Name = "Tagline"
	brandTagline.AnchorPoint = Vector2.new(0.5, 0)
	brandTagline.Position = UDim2.new(0.5, 0, 0, 68)
	brandTagline.Size = UDim2.new(1, 0, 0, 26)
	brandTagline.BackgroundTransparency = 1
	brandTagline.FontFace = Fonts.TextBold
	brandTagline.Text = "Defend Planet Ember · Push, Spear & Slingshot"
	brandTagline.TextSize = 18
	brandTagline.TextColor3 = SUBTEXT
	border(brandTagline, 2, OUTLINE, Enum.ApplyStrokeMode.Contextual)
	brandTagline.Parent = heroHeader

	local startDock = Instance.new("Frame")
	startDock.Name = "ActionDock"
	startDock.AnchorPoint = Vector2.new(0.5, 1)
	startDock.Position = UDim2.new(0.5, 0, 1, -28)
	startDock.Size = UDim2.fromOffset(440, 60)
	startDock.BackgroundTransparency = 1
	startDock.Parent = startView

	local dockLayout = Instance.new("UIListLayout")
	dockLayout.FillDirection = Enum.FillDirection.Horizontal
	dockLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dockLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	dockLayout.Padding = UDim.new(0, 14)
	dockLayout.SortOrder = Enum.SortOrder.LayoutOrder
	dockLayout.Parent = startDock

	makeToyButton(startDock, "StartCall", "START CALL", UDim2.fromOffset(240, 58), RED, 26, 1, function()
		fire("StartPrimary")
	end)
	makeToyButton(startDock, "Controls", "CONTROLS", UDim2.fromOffset(164, 52), INDIGO, 20, 2, function()
		fire("StartControls")
	end)

	-- =========================================================================
	-- 2. PAUSE CARD
	-- =========================================================================
	local pauseCard = Instance.new("Frame")
	pauseCard.Name = "PauseCard"
	pauseCard.AnchorPoint = Vector2.new(0.5, 0.5)
	pauseCard.Position = UDim2.fromScale(0.5, 0.5)
	pauseCard.Size = UDim2.fromOffset(500, 296)
	pauseCard.BackgroundColor3 = CARD
	pauseCard.Visible = false
	round(pauseCard, 16)
	border(pauseCard, 4, OUTLINE, Enum.ApplyStrokeMode.Border)
	pauseCard.Parent = root

	local pauseTitle = Instance.new("TextLabel")
	pauseTitle.Name = "Title"
	pauseTitle.AnchorPoint = Vector2.new(0.5, 0)
	pauseTitle.Position = UDim2.new(0.5, 0, 0, 16)
	pauseTitle.Size = UDim2.new(1, -32, 0, 46)
	pauseTitle.BackgroundTransparency = 1
	pauseTitle.FontFace = Fonts.Display
	pauseTitle.Text = "PAUSED"
	pauseTitle.TextSize = 40
	pauseTitle.TextColor3 = GOLD
	border(pauseTitle, 3.5, OUTLINE, Enum.ApplyStrokeMode.Contextual)
	pauseTitle.Parent = pauseCard

	local pauseStats = Instance.new("Frame")
	pauseStats.Name = "StatsRow"
	pauseStats.AnchorPoint = Vector2.new(0.5, 0)
	pauseStats.Position = UDim2.new(0.5, 0, 0, 72)
	pauseStats.Size = UDim2.new(1, -40, 0, 74)
	pauseStats.BackgroundTransparency = 1
	pauseStats.Parent = pauseCard

	local pauseStatsLayout = Instance.new("UIListLayout")
	pauseStatsLayout.FillDirection = Enum.FillDirection.Horizontal
	pauseStatsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pauseStatsLayout.Padding = UDim.new(0, 10)
	pauseStatsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pauseStatsLayout.Parent = pauseStats

	local pauseWaveValue = makeStatCell(pauseStats, "WaveCell", "CALL STAGE", GOLD, 1)
	local pauseHpValue = makeStatCell(pauseStats, "HpCell", "EMBER HP", GREEN, 2)
	local pauseScoreValue = makeStatCell(pauseStats, "ScoreCell", "SCORE", WHITE, 3)

	makeToyButton(pauseCard, "Resume", "RESUME CALL", UDim2.new(1, -40, 0, 54), GREEN, 24, 1, function()
		fire("PauseResume")
	end).Position =
		UDim2.new(0.5, 0, 0, 162)
	local resumeBtn = pauseCard:FindFirstChild("Resume") :: TextButton
	resumeBtn.AnchorPoint = Vector2.new(0.5, 0)

	local pauseRow = Instance.new("Frame")
	pauseRow.Name = "SecondaryRow"
	pauseRow.AnchorPoint = Vector2.new(0.5, 0)
	pauseRow.Position = UDim2.new(0.5, 0, 0, 228)
	pauseRow.Size = UDim2.new(1, -40, 0, 48)
	pauseRow.BackgroundTransparency = 1
	pauseRow.Parent = pauseCard

	local pauseRowLayout = Instance.new("UIListLayout")
	pauseRowLayout.FillDirection = Enum.FillDirection.Horizontal
	pauseRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pauseRowLayout.Padding = UDim.new(0, 10)
	pauseRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pauseRowLayout.Parent = pauseRow

	makeToyButton(pauseRow, "Controls", "CONTROLS", UDim2.fromOffset(146, 46), INDIGO, 18, 1, function()
		fire("PauseControls")
	end)
	makeToyButton(pauseRow, "Restart", "RESTART", UDim2.fromOffset(146, 46), RED, 18, 2, function()
		fire("PauseRestart")
	end)
	makeToyButton(pauseRow, "TitleBtn", "TITLE", UDim2.fromOffset(146, 46), SLATE_INDIGO, 18, 3, function()
		fire("PauseTitle")
	end)

	-- =========================================================================
	-- 3. RESULTS CARD
	-- =========================================================================
	local resultsCard = Instance.new("Frame")
	resultsCard.Name = "ResultsCard"
	resultsCard.AnchorPoint = Vector2.new(0.5, 0.5)
	resultsCard.Position = UDim2.fromScale(0.5, 0.5)
	resultsCard.Size = UDim2.fromOffset(536, 304)
	resultsCard.BackgroundColor3 = CARD
	resultsCard.Visible = false
	round(resultsCard, 16)
	border(resultsCard, 4, OUTLINE, Enum.ApplyStrokeMode.Border)
	resultsCard.Parent = root

	local resultsTitle = Instance.new("TextLabel")
	resultsTitle.Name = "Title"
	resultsTitle.AnchorPoint = Vector2.new(0.5, 0)
	resultsTitle.Position = UDim2.new(0.5, 0, 0, 14)
	resultsTitle.Size = UDim2.new(1, -32, 0, 48)
	resultsTitle.BackgroundTransparency = 1
	resultsTitle.FontFace = Fonts.Display
	resultsTitle.TextSize = 42
	resultsTitle.TextColor3 = GREEN
	border(resultsTitle, 3.5, OUTLINE, Enum.ApplyStrokeMode.Contextual)
	resultsTitle.Parent = resultsCard

	local resultsSub = Instance.new("TextLabel")
	resultsSub.Name = "Subtitle"
	resultsSub.AnchorPoint = Vector2.new(0.5, 0)
	resultsSub.Position = UDim2.new(0.5, 0, 0, 62)
	resultsSub.Size = UDim2.new(1, -32, 0, 24)
	resultsSub.BackgroundTransparency = 1
	resultsSub.FontFace = Fonts.TextBold
	resultsSub.TextSize = 17
	resultsSub.TextColor3 = SUBTEXT
	resultsSub.Parent = resultsCard

	local resultsStats = Instance.new("Frame")
	resultsStats.Name = "StatsRow"
	resultsStats.AnchorPoint = Vector2.new(0.5, 0)
	resultsStats.Position = UDim2.new(0.5, 0, 0, 96)
	resultsStats.Size = UDim2.new(1, -40, 0, 82)
	resultsStats.BackgroundTransparency = 1
	resultsStats.Parent = resultsCard

	local resultsStatsLayout = Instance.new("UIListLayout")
	resultsStatsLayout.FillDirection = Enum.FillDirection.Horizontal
	resultsStatsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	resultsStatsLayout.Padding = UDim.new(0, 10)
	resultsStatsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	resultsStatsLayout.Parent = resultsStats

	local resultsScoreValue = makeStatCell(resultsStats, "ScoreCell", "FINAL SCORE", GOLD, 1)
	local resultsComboValue = makeStatCell(resultsStats, "ComboCell", "BEST COMBO", CYAN, 2)
	local resultsPerfectValue = makeStatCell(resultsStats, "PerfectCell", "PERFECTS", PINK, 3)

	local resultsActionsRow = Instance.new("Frame")
	resultsActionsRow.Name = "ActionRow"
	resultsActionsRow.AnchorPoint = Vector2.new(0.5, 0)
	resultsActionsRow.Position = UDim2.new(0.5, 0, 0, 198)
	resultsActionsRow.Size = UDim2.new(1, -40, 0, 84)
	resultsActionsRow.BackgroundTransparency = 1
	resultsActionsRow.Parent = resultsCard

	local playAgainBtn = makeToyButton(
		resultsActionsRow,
		"PlayAgain",
		"PLAY AGAIN",
		UDim2.fromOffset(234, 56),
		RED,
		24,
		1,
		function()
			fire("ResultsPlayAgain")
		end
	)
	playAgainBtn.AnchorPoint = Vector2.new(0, 0.5)
	playAgainBtn.Position = UDim2.fromScale(0, 0.5)

	local resultsControlsBtn = makeToyButton(
		resultsActionsRow,
		"Controls",
		"CONTROLS",
		UDim2.fromOffset(126, 50),
		INDIGO,
		17,
		2,
		function()
			fire("ResultsControls")
		end
	)
	resultsControlsBtn.AnchorPoint = Vector2.new(1, 0.5)
	resultsControlsBtn.Position = UDim2.new(1, -126, 0.5, 0)

	local resultsTitleBtn = makeToyButton(
		resultsActionsRow,
		"TitleBtn",
		"TITLE",
		UDim2.fromOffset(116, 50),
		SLATE_INDIGO,
		17,
		3,
		function()
			fire("ResultsTitle")
		end
	)
	resultsTitleBtn.AnchorPoint = Vector2.new(1, 0.5)
	resultsTitleBtn.Position = UDim2.fromScale(1, 0.5)

	self._startView = startView
	self._pauseCard = pauseCard
	self._resultsCard = resultsCard
	self._pauseWaveValue = pauseWaveValue
	self._pauseHpValue = pauseHpValue
	self._pauseScoreValue = pauseScoreValue
	self._resultsTitle = resultsTitle
	self._resultsSub = resultsSub
	self._resultsScoreValue = resultsScoreValue
	self._resultsComboValue = resultsComboValue
	self._resultsPerfectValue = resultsPerfectValue

	scrimGui.Parent = parent
	safeGui.Parent = parent
	return self
end

local function refreshVisibility(self: Overlay)
	local visible = not self._suppressed and self._mode ~= "None"
	self._scrimGui.Enabled = visible
	self._safeGui.Enabled = visible
	self._startView.Visible = self._mode == "Start"
	self._pauseCard.Visible = self._mode == "Pause"
	self._resultsCard.Visible = self._mode == "Results"
end

function Overlay.ShowStart(self: Overlay, onStart: () -> (), onControls: () -> ())
	table.clear(self._actions)
	self._actions.StartPrimary = onStart
	self._actions.StartControls = onControls
	self._onScrimTap = onStart
	self._scrimButton.BackgroundTransparency = 0.72 -- light vignette so spinning Ember shines through
	self._mode = "Start"
	refreshVisibility(self)
end

function Overlay.ShowPause(self: Overlay, info: PauseInfo, actions: PauseActions)
	table.clear(self._actions)
	self._actions.PauseResume = actions.OnResume
	self._actions.PauseControls = actions.OnControls
	self._actions.PauseRestart = actions.OnRestart
	self._actions.PauseTitle = actions.OnTitle
	self._onScrimTap = actions.OnResume
	self._scrimButton.BackgroundTransparency = 0.36

	local waveText = if info.IsBoss then "INFERNO" else `{math.max(1, info.Wave)} / {info.LastWave}`
	self._pauseWaveValue.Text = waveText
	self._pauseWaveValue.TextColor3 = if info.IsBoss then CORAL else GOLD

	local hpPct = if info.PlanetMaxHp > 0
		then math.clamp(math.floor(info.PlanetHp / info.PlanetMaxHp * 100 + 0.5), 0, 100)
		else 0
	local shieldPct = math.floor(info.PlanetShield + 0.5)
	if shieldPct > 0 then
		self._pauseHpValue.Text = `{hpPct}% +{shieldPct}`
		self._pauseHpValue.TextColor3 = SHIELD_CYAN
	else
		self._pauseHpValue.Text = `{hpPct}%`
		self._pauseHpValue.TextColor3 = if hpPct > 60 then GREEN elseif hpPct > 30 then AMBER else CORAL
	end

	self._pauseScoreValue.Text = formatInt(info.Score)

	self._mode = "Pause"
	refreshVisibility(self)
end

function Overlay.ShowResults(self: Overlay, summary: ResultsSummary, lastWave: number, actions: ResultsActions)
	table.clear(self._actions)
	self._actions.ResultsPlayAgain = actions.OnPlayAgain
	self._actions.ResultsControls = actions.OnControls
	self._actions.ResultsTitle = actions.OnTitle
	self._onScrimTap = nil -- require explicit button tap on Results so thumbs mid-steering don't skip stats!
	self._scrimButton.BackgroundTransparency = 0.34

	self._resultsTitle.Text = if summary.Won then "CALL CLEARED!" else "PLANET LOST"
	self._resultsTitle.TextColor3 = if summary.Won then GREEN else CORAL

	local reached = if summary.Wave > lastWave then "The Inferno" else `Wave {math.max(1, summary.Wave)} of {lastWave}`
	self._resultsSub.Text = `Reached {reached}  ·  Call time {formatClock(summary.Time)}`

	self._resultsScoreValue.Text = formatInt(summary.Score)
	self._resultsComboValue.Text = `×{summary.BestCombo}`
	self._resultsPerfectValue.Text = tostring(summary.Perfects)

	self._mode = "Results"
	refreshVisibility(self)
end

function Overlay.Hide(self: Overlay)
	self._mode = "None"
	self._onScrimTap = nil
	table.clear(self._actions)
	refreshVisibility(self)
end

-- Keeps the screen out of sight (while the style tile or controls card shows) without forgetting it.
function Overlay.SetSuppressed(self: Overlay, suppressed: boolean)
	self._suppressed = suppressed
	refreshVisibility(self)
end

return Overlay
