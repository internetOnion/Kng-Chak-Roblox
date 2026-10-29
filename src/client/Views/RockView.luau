--!strict
--[[
	RockView: draws one model per rock in the Run's snapshot.

	    local rocks = RockView.new(folder)
	    rocks:Update(run:Snapshot().Rocks) -- every frame, after the Run steps

	Update makes a model for each new rock, moves the ones it already has and
	removes models whose rock is gone. Each rock type's model is the one named
	after it in ReplicatedStorage.Assets.Rocks (Assets.Rocks.Rock if there's none),
	built at radius 1 with its front along -Z. The view scales it to the type's
	radius, paints its Body parts with the type's tint and points it at the planet.
	Its Outline highlight is black, and pink while the rock is primed. Swapping a
	model in the assets folder changes the rock with no code change. The view only
	reads the snapshot and never changes the Run.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local Rock = require(KngChak.Rocks.Rock)

local LIFT = 2 -- studs above the play plane (see the art guide's heights)
local OUTLINE = Color3.fromHex("#000000")
local PRIMED = Color3.fromHex("#ff4fd8")
local PRIMED_FILL = 0.55 -- fill transparency while primed

type Drawn = {
	model: Model,
	outline: Highlight?,
	primed: boolean?,
}

local RockView = {}
RockView.__index = RockView

export type RockView = typeof(setmetatable(
	{} :: {
		_parent: Instance,
		_prefabs: Folder,
		_drawn: { [number]: Drawn }, -- by rock Id
	},
	RockView
))

function RockView.new(parent: Instance): RockView
	local prefabs = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Rocks") :: Folder
	return setmetatable({ _parent = parent, _prefabs = prefabs, _drawn = {} }, RockView)
end

local function build(self: RockView, rock: Rock.Rock): Drawn
	local prefab = (self._prefabs:FindFirstChild(rock.Type.Id) or self._prefabs:WaitForChild("Rock")) :: Model
	local model = prefab:Clone()
	model.Name = rock.Type.Id
	model.WorldPivot = CFrame.identity -- assets are built around the origin; Studio may have picked another pivot
	model:ScaleTo(rock.Type.Radius)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and string.sub(part.Name, 1, 4) == "Body" then
			part.Color = rock.Type.Tint
		end
	end
	model.Parent = self._parent
	return { model = model, outline = model:FindFirstChildOfClass("Highlight"), primed = nil }
end

function RockView.Update(self: RockView, rocks: { Rock.Rock })
	local seen = {}
	for _, rock in rocks do
		seen[rock.Id] = true
		local drawn = self._drawn[rock.Id]
		if not drawn then
			drawn = build(self, rock)
			self._drawn[rock.Id] = drawn
		end
		-- front toward the planet, so a comet's tail streams out behind it
		drawn.model:PivotTo(ArenaSpace.CFrameAt(rock.Position, -rock.Position, LIFT))

		local outline = drawn.outline
		if outline and drawn.primed ~= rock.IsPrimed then
			drawn.primed = rock.IsPrimed
			outline.OutlineColor = if rock.IsPrimed then PRIMED else OUTLINE
			outline.FillColor = PRIMED
			outline.FillTransparency = if rock.IsPrimed then PRIMED_FILL else 1
		end
	end
	for id, drawn in self._drawn do
		if not seen[id] then
			drawn.model:Destroy()
			self._drawn[id] = nil
		end
	end
end

function RockView.Destroy(self: RockView)
	for _, drawn in self._drawn do
		drawn.model:Destroy()
	end
	table.clear(self._drawn)
end

return RockView
