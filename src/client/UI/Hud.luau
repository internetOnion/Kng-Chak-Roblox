--!strict
--[[
	Hud: planet HP %, wave, score and combo, readable at phone size.

	    local hud = Hud.new(playerGui)
	    hud:Update(run:Snapshot()) -- every frame

	It only reads the Run's snapshot. The ScreenGui keeps to Roblox's safe area
	(ScreenInsets CoreUISafeInsets), so notches and the top bar never cover it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fonts = require(script.Parent.Fonts)
local Run = require(ReplicatedStorage.KngChak.Run.Run)

local TEXT = Color3.fromHex("#ffffff")
local LOW_HP = Color3.fromHex("#ff4d5e")
local LOW_HP_AT = 30 -- HP % below which the HP readout turns red
local COMBO = Color3.fromHex("#ffe066")

local Hud = {}
Hud.__index = Hud

export type Hud = typeof(setmetatable(
	{} :: {
		_gui: ScreenGui,
		_hp: TextLabel,
		_wave: TextLabel,
		_score: TextLabel,
		_combo: TextLabel,
		_shown: { [string]: any },
	},
	Hud
))

local function label(
	parent: Instance,
	name: string,
	anchor: Vector2,
	position: UDim2,
	align: Enum.TextXAlignment
): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.AnchorPoint = anchor
	text.Position = position
	text.Size = UDim2.fromOffset(220, 44)
	text.BackgroundTransparency = 1
	text.FontFace = Fonts.TextBold
	text.TextSize = 30
	text.TextColor3 = TEXT
	text.TextXAlignment = align
	text.TextStrokeTransparency = 0.4
	text.Parent = parent
	return text
end

function Hud.new(parent: Instance): Hud
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.IgnoreGuiInset = false

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.PaddingTop = UDim.new(0, 8)
	pad.Parent = gui

	local self = setmetatable({
		_gui = gui,
		_hp = label(gui, "Hp", Vector2.new(0, 0), UDim2.fromScale(0, 0), Enum.TextXAlignment.Left),
		_wave = label(gui, "Wave", Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), Enum.TextXAlignment.Center),
		_score = label(gui, "Score", Vector2.new(1, 0), UDim2.fromScale(1, 0), Enum.TextXAlignment.Right),
		_combo = label(gui, "Combo", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 34), Enum.TextXAlignment.Center),
		_shown = {},
	}, Hud)
	self._combo.FontFace = Fonts.Display
	self._combo.TextSize = 26
	self._combo.TextColor3 = COMBO
	self._wave.FontFace = Fonts.Display
	self._wave.TextSize = 24
	gui.Parent = parent
	return self
end

function Hud.Update(self: Hud, snapshot: Run.Snapshot)
	local hp = math.ceil(snapshot.PlanetHp)
	if self._shown.hp ~= hp then
		self._shown.hp = hp
		self._hp.Text = `HP {hp}%`
		self._hp.TextColor3 = if hp < LOW_HP_AT then LOW_HP else TEXT
	end
	if self._shown.wave ~= snapshot.Wave then
		self._shown.wave = snapshot.Wave
		self._wave.Text = if snapshot.Wave > 0 then `WAVE {snapshot.Wave}` else ""
	end
	if self._shown.combo ~= snapshot.Combo then
		self._shown.combo = snapshot.Combo
		self._combo.Text = if snapshot.Combo > 0
			then `{snapshot.Combo} COMBO  ×{string.format("%.1f", snapshot.Multiplier)}`
			else ""
	end
	local score = math.floor(snapshot.Score)
	if self._shown.score ~= score then
		self._shown.score = score
		self._score.Text = tostring(score)
	end
end

function Hud.SetVisible(self: Hud, visible: boolean)
	self._gui.Enabled = visible
end

return Hud
