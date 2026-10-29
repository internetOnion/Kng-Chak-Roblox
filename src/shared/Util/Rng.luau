--!strict
--[[
	Rng: a small seeded random number generator (Park–Miller).

	    local rng = Rng.new(1234)
	    rng:Next()           -- 0 <= x < 1
	    rng:Range(2, 5)      -- 2 <= x < 5
	    rng:Chance(0.65)     -- true 65% of the time

	The same seed always gives the same numbers, in Roblox and in the test runner
	alike. The Run uses one of these and never Roblox's Random or math.random,
	which is what makes a seed plus an input recording replay exactly.
]]

local MODULUS = 2147483647 -- 2^31 - 1
local MULTIPLIER = 48271 -- state × this stays below 2^53, so doubles keep it exact

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { _state: number }, Rng))

function Rng.new(seed: number): Rng
	local state = math.floor(math.abs(seed)) % (MODULUS - 1) + 1
	return setmetatable({ _state = state }, Rng)
end

function Rng.Next(self: Rng): number
	self._state = self._state * MULTIPLIER % MODULUS
	return (self._state - 1) / (MODULUS - 1)
end

function Rng.Range(self: Rng, min: number, max: number): number
	return min + (max - min) * self:Next()
end

function Rng.Chance(self: Rng, probability: number): boolean
	return self:Next() < probability
end

return Rng
