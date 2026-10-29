--!strict
--[[
	RockTypes: one definition per kind of rock (area 5 owns the values).

	    local RockTypes = require(ReplicatedStorage.KngChak.Data.RockTypes)
	    local rock = Rock.new(RockTypes.Rock, position)

	Values come from the web prototype's TYPES table. Each definition is frozen:
	game code reads it and never changes it.
]]

export type RockType = {
	Id: string,
	Radius: number, -- arena units (the prototype's `size` is a radius)
	FallSpeed: number, -- arena units per second toward the planet, at wave 1
	SlowFallSpeed: number?, -- comet only: fall speed after it has been pushed
	Tint: Color3,
	Glow: Color3?, -- energy glow, for rocks that have one
	IsMetal: boolean,
	Score: number, -- points for breaking it
	PushFactor: number, -- how far a flame push moves it (1 = normal, lower = moves less)
	DamagePercent: number, -- planet HP lost when it hits
}

local function define(def: RockType): RockType
	return table.freeze(def)
end

local RockTypes = {
	Rock = define({
		Id = "Rock",
		Radius = 1.4,
		FallSpeed = 3.0,
		Tint = Color3.fromHex("#b08a68"),
		IsMetal = false,
		Score = 100,
		PushFactor = 1.0,
		DamagePercent = 8,
	}),
	Comet = define({
		Id = "Comet",
		Radius = 1.1,
		FallSpeed = 7.5,
		SlowFallSpeed = 2.0,
		Tint = Color3.fromHex("#bff6ff"),
		Glow = Color3.fromHex("#2a8fa0"),
		IsMetal = false,
		Score = 150,
		PushFactor = 0.8,
		DamagePercent = 8,
	}),
	Iron = define({
		Id = "Iron",
		Radius = 1.8,
		FallSpeed = 1.8,
		Tint = Color3.fromHex("#5d6b7d"),
		IsMetal = true,
		Score = 200,
		PushFactor = 0.3,
		DamagePercent = 15,
	}),
	Cluster = define({
		Id = "Cluster",
		Radius = 2.4,
		FallSpeed = 2.6,
		Tint = Color3.fromHex("#8a5a7a"),
		IsMetal = false,
		Score = 100,
		PushFactor = 0.6,
		DamagePercent = 10,
	}),
	Shard = define({
		Id = "Shard",
		Radius = 0.85,
		FallSpeed = 3.5,
		Tint = Color3.fromHex("#c49a74"),
		IsMetal = false,
		Score = 50,
		PushFactor = 1.4,
		DamagePercent = 4,
	}),
	Gold = define({
		Id = "Gold",
		Radius = 1.5,
		FallSpeed = 2.4,
		Tint = Color3.fromHex("#ffd166"),
		Glow = Color3.fromHex("#5a3c00"),
		IsMetal = true,
		Score = 500,
		PushFactor = 0.7,
		DamagePercent = 8,
	}),
}

return table.freeze(RockTypes)
