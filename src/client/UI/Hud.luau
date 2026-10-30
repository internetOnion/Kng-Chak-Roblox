--!strict
--[[
	Hud: planet HP % (and shield), wave/boss status, score and combo, readable at phone size.
	Kept inside a compact 2-row top strip (<= 54 px) so wave/boss banners below never touch it.

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
		_shown: { [string]: any },
	},
	Hud
))

local function label(
	parent: Instance,
	name: string,
	anchor: Vector2,
	position: UDim2,
	size: UDim2,
	align: Enum.TextXAlignment
): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.AnchorPoint = anchor
	text.Position = position
	text.Size = size
	text.BackgroundTransparency = 1
	text.FontFace = Fonts.TextBold
	text.TextSize = 28
	text.TextColor3 = TEXT
	text.TextXAlignment = align
	text.TextStrokeTransparency = 0.35
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
		_hp = label(
			gui,
			"Hp",
			Vector2.new(0, 0),
			UDim2.fromScale(0, 0),
			UDim2.fromOffset(210, 34),
			Enum.TextXAlignment.Left
		),
		_wave = label(
			gui,
			"Wave",
			Vector2.new(0.5, 0),
			UDim2.fromScale(0.5, 0),
			UDim2.fromOffset(440, 28),
			Enum.TextXAlignment.Center
		),
		_score = label(
			gui,
			"Score",
			Vector2.new(1, 0),
			UDim2.fromScale(1, 0),
			UDim2.fromOffset(210, 34),
			Enum.TextXAlignment.Right
		),
		_combo = label(
			gui,
			"Combo",
			Vector2.new(0.5, 0),
			UDim2.new(0.5, 0, 0, 28),
			UDim2.fromOffset(280, 24),
			Enum.TextXAlignment.Center
		),
		_shown = {},
	}, Hud)
	self._wave.FontFace = Fonts.Display
	self._wave.TextSize = 22
	self._combo.FontFace = Fonts.Display
	self._combo.TextSize = 20
	self._combo.TextColor3 = COMBO
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
	local wave = ""
	local isBoss = boss ~= nil
	if boss then
		local seconds = math.ceil(boss.TimeToImpact)
		wave = if boss.Phase < 3
			then `INFERNO · PLATES {boss.PlatesLeft}/{boss.Plates} · {seconds}s`
			else `INFERNO · CORE {boss.CoreHits - boss.CoreHitsLeft}/{boss.CoreHits} · {seconds}s`
	elseif snapshot.Wave > 0 then
		wave = `WAVE {snapshot.Wave} / {snapshot.LastWave}`
	end
	if self._shown.wave ~= wave or self._shown.isBoss ~= isBoss then
		self._shown.wave = wave
		self._shown.isBoss = isBoss
		self._wave.Text = wave
		self._wave.TextColor3 = if isBoss then BOSS else TEXT
	end

	local mult = string.format("%.1f", snapshot.Multiplier)
	local comboKey = `{snapshot.Combo}:{mult}`
	if self._shown.combo ~= comboKey then
		self._shown.combo = comboKey
		self._combo.Text = if snapshot.Combo > 0 then `{snapshot.Combo} COMBO · ×{mult}` else ""
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
