--!strict
--[[
	Banner: the wave and boss phase pill below the HUD.

	    local banner = Banner.new(playerGui)
	    banner:Listen(GameEvents) -- once; GameEvents follows whichever Run is active

	Anchored at a fixed safe-area offset below the 2-row HUD so it never overlaps
	the Wave/Combo readouts on short phone screens. Cancels prior tweens cleanly on
	replacement, skips redundant WAVE CLEAR / SURGE SURVIVED banners when the
	UpgradeCards screen already celebrates the clear, and paces back-to-back banners
	when upgrades are maxed out.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local KngChak = ReplicatedStorage.KngChak
local InfernoConfig = require(KngChak.Data.InfernoConfig)
local RunEvents = require(KngChak.Run.RunEvents)
local WaveConfig = require(KngChak.Data.WaveConfig)
local WaveModifiers = require(KngChak.Data.WaveModifiers)

local Fonts = require(script.Parent.Fonts)

local HOLD = 2.4 -- seconds a banner stays before fading
local CLEAR_MIN_HOLD = 1.0 -- minimum readable beat for a clear banner before the next wave replaces it
local FADE = 0.35
local PILL_BG = Color3.fromHex("#14133d")
local PILL_ALPHA = 0.28
local OUTLINE = Color3.fromHex("#000000")
local TITLE = Color3.fromHex("#ffe066")
local TIP_TEXT = Color3.fromHex("#d8d6ff")
local SURGE = Color3.fromHex("#ff9a1f")
local BOSS = Color3.fromHex("#ff4a1c")

local Banner = {}
Banner.__index = Banner

export type Banner = typeof(setmetatable(
	{} :: {
		_gui: ScreenGui,
		_frame: Frame,
		_border: UIStroke,
		_title: TextLabel,
		_titleStroke: UIStroke,
		_tip: TextLabel,
		_tweens: { Tween },
		_shown: number, -- increments on each Show/Clear to invalidate older timers
		_clearShownAt: number, -- os.clock() when a clear/surge banner appeared without an upgrade screen
	},
	Banner
))

local function cancelTweens(self: Banner)
	for _, tween in self._tweens do
		tween:Cancel()
	end
	table.clear(self._tweens)
end

function Banner.new(parent: Instance): Banner
	local gui = Instance.new("ScreenGui")
	gui.Name = "Banner"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local frame = Instance.new("Frame")
	frame.Name = "Banner"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 66) -- strictly below the 54 px HUD strip
	frame.Size = UDim2.fromOffset(0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.BackgroundColor3 = PILL_BG
	frame.BackgroundTransparency = PILL_ALPHA
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame

	local border = Instance.new("UIStroke")
	border.Color = OUTLINE
	border.Thickness = 2.5
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Parent = frame

	local sizeCap = Instance.new("UISizeConstraint")
	sizeCap.MinSize = Vector2.new(180, 0)
	sizeCap.MaxSize = Vector2.new(480, 130)
	sizeCap.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 20)
	pad.PaddingRight = UDim.new(0, 20)
	pad.Parent = frame

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 3)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.LayoutOrder = 1
	title.Size = UDim2.fromOffset(0, 0)
	title.AutomaticSize = Enum.AutomaticSize.XY
	title.BackgroundTransparency = 1
	title.FontFace = Fonts.Display
	title.TextSize = 30
	title.TextColor3 = TITLE
	title.Parent = frame

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = OUTLINE
	titleStroke.Thickness = 2.5
	titleStroke.Transparency = 0.15
	titleStroke.Parent = title

	local tip = Instance.new("TextLabel")
	tip.Name = "Tip"
	tip.LayoutOrder = 2
	tip.Size = UDim2.fromOffset(0, 0)
	tip.AutomaticSize = Enum.AutomaticSize.XY
	tip.BackgroundTransparency = 1
	tip.FontFace = Fonts.TextBold
	tip.TextSize = 16
	tip.TextColor3 = TIP_TEXT
	tip.TextWrapped = true
	tip.Parent = frame

	local tipCap = Instance.new("UISizeConstraint")
	tipCap.MaxSize = Vector2.new(440, 64)
	tipCap.Parent = tip

	gui.Parent = parent
	return setmetatable({
		_gui = gui,
		_frame = frame,
		_border = border,
		_title = title,
		_titleStroke = titleStroke,
		_tip = tip,
		_tweens = {},
		_shown = 0,
		_clearShownAt = 0,
	}, Banner)
end

