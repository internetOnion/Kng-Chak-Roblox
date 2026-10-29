--!strict
--[[
	SoundPlayer: plays the game's sounds from its events.

	    local sounds = SoundPlayer.new()
	    sounds:Listen(GameEvents)                  -- once; GameEvents follows whichever Run is active
	    sounds:UpdateEngine(snapshot.Ship, playing) -- every frame: the engine hum

	One-shot sounds play only in answer to game events (a boost, a push, a break,
	a clang, a bump, a planet impact, a slingshot), never from inside the Run. The
	engine hum is a loop whose volume and pitch follow the throttle, and it's
	silent outside play. Sounds and their levels come from Audio/SoundBank.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local RunEvents = require(ReplicatedStorage.KngChak.Run.RunEvents)
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
	local voices = {}
	for name, entry in SoundBank :: { [string]: SoundBank.Sound } do
		if not entry.Looped then
			local sounds = {}
			for _ = 1, VOICES do
				table.insert(sounds, make(folder, name, entry))
			end
			voices[name] = { sounds = sounds, next = 1 }
		end
	end
	local hum = make(folder, "EngineHum", SoundBank.EngineHum)
	hum.Volume = 0
	return setmetatable({ _folder = folder, _voices = voices, _hum = hum, _humLevel = 0 }, SoundPlayer)
end

-- Plays the one-shot sound `name` from the SoundBank.
function SoundPlayer.Play(self: SoundPlayer, name: string)
	local voices = self._voices[name]
	if not voices then
		return
	end
	local sound = voices.sounds[voices.next]
	voices.next = voices.next % #voices.sounds + 1
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
	on(events.RockPrimed, "Push")
	on(events.RockBroken, "Break")
	on(events.RockClanged, "Clang")
	on(events.ShipBumped, "Bump")
	on(events.PlanetHit, "Impact")
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

return SoundPlayer
