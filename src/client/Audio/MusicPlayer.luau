--!strict
--[[
	MusicPlayer: wave-escalating soundtrack and Inferno boss theme (#46).

	    local music = MusicPlayer.new()
	    music:SetMuted(true)             -- optional: silence and stop all music tracks
	    music:Update(snapshot, state, dt) -- every frame

	Crossfades smoothly across four public Creator Store chiptune tracks recorded
	in Audio/SoundBank and docs/audio-licences.md:
	  - MusicCalm:    Title screen and Waves 1-4 ("Coin Bonus", 119 BPM)
	  - MusicMid:     Waves 5-8 and Victory ("High Score", 131 BPM)
	  - MusicIntense: Waves 9-12 ("Retro Gamer", 140 BPM)
	  - MusicBoss:    The Inferno ("Final Boss", stepping +1 semitone in Phase 3)

	Ducks gently during Pause and UpgradePick so menus and cards read cleanly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Run = require(ReplicatedStorage.KngChak.Run.Run)
local SoundBank = require(script.Parent.SoundBank)

export type GameState = "Start" | "Playing" | "Paused" | "Finished"
type TrackId = "MusicCalm" | "MusicMid" | "MusicIntense" | "MusicBoss"

local TRACK_IDS: { TrackId } = { "MusicCalm", "MusicMid", "MusicIntense", "MusicBoss" }
local FADE_RATE = 1.6 -- volume units per second for smooth crossfades
local PITCH_EASE = 4.0
local SEMITONE = 2 ^ (1 / 12) -- +1 semitone (~1.0595) keeps Phase 3 boss music in tune

type Track = {
	sound: Sound,
	spec: SoundBank.Sound,
	level: number, -- 0..1 blend weight
	pitch: number,
}

local MusicPlayer = {}
MusicPlayer.__index = MusicPlayer

export type MusicPlayer = typeof(setmetatable(
	{} :: {
		_group: SoundGroup,
		_tracks: { [string]: Track },
		_duck: number,
		_muted: boolean,
	},
	MusicPlayer
))

function MusicPlayer.new(): MusicPlayer
	local group = Instance.new("SoundGroup")
	group.Name = "KngChakMusic"
	group.Volume = 1
	group.Parent = SoundService

	local tracks: { [string]: Track } = {}
	for _, id in TRACK_IDS do
		local spec = (SoundBank :: any)[id] :: SoundBank.Sound
		local sound = Instance.new("Sound")
		sound.Name = id
		sound.SoundId = `rbxassetid://{spec.Id}`
		sound.Volume = 0
		sound.PlaybackSpeed = spec.Pitch
		sound.Looped = true
		sound.SoundGroup = group
		sound.Parent = group
		tracks[id] = {
			sound = sound,
			spec = spec,
			level = 0,
			pitch = spec.Pitch,
		}
	end

	return setmetatable({
		_group = group,
		_tracks = tracks,
		_duck = 1,
		_muted = false,
	}, MusicPlayer)
end

function MusicPlayer.IsMuted(self: MusicPlayer): boolean
	return self._muted
end

function MusicPlayer.SetMuted(self: MusicPlayer, muted: boolean)
	if self._muted == muted then
		return
	end
	self._muted = muted
	self._group.Volume = if muted then 0 else 1
	if muted then
		for _, id in TRACK_IDS do
			local track = self._tracks[id]
			track.level = 0
			track.sound.Volume = 0
			if track.sound.IsPlaying then
				track.sound:Stop()
			end
		end
	end
end

local function pickCue(snapshot: Run.Snapshot, state: GameState): (TrackId, number, number)
	if state == "Start" then
		return "MusicCalm", 0.82, 1.0
	elseif state == "Finished" then
		if snapshot.Phase == "Won" then
			return "MusicMid", 0.62, 1.0
		end
		return "MusicCalm", 0.42, 1.0
	end

	local boss = snapshot.Boss
	if boss then
		local phaseStep = math.clamp(boss.Phase - 1, 0, 2)
		local pitch = if phaseStep >= 2 then SEMITONE else 1.0
		return "MusicBoss", 1.0 + 0.05 * phaseStep, pitch
	end

	local wave = math.max(1, snapshot.Wave)
	if wave <= 4 then
		local t = (wave - 1) / 3
		return "MusicCalm", 0.90 + 0.10 * t, 1.0
	elseif wave <= 8 then
		local t = (wave - 5) / 3
		return "MusicMid", 0.92 + 0.10 * t, 1.0
	else
		local t = math.clamp((wave - 9) / 3, 0, 1)
		return "MusicIntense", 0.95 + 0.10 * t, 1.0
	end
end

function MusicPlayer.Update(self: MusicPlayer, snapshot: Run.Snapshot, state: GameState, dt: number)
	local duckTarget = if state == "Paused" or (state == "Playing" and snapshot.Phase == "UpgradePick")
		then 0.42
		else 1.0
	if self._muted then
		self._duck = duckTarget
		return
	end

	local activeId, intensity, targetPitch = pickCue(snapshot, state)
	self._duck += (duckTarget - self._duck) * math.min(1, 5 * dt)

	for _, id in TRACK_IDS do
		local track = self._tracks[id]
		local want = if id == activeId then intensity else 0
		if id == activeId and track.level == 0 then
			track.pitch = targetPitch
		end
		if track.level < want then
			track.level = math.min(want, track.level + FADE_RATE * dt)
		elseif track.level > want then
			track.level = math.max(want, track.level - FADE_RATE * dt)
		end

		if id == activeId then
			track.pitch += (targetPitch - track.pitch) * math.min(1, PITCH_EASE * dt)
		end

		local sound = track.sound
		sound.Volume = track.spec.Volume * track.level * self._duck
		sound.PlaybackSpeed = track.spec.Pitch * track.pitch

		if track.level > 0.005 then
			if not sound.IsPlaying then
				sound:Play()
			end
		elseif sound.IsPlaying then
			sound:Stop()
		end
	end
end

function MusicPlayer.Destroy(self: MusicPlayer)
	self._group:Destroy()
end

return MusicPlayer
