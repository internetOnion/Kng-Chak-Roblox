--!strict
--[[
	SoundPlayer: plays the game's sound effects from its events and threat state (#46).

	    local sounds = SoundPlayer.new()
	    sounds:Listen(GameEvents)                              -- once; GameEvents follows whichever Run is active
	    sounds:UpdateEngine(snapshot.Ship, playing, dt)        -- every frame: the engine hum
	    sounds:UpdateThreat(snapshot, planetRadius, playing)   -- every frame: urgent impact warning pip

	One-shot sounds play in answer to game events and UI taps, never from inside
	the Run. The engine hum is a loop whose volume and pitch follow the throttle,
	and the urgent impact alarm pips at a rising tempo when a rock or the Inferno
	is under Threat.UrgentEta seconds from hitting Ember. Sounds and their levels
	come from Audio/SoundBank (documented in docs/audio-licences.md).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local KngChak = ReplicatedStorage.KngChak
local Rock = require(KngChak.Rocks.Rock)
local Run = require(KngChak.Run.Run)
local RunEvents = require(KngChak.Run.RunEvents)
local Threat = require(KngChak.Rocks.Threat)

local SoundBank = require(script.Parent.SoundBank)

local VOICES = 3 -- copies of each one-shot, so quick repeats overlap instead of cutting off
local HUM_EASE = 8 -- how fast the hum follows the throttle

local SoundPlayer = {}
SoundPlayer.__index = SoundPlayer

type Voices = { sounds: { Sound }, next: number }

export type SoundPlayer = typeof(setmetatable(
	{} :: {
		_folder: Folder,
		_voices: { [string]: Voices },
		_hum: Sound,
		_humLevel: number,
		_nextAlarmAt: number,
	},
	SoundPlayer
))

local function make(folder: Instance, name: string, entry: SoundBank.Sound): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = `rbxassetid://{entry.Id}`
	sound.Volume = entry.Volume
	sound.PlaybackSpeed = entry.Pitch
	sound.Looped = entry.Looped == true
	sound.Parent = folder
	return sound
end

function SoundPlayer.new(): SoundPlayer
	local folder = Instance.new("Folder")
	folder.Name = "KngChakSounds"
	folder.Parent = SoundService
	local voices: { [string]: Voices } = {}
	for name, entry in SoundBank :: { [string]: SoundBank.Sound } do
		if not entry.Looped and not entry.IsMusic then
			local sounds: { Sound } = {}
			for _ = 1, VOICES do
				table.insert(sounds, make(folder, name, entry))
			end
			voices[name] = { sounds = sounds, next = 1 }
		end
	end
	local hum = make(folder, "EngineHum", SoundBank.EngineHum)
	hum.Volume = 0
	return setmetatable({
		_folder = folder,
		_voices = voices,
		_hum = hum,
		_humLevel = 0,
		_nextAlarmAt = 0,
	}, SoundPlayer)
end

-- Plays the one-shot sound `name` from the SoundBank (optionally nudging pitch).
function SoundPlayer.Play(self: SoundPlayer, name: string, pitchScale: number?)
	local voices = self._voices[name]
	if not voices then
		return
	end
	local entry = (SoundBank :: any)[name] :: SoundBank.Sound?
	local sound = voices.sounds[voices.next]
	voices.next = voices.next % #voices.sounds + 1
	if entry then
		sound.PlaybackSpeed = entry.Pitch * (pitchScale or 1)
	end
	sound.TimePosition = 0
	sound:Play()
end

-- Plays sounds for the events of whatever `events` forwards (GameEvents, or one Run's hub).
function SoundPlayer.Listen(self: SoundPlayer, events: RunEvents.RunEvents)
	local function on(signal: any, name: string)
		signal:Connect(function()
			self:Play(name)
		end)
	end
	on(events.Boosted, "Boost")
	on(events.Slingshot, "Slingshot")
	on(events.OrbitLocked, "OrbitLock")
	on(events.RockPrimed, "Push")
	on(events.RockFlared, "Flare")
	on(events.RockBroken, "Break")
	on(events.Perfect, "Perfect")
	on(events.RockClanged, "Clang")
	on(events.ShipBumped, "Bump")
	on(events.PlanetHit, "Impact")
	on(events.BossHit, "Impact")
	on(events.WaveStarted, "WaveStart")
	on(events.WaveCleared, "WaveClear")
	on(events.UpgradePicked, "UpgradePick")

	events.CoreCracked:Connect(function()
		self:Play("CoreCrack")
		self:Play("Clang")
	end)
	events.ShieldChanged:Connect(function(_shield: number, delta: number)
		if delta < 0 then
			self:Play("ShieldHit")
		end
	end)
	events.Healed:Connect(function()
		self:Play("Heal")
	end)
	events.RunFinished:Connect(function(summary: Run.Summary)
		self:Play(if summary.Won then "Victory" else "Defeat")
	end)
end

-- The fields the hum reads. A Run snapshot's Ship has them all.
export type Engine = {
	Throttle: number,
	IsBoosting: boolean,
	IsSlingshotting: boolean,
	IsStunned: boolean,
}

-- Keeps the engine hum in step with the ship. `playing` is false outside a run (silence).
function SoundPlayer.UpdateEngine(self: SoundPlayer, ship: Engine, playing: boolean, dt: number)
	local target = 0
	if playing and not ship.IsStunned then
		target = if ship.IsBoosting or ship.IsSlingshotting then 1 else 0.35 + 0.65 * ship.Throttle
	end
	self._humLevel += (target - self._humLevel) * math.min(1, HUM_EASE * dt)
	local entry = SoundBank.EngineHum
	self._hum.Volume = entry.Volume * self._humLevel
	self._hum.PlaybackSpeed = entry.Pitch * (0.85 + 0.3 * self._humLevel)
	if playing and not self._hum.IsPlaying then
		self._hum:Play()
	elseif not playing and self._hum.IsPlaying and self._humLevel < 0.01 then
		self._hum:Stop()
	end
end

-- Pulses the urgent impact warning pip while the nearest rock or boss is about to hit Ember.
function SoundPlayer.UpdateThreat(
	self: SoundPlayer,
	snapshot: Run.Snapshot,
	planetRadius: number,
	playing: boolean,
	now: number
)
	if not playing then
		return
	end

	local minEta: number? = nil
	if snapshot.ThreatId then
		for _, rock: Rock.Rock in snapshot.Rocks do
			if rock.Id == snapshot.ThreatId then
				minEta = Threat.Eta(rock, planetRadius)
				break
			end
		end
	end
	local boss = snapshot.Boss
	if boss and not boss.IsHolding then
		if not minEta or boss.TimeToImpact < minEta then
			minEta = boss.TimeToImpact
		end
	end

	if not minEta or minEta >= Threat.UrgentEta then
		return
	end
	if now < self._nextAlarmAt then
		return
	end

	local urgency = 1 - math.clamp(minEta / Threat.UrgentEta, 0, 1)
	local interval = 0.68 - 0.36 * urgency -- 0.68s at 2.0s out -> 0.32s right before impact
	self._nextAlarmAt = now + interval
	self:Play("ImpactAlarm", 0.94 + 0.18 * urgency)
end

return SoundPlayer
