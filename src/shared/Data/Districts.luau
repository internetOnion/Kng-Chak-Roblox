--!strict
--[[
	Districts: visual and stage data per planet district, plus shared Toy Box model tints.

	    local Districts = require(ReplicatedStorage.KngChak.Data.Districts)
	    local ember = Districts.Ember

	Every planet reuses the same Planet model ("tint, don't rebuild"): views paint
	Ocean, Land, LandDark, Ice and Rim parts from the active district's palette, and
	Stage paints the sky backdrop and star layers from it. Primed and outline colours
	also live here so views read changing model colours from frozen data.
]]

export type District = {
	Id: string,
	Name: string,
	Subtitle: string,
	-- Planet model part tints
	Ocean: Color3,
	Land: Color3,
	LandDark: Color3,
	Ice: Color3,
	Rim: Color3,
	RimTransparency: number,
	SpinRate: number, -- radians per second around the north-tilted polar axis
	-- Sky and two-layer starfield
	Sky: Color3,
	Nebula: Color3,
	StarPrimary: Color3,
	StarAccent: Color3,
	FarFollow: number, -- 0..1: how much the deep star layer follows the camera (higher = farther away)
	NearFollow: number, -- 0..1: how much the near star layer follows the camera
}

local function define(district: District): District
	return table.freeze(district)
end

local ember = define({
	Id = "Ember",
	Name = "Ember",
	Subtitle = "First District",
	Ocean = Color3.fromHex("#2fc4ff"),
	Land = Color3.fromHex("#5ee05e"),
	LandDark = Color3.fromHex("#3fb34a"),
	Ice = Color3.fromHex("#ffffff"),
	Rim = Color3.fromHex("#7fe6ff"),
	RimTransparency = 0.72,
	SpinRate = 0.12,
	Sky = Color3.fromHex("#3d3ad8"),
	Nebula = Color3.fromHex("#5652f0"),
	StarPrimary = Color3.fromHex("#ffffff"),
	StarAccent = Color3.fromHex("#ffe066"),
	FarFollow = 0.68,
	NearFollow = 0.34,
})

local list = table.freeze({ ember })
local byId = table.freeze({
	Ember = ember,
})

local Districts = {
	-- Shared Toy Box outline and primed state values (docs/art-guide.md)
	Outline = Color3.fromHex("#000000"),
	Primed = Color3.fromHex("#ff4fd8"),
	PrimedFill = 0.55,
	MaxHighlights = 31, -- Roblox's engine cap on simultaneously rendered Highlights

	Ember = ember,
	Default = ember,
	List = list,
	ById = byId,
}

return table.freeze(Districts)
