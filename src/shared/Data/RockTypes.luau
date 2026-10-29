--!strict
--[[
	RockTypes: one definition per kind of rock (area 5 owns the values).

	    local RockTypes = require(ReplicatedStorage.KngChak.Data.RockTypes)
	    local rock = Rock.new(RockTypes.Rock, position)

	Values come from the web prototype's TYPES table; colours come from the Toy Box
	palette in docs/art-guide.md. Each definition is frozen: game code reads it and
	never changes it.
]]

-- What it takes to break a rock with the spear; anything less clangs off it.
--   Any           any boosted ram or slingshot
--   Primed        only once primed (a comet is too fast to ram until a push slows it)
--   PrimedOrDive  once primed, or by a slingshot (iron)
--   Perfect       only a PERFECT: primed, then slingshot (gold, the Inferno's core)
export type BreaksBy = "Any" | "Primed" | "PrimedOrDive" | "Perfect"

-- What a rock breaks into (a cluster's shards).
export type Split = {
	Into: string, -- the shards' rock type id
	Count: number,
	Speed: number, -- shards fly apart this fast...
	Lift: number, -- ...plus this fast away from the planet
	Grace: number, -- seconds before a new shard can hit the ship (so the ram that split it doesn't break them all)
}

export type RockType = {
	Id: string,
	Radius: number, -- arena units (the prototype's `size` is a radius)
	FallSpeed: number, -- arena units per second toward the planet, at wave 1
	SlowFallSpeed: number?, -- comet only: fall speed after it has been pushed
	BreaksBy: BreaksBy,
	Tint: Color3, -- body colour; the rock view paints the model's Body parts with it
	Glow: Color3?, -- energy glow, for rocks that have one (the comet's tail)
	IsMetal: boolean,
	Score: number, -- points for breaking it
	PushFactor: number, -- how far a flame push moves it (1 = normal, lower = moves less)
	DamagePercent: number, -- planet HP lost when it hits
	Split: Split?, -- breaking it splits it into shards
	IsBossPart: boolean?, -- part of the Inferno: it rides on the boss and never falls on its own
}

local function define(def: RockType): RockType
	return table.freeze(def)
end

local RockTypes = {
	Rock = define({
		Id = "Rock",
		BreaksBy = "Any",
		Radius = 1.4,
		FallSpeed = 3.0,
		Tint = Color3.fromHex("#c98b55"),
		IsMetal = false,
		Score = 100,
		PushFactor = 1.0,
		DamagePercent = 8,
	}),
	Comet = define({
		Id = "Comet",
		BreaksBy = "Primed",
		Radius = 1.1,
		FallSpeed = 7.5,
		SlowFallSpeed = 2.0,
		Tint = Color3.fromHex("#c9f7ff"),
		Glow = Color3.fromHex("#7fe6ff"),
		IsMetal = false,
		Score = 150,
		PushFactor = 0.8,
		DamagePercent = 8,
	}),
	Iron = define({
		Id = "Iron",
		BreaksBy = "PrimedOrDive",
		Radius = 1.8,
		FallSpeed = 1.8,
		Tint = Color3.fromHex("#7487a3"),
		IsMetal = true,
		Score = 200,
		PushFactor = 0.3,
		DamagePercent = 15,
	}),
	Cluster = define({
		Id = "Cluster",
		BreaksBy = "Any",
		Radius = 2.4,
		FallSpeed = 2.6,
		Tint = Color3.fromHex("#b25fd0"),
		IsMetal = false,
		Score = 100,
		PushFactor = 0.6,
		DamagePercent = 10,
		Split = table.freeze({ Into = "Shard", Count = 3, Speed = 7, Lift = 3, Grace = 0.45 }),
	}),
	Shard = define({
		Id = "Shard",
		BreaksBy = "Any",
		Radius = 0.85,
		FallSpeed = 3.5,
		Tint = Color3.fromHex("#e8b27a"),
		IsMetal = false,
		Score = 50,
		PushFactor = 1.4,
		DamagePercent = 4,
	}),
	Gold = define({
		Id = "Gold",
		BreaksBy = "Perfect",
		Radius = 1.5,
		FallSpeed = 2.4,
		Tint = Color3.fromHex("#ffcf2e"),
		Glow = Color3.fromHex("#5a3c00"),
		IsMetal = true,
		Score = 500,
		PushFactor = 0.7,
		DamagePercent = 8,
	}),
	-- The Inferno's parts (see Boss/Inferno). They ride on the boss, so FallSpeed and DamagePercent are unused.
	Plate = define({
		Id = "Plate",
		BreaksBy = "Primed",
		Radius = 1.7,
		FallSpeed = 0,
		Tint = Color3.fromHex("#5a2a1e"),
		Glow = Color3.fromHex("#ff6a1f"),
		IsMetal = true,
		Score = 300,
		PushFactor = 0,
		DamagePercent = 0,
		IsBossPart = true,
	}),
	Core = define({
		Id = "Core",
		BreaksBy = "Perfect",
		Radius = 2.6,
		FallSpeed = 0,
		Tint = Color3.fromHex("#7487a3"),
		Glow = Color3.fromHex("#ffe066"),
		IsMetal = true,
		Score = 1000,
		PushFactor = 0,
		DamagePercent = 0,
		IsBossPart = true,
	}),
}

return table.freeze(RockTypes)
