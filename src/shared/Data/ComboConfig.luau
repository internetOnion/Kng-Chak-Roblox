--!strict
--[[
	ComboConfig: combos, heals and fuel refunds.

	Values come from the web prototype's TUNE table. Game code reads them through
	the Run's tuning (see Run/Tuning) and never writes them: the table is frozen.
	Heals are percentages of the planet's HP. Only combo moves heal: plain rams never do.
]]

local ComboConfig = {
	-- The chain
	Window = 4, -- seconds after a move before the combo runs out (it only counts down while rocks are in the air)
	MultPerCombo = 0.1, -- score multiplier = 1 + combo × this...
	MaxMult = 5, -- ...up to this
	RegenPerCombo = 0.075, -- fuel regen multiplier = 1 + combo × this...
	MaxRegenCombo = 20, -- ...counting the combo up to this

	-- Combo points each move adds
	PushPoints = 1, -- the first prime of a rock, by the flame or the orbit flare
	SlingshotPoints = 1,
	RamPoints = 1, -- a plain boosted ram
	PushBreakPoints = 3, -- primed, then rammed
	DivePoints = 3, -- slingshot into an unprimed rock
	PerfectPoints = 6, -- primed, then slingshot

	-- Heals (% of planet HP)
	HealPushBreak = 3,
	HealDive = 2,
	HealPerfect = 6,
	HealGold = 15, -- a golden rock (only a PERFECT breaks it)

	-- Fuel
	PushBreakRefuel = 30, -- fuel back for breaking a primed rock

	-- Shockwave (an upgrade sets the radius)
	ShockwaveRadius = 0, -- breaking a primed rock primes every rock within this distance of it
}

export type ComboConfig = typeof(ComboConfig)

return table.freeze(ComboConfig)