local function showNow(self: Banner, title: string, tip: string, color: Color3?, isClear: boolean)
	cancelTweens(self)
	self._shown += 1
	local shown = self._shown
	self._clearShownAt = if isClear then os.clock() else 0

	self._title.Text = title
	self._title.TextColor3 = color or TITLE
	self._title.TextTransparency = 0
	self._titleStroke.Transparency = 0.15

	self._tip.Text = tip
	self._tip.TextTransparency = 0
	self._tip.Visible = tip ~= ""

	self._frame.BackgroundTransparency = PILL_ALPHA
	self._border.Transparency = 0
	self._frame.Visible = true

	task.delay(HOLD, function()
		if self._shown ~= shown then
			return
		end
		local info = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tweens = {
			TweenService:Create(self._frame, info, { BackgroundTransparency = 1 }),
			TweenService:Create(self._border, info, { Transparency = 1 }),
			TweenService:Create(self._title, info, { TextTransparency = 1 }),
			TweenService:Create(self._titleStroke, info, { Transparency = 1 }),
			TweenService:Create(self._tip, info, { TextTransparency = 1 }),
		}
		for _, tween in tweens do
			table.insert(self._tweens, tween)
			tween:Play()
		end
		task.delay(FADE, function()
			if self._shown == shown then
				self._frame.Visible = false
			end
		end)
	end)
end

-- Shows `title` over `tip` in `color`, waiting briefly if a wave-clear banner just went up.
function Banner.Show(self: Banner, title: string, tip: string, color: Color3?)
	local sinceClear = os.clock() - self._clearShownAt
	if self._clearShownAt > 0 and sinceClear < CLEAR_MIN_HOLD then
		local token = self._shown
		task.delay(CLEAR_MIN_HOLD - sinceClear, function()
			if self._shown == token then
				showNow(self, title, tip, color, false)
			end
		end)
		return
	end
	showNow(self, title, tip, color, false)
end

-- Hides the banner straight away and drops any pending fade or queued announcement.
function Banner.Clear(self: Banner)
	cancelTweens(self)
	self._shown += 1
	self._clearShownAt = 0
	self._frame.Visible = false
end

local function modifierNames(modifiers: { string }): { string }
	local names = {}
	for _, id in modifiers do
		table.insert(names, WaveModifiers.ById[id].Name)
	end
	return names
end

-- Shows banners for the events of whatever `events` forwards (GameEvents, or one Run's hub).
function Banner.Listen(self: Banner, events: RunEvents.RunEvents)
	local surgeHeal: number? = nil
	local offerOpened = false

	events.UpgradeOffered:Connect(function()
		offerOpened = true
	end)

	events.Healed:Connect(function(amount: number, cause: string)
		if cause == "Surge" then
			surgeHeal = amount
		end
	end)

	events.WaveCleared:Connect(function(wave: number)
		local token = self._shown
		-- UpgradeOffered and Surge Healed fire right after WaveCleared in the same sub-step.
		task.defer(function()
			local heal = surgeHeal
			local hadOffer = offerOpened
			surgeHeal = nil
			offerOpened = false
			if self._shown ~= token or hadOffer then
				-- UpgradeCards takes the screen and shows the wave/surge header itself.
				return
			end
			if heal then
				showNow(self, "SURGE SURVIVED", `Planet +{heal}%`, SURGE, true)
			else
				showNow(self, `WAVE {wave} CLEAR`, "", nil, true)
			end
		end)
	end)

	events.WaveAnnounced:Connect(function(wave: number, intro: string?, modifiers: { string })
		local names = modifierNames(modifiers)
		if #modifiers >= 2 then
			self:Show(
				`WAVE {wave} · SURGE`,
				`{table.concat(names, " + ")} · survive for +{WaveConfig.SurgeHeal}%`,
				SURGE
			)
		elseif #modifiers == 1 then
			self:Show(`WAVE {wave} · {string.upper(names[1])}`, WaveModifiers.ById[modifiers[1]].Tip)
		elseif intro then
			self:Show(`WAVE {wave}`, WaveModifiers.Intros[intro] or "")
		elseif wave == WaveConfig.LastWave then
			self:Show(`WAVE {wave}`, "Final wave. Something huge is coming.")
		else
			self:Show(`WAVE {wave}`, "")
		end
	end)

	events.BossPhaseChanged:Connect(function(phase: number)
		if phase == 1 then
			self:Show("THE INFERNO", "Push its burning plates pink, then spear them.", BOSS)
		elseif phase == 2 then
			self:Show("BURN-OFF", "Shedding rocks! Finish the remaining plates.", BOSS)
		elseif phase == 3 then
			self:Show("CORE EXPOSED", `Crack it with {InfernoConfig.CoreHits} PERFECT dives from orbit.`, BOSS)
		end
	end)
end

function Banner.SetVisible(self: Banner, visible: boolean)
	self._gui.Enabled = visible
end

return Banner
