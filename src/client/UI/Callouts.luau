--!strict
--[[
	Callouts: the big words for the best moments, mid-screen.

	    local callouts = Callouts.new(playerGui)
	    callouts:Listen(GameEvents) -- once; GameEvents follows whichever Run is active

	PERFECT pops up on every PERFECT, and COMBO ×n each time the combo reaches a
	multiple of MILESTONE. Each callout pops in, holds and fades, and a newer one
	replaces it. They glow (callouts are energy, see docs/art-guide.md) and only
	listen to game events, never the Run itself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Fonts = require(script.Parent.Fonts)
local RunEvents = require(ReplicatedStorage.KngChak.Run.RunEvents)

local MILESTONE = 5 -- a combo callout every this many
local PERFECT_COLOR = Color3.fromHex("#ffe066")
local COMBO_COLOR = Color3.fromHex("#ff9a1f")
local GLOW = Color3.fromHex("#ff4a1c")
local HOLD = 0.55 -- seconds a callout stays before fading
local FADE = 0.35

local Callouts = {}
Callouts.__index = Callouts

export type Callouts = typeof(setmetatable(
	{} :: {
		_gui: ScreenGui,
		_label: TextLabel,
		_stroke: UIStroke,
		_scale: UIScale,
		_shown: number, -- counts callouts, so an older one's fade doesn't hide a newer one
		_combo: number,
	},
	Callouts
))

function Callouts.new(parent: Instance): Callouts
	local gui = Instance.new("ScreenGui")
	gui.Name = "Callouts"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local label = Instance.new("TextLabel")
	label.Name = "Callout"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.3) -- above the planet, clear of the thumbs
	label.Size = UDim2.new(1, 0, 0, 80)
	label.BackgroundTransparency = 1
	label.FontFace = Fonts.Display
	label.TextSize = 64
	label.TextTransparency = 1
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = GLOW
	stroke.Thickness = 4
	stroke.Transparency = 1
	stroke.Parent = label

	local scale = Instance.new("UIScale")
	scale.Parent = label

	gui.Parent = parent
	return setmetatable(
		{ _gui = gui, _label = label, _stroke = stroke, _scale = scale, _shown = 0, _combo = 0 },
		Callouts
	)
end

-- Shows `text` in `color`, popping in and then fading out.
function Callouts.Show(self: Callouts, text: string, color: Color3)
	self._shown += 1
	local shown = self._shown
	local label = self._label
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	self._stroke.Transparency = 0.2
	self._scale.Scale = 1.6
	TweenService:Create(self._scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
	task.delay(HOLD, function()
		if self._shown ~= shown then
			return
		end
		local fade = TweenInfo.new(FADE)
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(self._stroke, fade, { Transparency = 1 }):Play()
	end)
end

-- Shows callouts for the events of whatever `events` forwards (GameEvents, or one Run's hub).
function Callouts.Listen(self: Callouts, events: RunEvents.RunEvents)
	events.Perfect:Connect(function()
		self:Show("PERFECT!", PERFECT_COLOR)
	end)
	events.ComboChanged:Connect(function(combo: number)
		local before = self._combo
		self._combo = combo
		if combo > before and math.floor(combo / MILESTONE) > math.floor(before / MILESTONE) then
			-- a PERFECT that also passes a milestone shows PERFECT, which fires first
			task.defer(function()
				if self._label.Text ~= "PERFECT!" or self._label.TextTransparency > 0 then
					self:Show(`COMBO ×{combo}`, COMBO_COLOR)
				end
			end)
		end
	end)
end

function Callouts.SetVisible(self: Callouts, visible: boolean)
	self._gui.Enabled = visible
end

return Callouts
