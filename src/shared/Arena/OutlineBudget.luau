--!strict
--[[
	OutlineBudget: decides which visible models get a Roblox Highlight and which
	use the fallback hull outline once more than MaxHighlights (31) would show.

	Kept pure in shared/Arena so the priority and cap rules are unit-tested headless.

	Priority order (lowest Rank wins):
	  1. Essential hero objects (Ship, Planet, Boss body/core/plates)
	  2. Primed rocks (so pink primed highlights stay crisp first)
	  3. Loose rocks nearest the planet, with Id breaking ties deterministically
]]

local Districts = require("../Data/Districts")

export type Candidate = {
	Key: number, -- unique registration id (breaks ties deterministically)
	Visible: boolean,
	Tier: number, -- 1 = hero (ship/planet/boss), 2 = primed rock, 3 = unprimed rock, 4 = decoration
	Distance: number, -- arena distance from planet centre (closer wins within a tier)
}

local OutlineBudget = {}

--[[
	Returns a set `{ [Key]: boolean }` mapping every `Visible` candidate's Key to
	`true` if it receives a Highlight (at most `limit`, default 31) or `false` if
	it must render with the fallback hull outline. Invisible candidates are omitted.
]]
function OutlineBudget.Select(candidates: { Candidate }, limit: number?): { [number]: boolean }
	local cap = limit or Districts.MaxHighlights
	local active: { Candidate } = {}
	for _, item in candidates do
		if item.Visible then
			table.insert(active, item)
		end
	end

	local result: { [number]: boolean } = {}
	if #active <= cap then
		for _, item in active do
			result[item.Key] = true
		end
		return result
	end

	table.sort(active, function(a: Candidate, b: Candidate): boolean
		if a.Tier ~= b.Tier then
			return a.Tier < b.Tier
		end
		if math.abs(a.Distance - b.Distance) > 1e-4 then
			return a.Distance < b.Distance
		end
		return a.Key < b.Key
	end)

	for index, item in active do
		result[item.Key] = index <= cap
	end
	return result
end

return table.freeze(OutlineBudget)
