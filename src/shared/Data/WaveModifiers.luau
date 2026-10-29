--!strict
--[[
	WaveModifiers: the twists late waves get, and the tips that introduce each threat.

	Values and words come from the web prototype's MODS and INTRO tables. From
	WaveConfig.RemixStart to RemixEnd each wave gets one modifier (a surge gets two),
	never one the wave before had. Each asks for combos, not more rocks. Game code
	reads these and never writes them: every table is frozen.
]]

export type Modifier = {
	Id: string,
	Name: string, -- shown on the wave banner
	Tip: string,
	Weights: { [string]: number }?, -- rock type id -> multiplier on its share of the specials
	PlainShare: number?, -- multiplier on plain rocks' share of the mix
	Gold: number?, -- golden rocks slipped into the wave
	Pincer: boolean?, -- groups land on both sides of the planet at once
	Tuning: { [string]: { [string]: any } }?, -- tuning values set while the wave plays (see Run/Tuning)
}

local function define(def: Modifier): Modifier
	if def.Weights then
		table.freeze(def.Weights)
	end
	if def.Tuning then
		for _, section in def.Tuning do
			table.freeze(section)
		end
		table.freeze(def.Tuning)
	end
	return table.freeze(def)
end

local WaveModifiers = {}

-- Every modifier, in a fixed order (picks draw from this list, so the order matters for a seed).
WaveModifiers.List = table.freeze({
	define({
		Id = "CometStorm",
		Name = "Comet storm",
		Tip = "Mostly comets. Push every one first.",
		Weights = { Comet = 3 },
		PlainShare = 0.5,
	}),
	define({
		Id = "IronRain",
		Name = "Iron rain",
		Tip = "Iron-heavy. Push-then-break or flare + slingshot.",
		Weights = { Iron = 3 },
		PlainShare = 0.5,
	}),
	define({
		Id = "Bloom",
		Name = "Bloom",
		Tip = "Clusters split into 4 shards.",
		Weights = { Cluster = 2 },
		Tuning = { Waves = { ExtraShards = 1 } },
	}),
	define({
		Id = "Pincer",
		Name = "Pincer",
		Tip = "Groups land on both sides of the planet at once.",
		Pincer = true,
	}),
	define({
		Id = "LowDrag",
		Name = "Low drag",
		Tip = "The slow band above orbit is thin. Flare early.",
		Tuning = { Arena = { DragBandMult = 0.8 } },
	}),
	define({
		Id = "GoldenRock",
		Name = "Golden rock",
		Tip = "One golden rock: only a PERFECT breaks it, for +15%.",
		Gold = 1,
	}),
})

-- Modifier id -> modifier.
local byId: { [string]: Modifier } = {}
for _, modifier in WaveModifiers.List do
	byId[modifier.Id] = modifier
end
WaveModifiers.ById = table.freeze(byId)

-- The banner tip for the wave that introduces a rock type, by rock type id.
WaveModifiers.Intros = table.freeze({
	Rock = "Ram rocks with a boosted nose. Push them first: only combo moves repair the planet.",
	Comet = "COMET · too fast to ram. Push it with your exhaust, then break it.",
	Iron = "IRON · plain rams clang off. Push-then-break or dive slingshot.",
	Cluster = "CLUSTER · splits into 3 shards. Chain them.",
} :: { [string]: string })

return table.freeze(WaveModifiers)
