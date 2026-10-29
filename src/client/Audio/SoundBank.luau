--!strict
--[[
	SoundBank: every sound the game plays, by name, with how loud and at what pitch.

	Swapping a sound means changing its id here, nothing else. Each entry's source
	and licence is recorded in docs/audio-licences.md; keep the two in step.
	All of these are Creator Store sound effects licensed for use in Roblox
	experiences (the Pro Sound Effects library, and one uploaded by Roblox).
]]

export type Sound = {
	Id: number,
	Volume: number,
	Pitch: number,
	Looped: boolean?,
}

local function define(sound: Sound): Sound
	return table.freeze(sound)
end

local SoundBank = {
	-- Low Drone Pulsing Tone Continuous 2 (SFX)
	EngineHum = define({ Id = 9116328633, Volume = 0.25, Pitch = 1.4, Looped = true }),
	-- Whoosh By Fast Airy Swooshing Whipping Thuds (SFX)
	Boost = define({ Id = 9126229255, Volume = 0.5, Pitch = 1.25 }),
	Slingshot = define({ Id = 9126229255, Volume = 0.6, Pitch = 0.85 }),
	-- swoosh.wav (Roblox)
	Push = define({ Id = 12222200, Volume = 0.45, Pitch = 0.8 }),
	-- Rock Drop On Concrete Drops Breaks 1 (SFX)
	Break = define({ Id = 9118587493, Volume = 0.7, Pitch = 1.1 }),
	-- Shield Clang As Hit Metal Sword Hubcap 1 (SFX)
	Clang = define({ Id = 9119072660, Volume = 0.6, Pitch = 1 }),
	-- Low Impacts 3 (SFX)
	Impact = define({ Id = 9116329922, Volume = 0.9, Pitch = 1 }),
	-- Explosions 1 (SFX)
	Bump = define({ Id = 9114361757, Volume = 0.4, Pitch = 1.6 }),
}

return table.freeze(SoundBank)
