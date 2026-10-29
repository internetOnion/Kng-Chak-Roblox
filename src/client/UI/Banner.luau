--!strict
--[[
	Banner: the big wave banner between waves, and the Inferno's phases.

	    local banner = Banner.new(playerGui)
	    banner:Listen(GameEvents) -- once; GameEvents follows whichever Run is active

	It shows, each for a few seconds, with a title and a line of tip:
	- WAVE n, with the tip of the threat it introduces or its modifiers (two on a surge)
	- WAVE n CLEAR, or SURGE SURVIVED with its heal
	- THE INFERNO and each of its phases
	The words come from the data (Data/WaveModifiers); the banner only listens to
	game events, never the Run itself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local KngChak = ReplicatedStorage.KngChak
local InfernoConfig = require(KngChak.Data.InfernoConfig)
local RunEvents = require(KngChak.Run.RunEvents)
local WaveConfig = require(KngChak.Data.WaveConfig)
local WaveModifiers = require(KngChak.Data.WaveModifiers)

local Fonts = require(script.Parent.Fonts)

local HOLD = 2.6 -- seconds a banner stays before fading
local FADE = 0.4
local TITLE = Color3.fromHex("#ffe066")
local SURGE = Color3.fromHex("#ff9a1f")
local BOSS = Color3.fromHex("#ff4a1c")
local GLOW = Color3.fromHex("#ff4a1c")

local Banner = {}
Banner.__index = Banner

export type Banner = typeof(setmetatable(
	{} :: {
		_gui: ScreenGui,
		_frame: Frame,
		_title: TextLabel,
		_tip: TextLabel,
		_shown: number, -- counts banners, so an older one's fade doesn't hide a newer one
	},
	Banner
))

local function text(parent: Instance, name: string, font: Font, size: number, y: number, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, y)
	label.Size = UDim2.new(1, 0, 0, height)
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = Color3.fromHex("#ffffff")
	label.TextStrokeTransparency = 0.35
	label.TextWrapped = true
	label.Parent = parent
	return label
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
	frame.Position = UDim2.fromScale(0.5, 0.14) -- under the HUD, above the planet
	frame.Size = UDim2.new(0.7, 0, 0, 110)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = gui

	local title = text(frame, "Title", Fonts.Display, 46, 0, 54)
	local stroke = Instance.new("UIStroke")
	stroke.Color = GLOW
	stroke.Thickness = 3
	stroke.Transparency = 0.3
	stroke.Parent = title
	local tip = text(frame, "Tip", Fonts.TextBold, 22, 56, 54)

	gui.Parent = parent
	return setmetatable({ _gui = gui, _frame = frame, _title = title, _tip = tip, _shown = 0 }, Banner)
end

-- Shows `title` over `tip` in `color`, then fades it out.
function Banner.Show(self: Banner, title: string, tip: string, color: Color3?)
	self._shown += 1
	local shown = self._shown
	self._title.Text = title
	self._title.TextColor3 = color or TITLE
	self._tip.Text = tip
	self._title.TextTransparency = 0
	self._tip.TextTransparency = 0
	self._frame.Visible = true
	task.delay(HOLD, function()
		if self._shown ~= shown then
			return
		end
		local fade = TweenInfo.new(FADE)
		TweenService:Create(self._title, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(self._tip, fade, { TextTransparency = 1 }):Play()
		task.delay(FADE, function()
			if self._shown == shown then
				self._frame.Visible = false
			end
		end)
	end)
end

-- Hides the banner straight away (a new run).
function Banner.Clear(self: Banner)
	self._shown += 1
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
	local surgeHealed = false
	events.WaveAnnounced:Connect(function(wave: number, intro: string?, modifiers: { string })
		local names = modifierNames(modifiers)
		if #modifiers >= 2 then
			self:Show(
				`WAVE {wave} · SURGE`,
				`{table.concat(names, " + ")} · survive it for +{WaveConfig.SurgeHeal}%`,
				SURGE
			)
		elseif #modifiers == 1 then
			self:Show(`WAVE {wave} · {string.upper(names[1])}`, WaveModifiers.ById[modifiers[1]].Tip)
		elseif intro then
			self:Show(`WAVE {wave}`, WaveModifiers.Intros[intro] or "")
		elseif wave == WaveConfig.LastWave then
			self:Show(`WAVE {wave}`, "The last wave. Something big is coming.")
		else
			self:Show(`WAVE {wave}`, "")
		end
	end)
	events.Healed:Connect(function(amount: number, cause: string)
		if cause == "Surge" then
			surgeHealed = true
			self:Show("SURGE SURVIVED", `Planet +{amount}%`, SURGE)
		end
	end)
	events.WaveCleared:Connect(function(wave: number)
		-- the surge heal fires right after this, in the same step
		task.defer(function()
			if not surgeHealed then
				self:Show(`WAVE {wave} CLEAR`, "")
			end
			surgeHealed = false
		end)
	end)
	events.BossPhaseChanged:Connect(function(phase: number)
		if phase == 1 then
			self:Show("THE INFERNO", "Push its burning plates, then break them.", BOSS)
		elseif phase == 2 then
			self:Show("BURN-OFF", "It's shedding rocks at the planet. Finish the plates!", BOSS)
		elseif phase == 3 then
			self:Show("CORE EXPOSED", `Crack it with {InfernoConfig.CoreHits} PERFECTs. Flare it from orbit.`, BOSS)
		end
	end)
end

function Banner.SetVisible(self: Banner, visible: boolean)
	self._gui.Enabled = visible
end

return Banner
