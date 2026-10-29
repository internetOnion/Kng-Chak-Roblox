--!strict
--[[
	WaveConfig: how waves are built and paced (area 5 owns the values).

	Values come from the web prototype's TUNE table. Game code reads them through
	the Run's tuning (see Run/Tuning) and never writes them: the table is frozen.
]]

local WaveConfig = {
	-- Size
	WaveBase = 6, -- rocks per wave = WaveBase + wave × WavePerLevel
	WavePerLevel = 1,
	InFlightStart = 4, -- most rocks in the air at once at wave 1...
	InFlightMax = 7, -- ...rising by 1 every 2 waves up to this

	-- Mix: plain rocks' share drops each wave; the specials fill the rest
	PlainShareDrop = 0.1,
	PlainShareMin = 0.3,
	CometFrom = 3, -- the first wave each special appears in (its intro wave)
	IronFrom = 5,
	ClusterFrom = 7,
	CometWeight = 1,
	IronWeight = 0.8,
	ClusterWeight = 0.7,

	-- Pacing
	FirstGroupDelay = 1.2, -- seconds from a wave's start to its first group
	GroupInterval = 4, -- seconds between groups at wave 1...
	GroupIntervalDrop = 0.25, -- ...minus this per wave...
	GroupIntervalMin = 1.5, -- ...down to this
	GroupSpreadDeg = 16, -- rocks in a group arrive this many degrees apart
	FullWaitRetry = 0.4, -- seconds before trying again when the in-flight cap is full
	Breather = 3, -- seconds between a wave clearing and the next one starting

	-- Spawning
	SpawnBeyondEdge = 3, -- rocks appear this far outside the arena edge...
	SpawnDepth = 6, -- ...plus up to this much more
	SpeedPerWave = 0.05, -- fall speed grows this much per wave...
	SpeedMaxMult = 1.4, -- ...and stops growing here
}

export type WaveConfig = typeof(WaveConfig)

return table.freeze(WaveConfig)
