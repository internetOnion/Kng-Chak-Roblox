--!strict
--[[
	Rock: one rock in the arena (milestone 1, contract 3, area 2).

	    local rock = Rock.new(RockTypes.Rock, Vector2.new(0, 40))
	    rock.Broken:Connect(function(cause) ... end)
	    rock:Prime()
	    rock:Break("Ram")

	The model is a clone of the prefab ReplicatedStorage.Assets.Rocks.Rock, sized
	and tinted from the rock type. Its PrimeGlow highlight shows while primed.
	Positions are arena positions (see Arena/ArenaSpace). This contract only holds
	state: falling is task 10 and pushing is task 14.

	Read the fields but never set them; use the methods so the model and events follow.

	Events (each also fires the matching GameEvents event):
	    Primed ()               on the first prime only
	    Broken (cause: string)  the player destroyed it, e.g. cause "Ram"
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaSpace = require("../Arena/ArenaSpace")
local GameEvents = require("../GameEvents")
local RockTypes = require("../Data/RockTypes")
local Signal = require("../Util/Signal")

local Rock = {}
Rock.__index = Rock

export type Rock = typeof(setmetatable(
	{} :: {
		Type: RockTypes.RockType,
		Position: Vector2,
		Velocity: Vector2,
		IsPrimed: boolean,
		IsBroken: boolean,
		Model: BasePart,
		Primed: Signal.Signal,
		Broken: Signal.Signal,
	},
	Rock
))

local function getPrefab(): BasePart
	local assets = ReplicatedStorage:WaitForChild("Assets")
	return assets:WaitForChild("Rocks"):WaitForChild("Rock") :: BasePart
end

-- Spawns a rock of `rockType` at an arena position. `parent` defaults to Workspace.
function Rock.new(rockType: RockTypes.RockType, position: Vector2, parent: Instance?): Rock
	local model = getPrefab():Clone()
	model.Name = rockType.Id
	model.Size = Vector3.one * rockType.Radius * 2
	model.Color = rockType.Tint
	model.Material = if rockType.IsMetal then Enum.Material.Metal else Enum.Material.SmoothPlastic
	model.CFrame = ArenaSpace.CFrameAt(position)
	model.Parent = parent or workspace

	return setmetatable({
		Type = rockType,
		Position = position,
		Velocity = Vector2.zero,
		IsPrimed = false,
		IsBroken = false,
		Model = model,
		Primed = Signal.new(),
		Broken = Signal.new(),
	}, Rock)
end

function Rock.SetPosition(self: Rock, position: Vector2)
	self.Position = position
	self.Model.CFrame = ArenaSpace.CFrameAt(position)
end

-- Marks the rock as pushed by the flame. Priming again does nothing.
function Rock.Prime(self: Rock)
	if self.IsPrimed or self.IsBroken then
		return
	end
	self.IsPrimed = true
	local glow = self.Model:FindFirstChild("PrimeGlow")
	if glow and glow:IsA("Highlight") then
		glow.Enabled = true
	end
	self.Primed:Fire()
	GameEvents.RockPrimed:Fire(self)
end

-- The player destroyed the rock: fires Broken, then removes it.
function Rock.Break(self: Rock, cause: string)
	if self.IsBroken then
		return
	end
	self.IsBroken = true
	self.Broken:Fire(cause)
	GameEvents.RockBroken:Fire(self, cause)
	self:Destroy()
end

-- Removes the rock without breaking it (it hit the planet, or the run reset).
function Rock.Destroy(self: Rock)
	self.Model:Destroy()
	self.Primed:DisconnectAll()
	self.Broken:DisconnectAll()
end

return Rock
