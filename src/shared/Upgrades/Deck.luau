--!strict
--[[
	Deck: which upgrade cards a Run offers after a wave.

	    Deck.Draw(rng, { LongHose = 2 }, 3) --> e.g. { "StickyHeat", "ExtraTank", "Firebreak" }

	Draws up to `count` different upgrades that haven't reached their stack limit,
	at random from the Run's seeded RNG, from different families where possible:
	each card prefers a family no earlier card has. Fewer come back when fewer
	are left to pick.
]]

local Rng = require("../Util/Rng")
local Upgrades = require("../Data/Upgrades")

local Deck = {}

-- Ids of upgrades that can still be picked, given the `stacks` already picked.
function Deck.Available(stacks: { [string]: number }): { string }
	local out = {}
	for _, upgrade in Upgrades.List do
		if (stacks[upgrade.Id] or 0) < upgrade.MaxStacks then
			table.insert(out, upgrade.Id)
		end
	end
	return out
end

function Deck.Draw(rng: Rng.Rng, stacks: { [string]: number }, count: number): { string }
	local pool = Deck.Available(stacks)
	local drawn = {}
	local families = {}
	for _ = 1, math.min(count, #pool) do
		local fresh = {}
		for index, id in pool do
			if not families[Upgrades.ById[id].Family] then
				table.insert(fresh, index)
			end
		end
		local index
		if #fresh > 0 then
			index = fresh[math.clamp(math.floor(rng:Next() * #fresh) + 1, 1, #fresh)]
		else
			index = math.clamp(math.floor(rng:Next() * #pool) + 1, 1, #pool)
		end
		local id = table.remove(pool, index) :: string
		families[Upgrades.ById[id].Family] = true
		table.insert(drawn, id)
	end
	return table.freeze(drawn)
end

return table.freeze(Deck)
