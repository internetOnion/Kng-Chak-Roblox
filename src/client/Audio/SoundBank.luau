--!strict
--[[
	SoundBank: every sound and music cue the game plays, by name, with volume and pitch.

	Swapping an audio asset means changing its id here, nothing else. Each entry's
	source and licence is recorded in docs/audio-licences.md; keep the two in step.
	All entries are public, moderated Creator Store assets licensed by Roblox
	(Pro Sound Effects, APM Music and Roblox).
]]

export type Sound = {
	Id: number,
	Volume: number,
	Pitch: number,
	Looped: boolean?,
	IsMusic: boolean?,
}

local function define(sound: Sound): Sound
	return table.freeze(sound)
end

local SoundBank = {
	-- Engine & flight
	EngineHum = define({ Id = 9116328633, Volume = 0.25, Pitch = 1.4, Looped = true }),
	Boost = define({ Id = 9126229255, Volume = 0.5, Pitch = 1.25 }),
	Slingshot = define({ Id = 9126229255, Volume = 0.62, Pitch = 0.85 }),
	OrbitLock = define({ Id = 9113399926, Volume = 0.26, Pitch = 1.38 }),

	-- Combat, combo & planet defense
	Push = define({ Id = 12222200, Volume = 0.45, Pitch = 0.8 }),
	Flare = define({ Id = 9125644310, Volume = 0.44, Pitch = 1.28 }),
	Break = define({ Id = 9118587493, Volume = 0.7, Pitch = 1.1 }),
	Perfect = define({ Id = 9125446879, Volume = 0.68, Pitch = 1.08 }),
	CoreCrack = define({ Id = 9125446879, Volume = 0.75, Pitch = 0.86 }),
	Clang = define({ Id = 9119072660, Volume = 0.6, Pitch = 1 }),
	Bump = define({ Id = 9114361757, Volume = 0.4, Pitch = 1.6 }),
	Impact = define({ Id = 9116329922, Volume = 0.9, Pitch = 1 }),
	ShieldHit = define({ Id = 9118196441, Volume = 0.58, Pitch = 1.15 }),
	Heal = define({ Id = 9125644310, Volume = 0.38, Pitch = 1.02 }),
	ImpactAlarm = define({ Id = 9113399926, Volume = 0.34, Pitch = 1.65 }),

	-- Wave flow & menus
	WaveStart = define({ Id = 9120005874, Volume = 0.30, Pitch = 1.18 }),
	WaveClear = define({ Id = 9125641284, Volume = 0.42, Pitch = 1.18 }),
	UpgradePick = define({ Id = 9125644310, Volume = 0.48, Pitch = 1.45 }),
	Victory = define({ Id = 9125641284, Volume = 0.68, Pitch = 1.0 }),
	Defeat = define({ Id = 9120005874, Volume = 0.52, Pitch = 0.65 }),
	UiClick = define({ Id = 9118138365, Volume = 0.34, Pitch = 1.4 }),

	-- Wave-escalating music & Inferno boss theme
	MusicCalm = define({ Id = 1837392508, Volume = 0.28, Pitch = 1.0, Looped = true, IsMusic = true }),
	MusicMid = define({ Id = 9043678925, Volume = 0.30, Pitch = 1.0, Looped = true, IsMusic = true }),
	MusicIntense = define({ Id = 89610760991334, Volume = 0.32, Pitch = 1.0, Looped = true, IsMusic = true }),
	MusicBoss = define({ Id = 9042357350, Volume = 0.36, Pitch = 1.0, Looped = true, IsMusic = true }),
}

return table.freeze(SoundBank)
