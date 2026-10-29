--!strict
--[[
	Combo: the chain of moves, ported from the web prototype.

	Every move (a push, a flare, a slingshot, a break) adds its combo points and
	restarts the combo window. The window only counts down while rocks are in the
	air, so dead air between groups never costs a chain. A bump or a planet
	impact loses the combo straight away. A higher combo raises the score
	multiplier and the fuel regen.

	The Run owns one combo; combat and orbit add to it through the Run's context.
	Fires ComboChanged on every change.
]]

local RunEvents = require("../Run/RunEvents")
local Tuning = require("../Run/Tuning")

export type Combo = {
	Count: number,
	Best: number, -- the highest the combo reached this run
	Time: number, -- seconds left in the window
}

local Combo = {}

function Combo.new(): Combo
	return { Count = 0, Best = 0, Time = 0 }
end

-- Score multiplier at this combo.
function Combo.Multiplier(combo: Combo, tuning: Tuning.Tuning): number
	local config = tuning.Combo
	return math.min(config.MaxMult, 1 + combo.Count * config.MultPerCombo)
end

-- Fuel regen multiplier at this combo.
function Combo.RegenMultiplier(combo: Combo, tuning: Tuning.Tuning): number
	local config = tuning.Combo
	return 1 + math.min(combo.Count, config.MaxRegenCombo) * config.RegenPerCombo
end

-- Adds `points` for `move` (e.g. "Push", "Perfect") and restarts the window.
function Combo.Add(combo: Combo, tuning: Tuning.Tuning, events: RunEvents.RunEvents, points: number, move: string)
	combo.Count += points
	combo.Best = math.max(combo.Best, combo.Count)
	combo.Time = tuning.Combo.Window
	events.ComboChanged:Fire(combo.Count, move)
end

-- Loses the combo because of `reason` ("Bump", "Impact" or "Timeout").
function Combo.Lose(combo: Combo, events: RunEvents.RunEvents, reason: string)
	combo.Time = 0
	if combo.Count > 0 then
		combo.Count = 0
		events.ComboChanged:Fire(0, reason)
	end
end

-- Counts the window down by dt while `rocksInAir`.
function Combo.Step(combo: Combo, events: RunEvents.RunEvents, rocksInAir: boolean, dt: number)
	if combo.Time > 0 and rocksInAir then
		combo.Time -= dt
		if combo.Time <= 0 then
			Combo.Lose(combo, events, "Timeout")
		end
	end
end

return table.freeze(Combo)
