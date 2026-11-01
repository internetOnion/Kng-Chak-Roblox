--!strict
--[[
	RockView: draws one model per rock in the Run's snapshot.

	    local rocks = RockView.new(folder)
	    rocks:Update(run:Snapshot().Rocks) -- every frame, after the Run steps

	Update makes a model for each new rock, moves the ones it already has and
	removes models whose rock is gone. Each rock type's entry in
	ReplicatedStorage.Assets.Rocks may be either a single Model (Plate, Core) or
	a Folder of shape variants (kc_rock_<type>_a/b/c), picked deterministically
	from rock.Id so replays draw the same shapes. Body*, Tail*/Seam*/Crack* and
	primed colours come from data, and Outlines manages the 31-Highlight budget.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local Districts = require(KngChak.Data.Districts)
local Rock = require(KngChak.Rocks.Rock)

local Outlines = require(script.Parent.Outlines)

local LIFT = 2 -- studs above the play plane (see the art guide's heights)
local PRIMED_BODY_BLEND = 0.35

type Drawn = {
	model: Model,
	bodyParts: { BasePart },
	outline: Outlines.Handle,
	primed: boolean?,
}

local RockView = {}
RockView.__index = RockView

export type RockView = typeof(setmetatable(
	{} :: {
		_parent: Instance,
		_prefabs: Folder,
		_planet: Vector2, -- where rocks point (the planet's centre)
		_variants: { [string]: { Model } },
		_drawn: { [number]: Drawn }, -- by rock Id
	},
	RockView
))

-- `planet` is where rocks point (default: the arena's centre).
function RockView.new(parent: Instance, planet: Vector2?): RockView
	local prefabs = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Rocks") :: Folder
	return setmetatable({
		_parent = parent,
		_prefabs = prefabs,
		_planet = planet or Vector2.zero,
		_variants = {},
		_drawn = {},
	}, RockView)
end

local function collectVariants(entry: Instance): { Model }
	if entry:IsA("Model") then
		return { entry }
	end
	local list: { Model } = {}
	for _, child in entry:GetChildren() do
		if child:IsA("Model") then
			table.insert(list, child)
		end
	end
	table.sort(list, function(a: Model, b: Model): boolean
		return a.Name < b.Name
	end)
	return list
end

local function resolvePrefab(self: RockView, typeId: string, rockId: number): Model
	local cached = self._variants[typeId]
	local variants: { Model }
	if cached then
		variants = cached
	else
		local entry = self._prefabs:FindFirstChild(typeId) or self._prefabs:WaitForChild("Rock")
		variants = collectVariants(entry)
		if #variants == 0 then
			variants = collectVariants(self._prefabs:WaitForChild("Rock"))
		end
		self._variants[typeId] = variants
	end
	local index = (math.max(1, rockId) - 1) % #variants + 1
	return variants[index]
end

local function build(self: RockView, rock: Rock.Rock): Drawn
	local prefab = resolvePrefab(self, rock.Type.Id, rock.Id)
	local model = prefab:Clone()
	model.Name = rock.Type.Id
	model.WorldPivot = CFrame.identity -- assets are built around the origin; Studio may have picked another pivot
	model:ScaleTo(rock.Type.Radius)

	local bodyParts: { BasePart } = {}
	local glow = rock.Type.Glow
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local name = part.Name
			if string.sub(name, 1, 4) == "Body" then
				part.Color = rock.Type.Tint
				table.insert(bodyParts, part)
			elseif
				glow
				and (
					string.sub(name, 1, 4) == "Tail"
					or string.sub(name, 1, 4) == "Seam"
					or string.sub(name, 1, 5) == "Crack"
					or string.sub(name, 1, 5) == "Facet"
				)
			then
				part.Color = glow
			end
		end
	end

	model.Parent = self._parent
	local initialTier = if rock.Type.IsBossPart then Outlines.Tier.Hero else Outlines.Tier.Rock
	local outline = Outlines.Register(model, rock.Type.Radius, initialTier)
	return {
		model = model,
		bodyParts = bodyParts,
		outline = outline,
		primed = nil,
	}
end

function RockView.Update(self: RockView, rocks: { Rock.Rock })
	local seen: { [number]: boolean } = {}
	for _, rock in rocks do
		seen[rock.Id] = true
		local drawn = self._drawn[rock.Id]
		if not drawn then
			drawn = build(self, rock)
			self._drawn[rock.Id] = drawn
		end
		-- front toward the planet, so a comet's tail streams out behind it
		local toPlanet = self._planet - rock.Position
		drawn.model:PivotTo(ArenaSpace.CFrameAt(rock.Position, toPlanet, LIFT))

		if drawn.primed ~= rock.IsPrimed then
			drawn.primed = rock.IsPrimed
			local bodyColor = if rock.IsPrimed
				then rock.Type.Tint:Lerp(Districts.Primed, PRIMED_BODY_BLEND)
				else rock.Type.Tint
			for _, part in drawn.bodyParts do
				part.Color = bodyColor
			end
		end

		local tier = if rock.Type.IsBossPart
			then Outlines.Tier.Hero
			elseif rock.IsPrimed then Outlines.Tier.PrimedRock
			else Outlines.Tier.Rock
		drawn.outline:SetState(true, rock.IsPrimed, toPlanet.Magnitude, tier)
	end
	for id, drawn in self._drawn do
		if not seen[id] then
			drawn.outline:Unregister()
			drawn.model:Destroy()
			self._drawn[id] = nil
		end
	end
end

function RockView.Destroy(self: RockView)
	for _, drawn in self._drawn do
		drawn.outline:Unregister()
		drawn.model:Destroy()
	end
	table.clear(self._drawn)
end

return RockView
