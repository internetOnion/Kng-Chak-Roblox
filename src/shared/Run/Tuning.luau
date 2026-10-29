--!strict
--[[
	Tuning: the effective tuning values a Run plays with.

	The data modules hold the starting values. A Run reads them only through its
	tuning, which is the data with any overrides on top (the Studio tuning panel
	now; upgrades later). Overrides never write back to the data modules.

	    local tuning = Tuning.new({ Ship = { MaxSpeed = 30 } })
	    tuning.Ship.MaxSpeed --> 30
	    tuning.Arena.ArenaRadius --> ArenaConfig.ArenaRadius
]]

local ArenaConfig = require("../Data/ArenaConfig")
local ShipConfig = require("../Data/ShipConfig")

export type Tuning = {
	Arena: typeof(ArenaConfig),
	Ship: typeof(ShipConfig),
}

-- Section name -> key -> value, e.g. { Ship = { MaxSpeed = 30 } }.
export type Overrides = { [string]: { [string]: any } }

local Tuning = {}

-- The data module behind each section.
local sections: { [string]: { [string]: any } } = {
	Arena = ArenaConfig :: any,
	Ship = ShipConfig :: any,
}
Tuning.Sections = table.freeze(sections)

function Tuning.new(overrides: Overrides?): Tuning
	local tuning: { [string]: any } = {}
	for name, data in sections do
		local section = table.clone(data)
		local changes = overrides and overrides[name]
		if changes then
			for key, value in changes do
				if data[key] == nil then
					error(`unknown tuning value {name}.{key}`, 2)
				end
				section[key] = value
			end
		end
		tuning[name] = table.freeze(section)
	end
	return table.freeze(tuning) :: any
end

return table.freeze(Tuning)
