--!strict
--[[
	Haptics: tactile phone & controller feedback for breaks, PERFECTs, clangs and impacts (#47).

	    local haptics = Haptics.new(playerGui)
	    haptics:Listen(GameEvents)

	Uses Roblox's HapticEffect instance parented under PlayerGui (non-spatial, so
	camera height never attenuates touch haptics on iOS CoreHaptics / Android),
	plus HapticService motor pulses when a gamepad is connected. Every engine call
	is guarded with pcall so unsupported phones, desktop clients and headless
	environments run with zero errors or warnings.
]]

local HapticService = game:GetService("HapticService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local RunEvents = require(KngChak.Run.RunEvents)
local Signal = require(KngChak.Util.Signal)

export type Kind = "Break" | "Clang" | "Perfect" | "Impact"

type Spec = {
	priority: number,
	fallbackType: Enum.HapticEffectType,
	keys: { { t: number, v: number } },
	gamepadMotor: Enum.VibrationMotor,
	gamepadStrength: number,
	gamepadDuration: number,
}

local MIN_GAP = 0.045 -- seconds between equal-or-lower priority pulses

local SPECS: { [Kind]: Spec } = {
	Break = {
		priority = 1,
		fallbackType = Enum.HapticEffectType.GameplayCollision,
		keys = {
			{ t = 0.00, v = 0.68 },
			{ t = 0.055, v = 0.00 },
		},
		gamepadMotor = Enum.VibrationMotor.Small,
		gamepadStrength = 0.45,
		gamepadDuration = 0.06,
	},
	Clang = {
		priority = 2,
		fallbackType = Enum.HapticEffectType.GameplayCollision,
		keys = {
			{ t = 0.00, v = 0.82 },
			{ t = 0.03, v = 0.15 },
			{ t = 0.055, v = 0.72 },
			{ t = 0.095, v = 0.00 },
		},
		gamepadMotor = Enum.VibrationMotor.Small,
		gamepadStrength = 0.65,
		gamepadDuration = 0.09,
	},
	Perfect = {
		priority = 3,
		fallbackType = Enum.HapticEffectType.GameplayExplosion,
		keys = {
			{ t = 0.00, v = 0.65 },
			{ t = 0.045, v = 0.12 },
			{ t = 0.075, v = 1.00 },
			{ t = 0.155, v = 0.00 },
		},
		gamepadMotor = Enum.VibrationMotor.Large,
		gamepadStrength = 0.85,
		gamepadDuration = 0.15,
	},
	Impact = {
		priority = 4,
		fallbackType = Enum.HapticEffectType.GameplayExplosion,
		keys = {
			{ t = 0.00, v = 1.00 },
			{ t = 0.11, v = 0.85 },
			{ t = 0.24, v = 0.00 },
		},
		gamepadMotor = Enum.VibrationMotor.Large,
		gamepadStrength = 1.00,
		gamepadDuration = 0.24,
	},
}

local Haptics = {}
Haptics.__index = Haptics

export type Haptics = typeof(setmetatable(
	{} :: {
		_folder: Folder,
		_effects: { [string]: HapticEffect? },
		_lastAt: number,
		_lastPriority: number,
		_pulseToken: number,
		_connections: { Signal.Connection },
	},
	Haptics
))

local function buildEffect(parent: Instance, name: Kind, spec: Spec): HapticEffect?
	local ok, created = pcall(function(): HapticEffect
		local effect = Instance.new("HapticEffect")
		effect.Name = name
		effect.Looped = false
		local curveOk = pcall(function()
			effect.Type = Enum.HapticEffectType.Custom
			local curve: { FloatCurveKey } = {}
			for _, pt in spec.keys do
				table.insert(curve, FloatCurveKey.new(pt.t, pt.v, Enum.KeyInterpolationMode.Linear))
			end
			effect:SetWaveformKeys(curve)
		end)
		if not curveOk then
			effect.Type = spec.fallbackType
		end
		effect.Parent = parent
		return effect
	end)
	if ok then
		return created
	end
	return nil
end

function Haptics.new(parent: Instance): Haptics
	local folder = Instance.new("Folder")
	folder.Name = "KngChakHaptics"
	folder.Parent = parent

	local effects: { [string]: HapticEffect? } = {}
	for kind, spec in SPECS do
		effects[kind] = buildEffect(folder, kind :: Kind, spec)
	end

	return setmetatable({
		_folder = folder,
		_effects = effects,
		_lastAt = 0,
		_lastPriority = 0,
		_pulseToken = 0,
		_connections = {} :: { Signal.Connection },
	}, Haptics)
end

local function pulseGamepad(self: Haptics, spec: Spec)
	local okSupported, supported = pcall(function()
		return HapticService:IsVibrationSupported(Enum.UserInputType.Gamepad1)
			and HapticService:IsMotorSupported(Enum.UserInputType.Gamepad1, spec.gamepadMotor)
	end)
	if not okSupported or not supported then
		return
	end
	self._pulseToken += 1
	local token = self._pulseToken
	pcall(function()
		HapticService:SetMotor(Enum.UserInputType.Gamepad1, spec.gamepadMotor, spec.gamepadStrength)
	end)
	task.delay(spec.gamepadDuration, function()
		if self._pulseToken == token then
			pcall(function()
				HapticService:SetMotor(Enum.UserInputType.Gamepad1, spec.gamepadMotor, 0)
			end)
		end
	end)
end

function Haptics.Pulse(self: Haptics, kind: Kind)
	local spec = SPECS[kind]
	if not spec then
		return
	end
	local now = os.clock()
	if now - self._lastAt < MIN_GAP and spec.priority <= self._lastPriority then
		return
	end
	self._lastAt = now
	self._lastPriority = spec.priority

	local effect = self._effects[kind]
	if effect then
		pcall(function()
			effect:Stop()
			effect:Play()
		end)
	end
	pulseGamepad(self, spec)
end

function Haptics.Listen(self: Haptics, events: RunEvents.RunEvents)
	local function connect(sig: Signal.Signal, fn: (...any) -> ())
		table.insert(self._connections, sig:Connect(fn))
	end

	connect(events.RockBroken, function(_rock: any, cause: string)
		-- Perfect fires right after RockBroken with cause == "Perfect"; let Perfect own that pulse.
		if cause ~= "Perfect" then
			self:Pulse("Break")
		end
	end)
	connect(events.Perfect, function()
		self:Pulse("Perfect")
	end)
	connect(events.CoreCracked, function()
		self:Pulse("Perfect")
	end)
	connect(events.RockClanged, function()
		self:Pulse("Clang")
	end)
	connect(events.ShipBumped, function()
		self:Pulse("Clang")
	end)
	connect(events.PlanetHit, function()
		self:Pulse("Impact")
	end)
	connect(events.BossHit, function()
		self:Pulse("Impact")
	end)
end

function Haptics.Destroy(self: Haptics)
	for _, conn in self._connections do
		conn:Disconnect()
	end
	table.clear(self._connections)
	self._folder:Destroy()
end

return Haptics
