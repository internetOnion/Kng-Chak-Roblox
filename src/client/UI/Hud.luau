--!strict
--[[
	Hud: planet HP % (and shield), wave, score and combo, readable at phone size.
	During the Inferno the wave readout names it, with its plates or core left and
	the seconds until it reaches the planet.

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
local BOSS = Color3.fromHex("#ff9a1f")

local Hud = {}
Hud.__index = Hud

export type Hud = typeof(setmetatable(
	{} :: {
		_gui: ScreenGui,
		_hp: TextLabel,
		_wave: TextLabel,
		_score: TextLabel,
		_combo: TextLabel,
		_boss: TextLabel,
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
		_boss = label(gui, "Boss", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 64), Enum.TextXAlignment.Center),
		_shown = {},
	}, Hud)
	self._boss.TextSize = 22
	self._boss.Size = UDim2.fromOffset(420, 32)
	self._boss.TextColor3 = BOSS
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
	local shield = math.ceil(snapshot.PlanetShield)
	if self._shown.hp ~= hp or self._shown.shield ~= shield then
		self._shown.hp = hp
		self._shown.shield = shield
		self._hp.Text = if shield > 0 then `HP {hp}% +{shield}` else `HP {hp}%`
		self._hp.TextColor3 = if hp < LOW_HP_AT then LOW_HP else TEXT
	end
	local boss = snapshot.Boss
	local wave = if boss
		then "INFERNO"
		elseif snapshot.Wave > 0 then `WAVE {snapshot.Wave} / {snapshot.LastWave}`
		else ""
	if self._shown.wave ~= wave then
		self._shown.wave = wave
		self._wave.Text = wave
	end
	local bossText = ""
	if boss then
		local seconds = math.ceil(boss.TimeToImpact)
		bossText = if boss.Phase < 3
			then `PLATES {boss.PlatesLeft}/{boss.Plates} · {seconds} s`
			else `CORE {boss.CoreHits - boss.CoreHitsLeft}/{boss.CoreHits} PERFECTS · {seconds} s`
	end
	if self._shown.boss ~= bossText then
		self._shown.boss = bossText
		self._boss.Text = bossText
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
