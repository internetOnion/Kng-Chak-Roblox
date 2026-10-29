--!strict
--[[
	RockView: draws one model per rock in the Run's snapshot.

	    local rocks = RockView.new(folder)
	    rocks:Update(run:Snapshot().Rocks) -- every frame, after the Run steps

	Update makes a model for each new rock, moves the ones it already has and
	removes models whose rock is gone. Models are clones of
	ReplicatedStorage.Assets.Rocks.Rock, sized and tinted from the rock's type; the
	prefab's PrimeGlow highlight shows while the rock is primed. The view only
	reads the snapshot and never changes the Run.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local Rock = require(KngChak.Rocks.Rock)

local LIFT = 2 -- studs above the play plane (see the art guide's heights)

local RockView = {}
RockView.__index = RockView

export type RockView = typeof(setmetatable(
	{} :: {
		_parent: Instance,
		_prefab: BasePart,
		_models: { [number]: BasePart }, -- by rock Id
	},
	RockView
))

function RockView.new(parent: Instance): RockView
	local prefab = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Rocks"):WaitForChild("Rock") :: BasePart
	return setmetatable({ _parent = parent, _prefab = prefab, _models = {} }, RockView)
end

local function build(self: RockView, rock: Rock.Rock): BasePart
	local model = self._prefab:Clone()
	model.Name = rock.Type.Id
	model.Size = Vector3.one * rock.Type.Radius * 2
	model.Color = rock.Type.Tint
	model.Material = if rock.Type.IsMetal then Enum.Material.Metal else Enum.Material.SmoothPlastic
	model.Parent = self._parent
	return model
end

function RockView.Update(self: RockView, rocks: { Rock.Rock })
	local seen = {}
	for _, rock in rocks do
		seen[rock.Id] = true
		local model = self._models[rock.Id]
		if not model then
			model = build(self, rock)
			self._models[rock.Id] = model
		end
		model.CFrame = ArenaSpace.CFrameAt(rock.Position, nil, LIFT)
		local glow = model:FindFirstChild("PrimeGlow")
		if glow and glow:IsA("Highlight") then
			glow.Enabled = rock.IsPrimed
		end
	end
	for id, model in self._models do
		if not seen[id] then
			model:Destroy()
			self._models[id] = nil
		end
	end
end

function RockView.Destroy(self: RockView)
	for _, model in self._models do
		model:Destroy()
	end
	table.clear(self._models)
end

return RockView
