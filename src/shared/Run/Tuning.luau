--!strict
--[[
	Tuning: the effective tuning values a Run plays with.

	The data modules hold the starting values. A Run reads them only through its
	tuning, which is the data with layers on top, in this order:

	1. overrides: values set outright (the Studio tuning panel, a test's setup)
	2. modifiers: the current wave's modifiers (see Data/WaveModifiers)
	3. upgrades: the upgrades picked so far, each stacked (see Data/Upgrades)

	Nothing ever writes back to the data modules.

	    local tuning = Tuning.new({ Ship = { MaxSpeed = 30 } })
	    tuning.Ship.MaxSpeed --> 30
	    tuning.Arena.ArenaRadius --> ArenaConfig.ArenaRadius

	    Tuning.new(nil, { Upgrades = { LongHose = 2 } }).Ship.PushRange --> PushRange × 1.4
]]

local ArenaConfig = require("../Data/ArenaConfig")
local ComboConfig = require("../Data/ComboConfig")
local InfernoConfig = require("../Data/InfernoConfig")
local ShipConfig = require("../Data/ShipConfig")
local Upgrades = require("../Data/Upgrades")
local WaveConfig = require("../Data/WaveConfig")
local WaveModifiers = require("../Data/WaveModifiers")

export type Tuning = {
	Arena: ArenaConfig.ArenaConfig,
	Combo: ComboConfig.ComboConfig,
	Inferno: InfernoConfig.InfernoConfig,
	Ship: ShipConfig.ShipConfig,
	Waves: WaveConfig.WaveConfig,
}

-- Section name -> key -> value, e.g. { Ship = { MaxSpeed = 30 } }.
export type Overrides = { [string]: { [string]: any } }

-- What a Run has picked up so far: upgrade id -> stacks, and the current wave's modifier ids.
export type Layers = {
	Upgrades: { [string]: number }?,
	Modifiers: { string }?,
}

local Tuning = {}

-- The data module behind each section.
local sections: { [string]: { [string]: any } } = {
	Arena = ArenaConfig :: any,
	Combo = ComboConfig :: any,
	Inferno = InfernoConfig :: any,
	Ship = ShipConfig :: any,
	Waves = WaveConfig :: any,
}
Tuning.Sections = table.freeze(sections)

local function set(tuning: { [string]: { [string]: any } }, changes: Overrides, level: number)
	for name, values in changes do
		local section = tuning[name]
		if not section then
			error(`unknown tuning section {name}`, level)
		end
		for key, value in values do
			if sections[name][key] == nil then
				error(`unknown tuning value {name}.{key}`, level)
			end
			section[key] = value
		end
	end
end

function Tuning.new(overrides: Overrides?, layers: Layers?): Tuning
	local tuning: { [string]: { [string]: any } } = {}
	for name, data in sections do
		tuning[name] = table.clone(data)
	end
	if overrides then
		set(tuning, overrides, 3)
	end
	if layers and layers.Modifiers then
		for _, id in layers.Modifiers do
			local modifier = WaveModifiers.ById[id]
			if not modifier then
				error(`unknown wave modifier {id}`, 2)
			end
			if modifier.Tuning then
				set(tuning, modifier.Tuning, 3)
			end
		end
	end
	if layers and layers.Upgrades then
		-- in the list's order, so the result never depends on how the table iterates
		for _, upgrade in Upgrades.List do
			local stacks = layers.Upgrades[upgrade.Id] or 0
			if stacks > 0 then
				for _, effect in upgrade.Effects do
					local section = tuning[effect.Section]
					local value = section[effect.Key]
					if effect.Scale then
						value *= 1 + effect.Scale * stacks
					end
					if effect.Add then
						value += effect.Add * stacks
					end
					section[effect.Key] = value
				end
			end
		end
	end
	for name, section in tuning do
		tuning[name] = table.freeze(section)
	end
	return table.freeze(tuning) :: any
end

return table.freeze(Tuning)
