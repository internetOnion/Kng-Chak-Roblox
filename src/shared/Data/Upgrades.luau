--!strict
--[[
	Upgrades: the 10 upgrade cards, one family per core move.

	Values come from the design pitch's upgrade table. After each wave the Run
	offers 3 cards, from different families where possible, and the player picks
	one. An upgrade never patches code: each one names the tuning values it
	changes, and the Run's tuning applies them (see Run/Tuning). Each stacks up to
	MaxStacks. Game code reads these and never writes them: every table is frozen.

	An effect changes one tuning value, per stack:
	    Scale  value × (1 + Scale × stacks)    e.g. 0.2 = +20% a stack
	    Add    value + Add × stacks
]]

export type Family = "Flame" | "Spear" | "Orbit" | "Any"

export type Effect = {
	Section: string, -- a tuning section: "Ship", "Combo", "Arena" or "Waves"
	Key: string,
	Scale: number?,
	Add: number?,
}

export type Upgrade = {
	Id: string,
	Name: string,
	Family: Family,
	Stat: string, -- bold badge under the visual diagram
	Text: string, -- short plain-English caption for the card
	MaxStacks: number,
	Effects: { Effect },
}

local function define(def: Upgrade): Upgrade
	for _, effect in def.Effects do
		table.freeze(effect)
	end
	table.freeze(def.Effects)
	return table.freeze(def)
end

local Upgrades = {}

-- Every upgrade, in a fixed order (offers draw from this list, so the order matters for a seed).
Upgrades.List = table.freeze({
	-- Flame
	define({
		Id = "LongHose",
		Name = "Long Hose",
		Family = "Flame",
		Stat = "+20% REACH",
		Text = "Longer flame push",
		MaxStacks = 2,
		Effects = {
			{ Section = "Ship", Key = "PushRangeMin", Scale = 0.2 },
			{ Section = "Ship", Key = "PushRange", Scale = 0.2 },
			{ Section = "Ship", Key = "PushBoostRange", Scale = 0.2 },
			{ Section = "Ship", Key = "FlareRange", Scale = 0.2 },
		},
	}),
	define({
		Id = "WideNozzle",
		Name = "Wide Nozzle",
		Family = "Flame",
		Stat = "+30% WIDTH",
		Text = "Wider flame cone",
		MaxStacks = 2,
		Effects = {
			{ Section = "Ship", Key = "PushConeDeg", Scale = 0.3 },
			{ Section = "Ship", Key = "FlareConeDeg", Scale = 0.3 },
		},
	}),
	define({
		Id = "StickyHeat",
		Name = "Sticky Heat",
		Family = "Flame",
		Stat = "+3s PRIMED",
		Text = "Rocks stay pink longer",
		MaxStacks = 2,
		Effects = { { Section = "Ship", Key = "PrimedTime", Add = 3 } },
	}),

	-- Spear
	define({
		Id = "TemperedTip",
		Name = "Tempered Tip",
		Family = "Spear",
		Stat = "+0.3s SPEAR",
		Text = "Boost spear lasts longer",
		MaxStacks = 2,
		Effects = { { Section = "Ship", Key = "BoostDuration", Add = 0.3 } },
	}),
	define({
		Id = "ExtraTank",
		Name = "Extra Tank",
		Family = "Spear",
		Stat = "+1 BOOST BAR",
		Text = "Carry 1 extra boost",
		MaxStacks = 2,
		Effects = { { Section = "Ship", Key = "FuelMax", Add = 30 } }, -- one BoostCost
	}),
	define({
		Id = "Shockwave",
		Name = "Shockwave",
		Family = "Spear",
		Stat = "CHAIN PRIME",
		Text = "Break primes nearby rocks",
		MaxStacks = 1,
		Effects = { { Section = "Combo", Key = "ShockwaveRadius", Add = 4 } },
	}),

	-- Orbit
	define({
		Id = "QuickRelease",
		Name = "Quick Release",
		Family = "Orbit",
		Stat = "−30% WAIT",
		Text = "Slingshot ready sooner",
		MaxStacks = 2,
		Effects = { { Section = "Ship", Key = "SlingshotCooldown", Scale = -0.3 } },
	}),
	define({
		Id = "LongDive",
		Name = "Long Dive",
		Family = "Orbit",
		Stat = "+20% SPEED",
		Text = "Faster slingshot dive",
		MaxStacks = 2,
		Effects = { { Section = "Ship", Key = "SlingshotSpeed", Scale = 0.2 } },
	}),
	define({
		Id = "Firebreak",
		Name = "Firebreak",
		Family = "Orbit",
		Stat = "+2% HEAL",
		Text = "PERFECT heals planet more",
		MaxStacks = 2,
		Effects = { { Section = "Combo", Key = "HealPerfect", Add = 2 } },
	}),

	-- Any
	define({
		Id = "ShieldPlating",
		Name = "Shield Plating",
		Family = "Any",
		Stat = "35% SHIELD",
		Text = "Bigger planet shield cap",
		MaxStacks = 1,
		Effects = { { Section = "Arena", Key = "PlanetMaxShield", Add = 10 } },
	}),
})

-- Upgrade id -> upgrade.
local byId: { [string]: Upgrade } = {}
for _, upgrade in Upgrades.List do
	byId[upgrade.Id] = upgrade
end
Upgrades.ById = table.freeze(byId)

Upgrades.OfferSize = 3 -- cards offered after each wave

return table.freeze(Upgrades)
