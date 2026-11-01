--!strict
--[[
	StyleTile: the Toy Box style tile and Ember art-set showcase, drawn by the game's own views.

	The same scene as variant A of the art-style prototype, at real game scale
	under the game's camera and lighting: the spinning Ember planet and orbit band,
	the Lancer cruising (soft nose), boosting (spear + boost flame) and slingshotting
	(spear + blue flame), every rock type across shape variants, a primed rock and
	the break debris chunks. Because it uses the real views and assets, what you see
	here is what the game draws; change an asset and the tile changes too.

	It's built off to the side of the arena, so it never mixes with a Run.

	    local tile = StyleTile.new()
	    tile:Show() ... tile:Update(dt) ... tile:Hide()
	    camera:LookAt(tile.Focus, arena)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaConfig = require(KngChak.Data.ArenaConfig)
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local Rock = require(KngChak.Rocks.Rock)
local RockTypes = require(KngChak.Data.RockTypes)
local ShipConfig = require(KngChak.Data.ShipConfig)

local PlanetView = require(script.Parent.Parent.Views.PlanetView)
local RingsView = require(script.Parent.Parent.Views.RingsView)
local RockView = require(script.Parent.Parent.Views.RockView)
local ShipView = require(script.Parent.Parent.Views.ShipView)
local Stage = require(script.Parent.Parent.Views.Stage)

local CENTRE = Vector2.new(1000, 0) -- far from the arena (radius 66)
local SKY_HALF = Vector2.new(160, 110)

-- Layout relative to the planet: fits inside both Zoom 50 and Zoom 35.
local SHIPS = {
	{
		at = Vector2.new(-16, 13),
		facing = Vector2.new(1, -0.35).Unit,
		spear = false,
		boost = false,
		slingshot = false,
		reach = ShipConfig.PushRangeMin + (ShipConfig.PushRange - ShipConfig.PushRangeMin) * 0.6,
		throttle = 0.6,
	},
	{
		at = Vector2.new(5, 20),
		facing = Vector2.new(1, 0),
		spear = true,
		boost = true,
		slingshot = false,
		reach = ShipConfig.PushBoostRange,
		throttle = 1.0,
	},
	{
		at = Vector2.new(-22, 1),
		facing = Vector2.new(0.45, -0.9).Unit,
		spear = true,
		boost = false,
		slingshot = true,
		reach = ShipConfig.PushBoostRange * 0.9,
		throttle = 1.0,
	},
}

-- `id` sets the Rock.Id (1 -> variant a, 2 -> variant b, 3 -> variant c).
local ROCKS: { { typeId: string, variant: number, at: Vector2, primed: boolean? } } = {
	-- Inner showcase ring (variant a + primed rock)
	{ typeId = "Rock", variant = 2, at = Vector2.new(16, 19), primed = true },
	{ typeId = "Shard", variant = 1, at = Vector2.new(21, 7) },
	{ typeId = "Rock", variant = 1, at = Vector2.new(22, -4) },
	{ typeId = "Comet", variant = 1, at = Vector2.new(15, -15) },
	{ typeId = "Iron", variant = 1, at = Vector2.new(2, -21) },
	{ typeId = "Cluster", variant = 1, at = Vector2.new(-11, -19) },
	{ typeId = "Gold", variant = 1, at = Vector2.new(-20, -9) },
	-- Outer variant ring (variants b & c)
	{ typeId = "Shard", variant = 2, at = Vector2.new(30, 12) },
	{ typeId = "Rock", variant = 3, at = Vector2.new(31, 0) },
	{ typeId = "Comet", variant = 2, at = Vector2.new(27, -13) },
	{ typeId = "Iron", variant = 2, at = Vector2.new(13, -25) },
	{ typeId = "Cluster", variant = 2, at = Vector2.new(-2, -28) },
	{ typeId = "Gold", variant = 3, at = Vector2.new(-19, -24) },
}

local DEBRIS_OFFSETS = {
	{ at = Vector2.new(-29, 17), tint = Color3.fromHex("#c98b55"), angle = 15 },
	{ at = Vector2.new(-32, 13), tint = Color3.fromHex("#b25fd0"), angle = 75 },
	{ at = Vector2.new(-28, 9), tint = Color3.fromHex("#7487a3"), angle = 140 },
	{ at = Vector2.new(-32, 5), tint = Color3.fromHex("#ffcf2e"), angle = 215 },
}

local StyleTile = {}
StyleTile.__index = StyleTile

export type StyleTile = typeof(setmetatable(
	{} :: {
		Focus: Vector2, -- where to point the camera
		_folder: Folder,
		_planet: PlanetView.PlanetView,
		_sky: Stage.SkyView,
		_clock: number,
	},
	StyleTile
))

local function spawnDebrisShowcase(parent: Instance)
	local assets = ReplicatedStorage:WaitForChild("Assets"):FindFirstChild("Debris")
	if not assets then
		return
	end
	local chunks: { Model } = {}
	for _, child in assets:GetChildren() do
		if child:IsA("Model") then
			table.insert(chunks, child)
		end
	end
	table.sort(chunks, function(a: Model, b: Model): boolean
		return a.Name < b.Name
	end)
	if #chunks == 0 then
		return
	end
	for i, spec in DEBRIS_OFFSETS do
		local prefab = chunks[(i - 1) % #chunks + 1]
		local model = prefab:Clone()
		model.WorldPivot = CFrame.identity
		model:ScaleTo(0.85)
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and string.sub(part.Name, 1, 4) == "Body" then
				part.Color = spec.tint
			end
		end
		local rad = math.rad(spec.angle)
		model:PivotTo(ArenaSpace.CFrameAt(CENTRE + spec.at, Vector2.new(math.cos(rad), math.sin(rad)), 2))
		model.Parent = parent
	end
end

function StyleTile.new(): StyleTile
	local folder = Instance.new("Folder")
	folder.Name = "StyleTile"

	local sky = Stage.Sky(folder, CENTRE, SKY_HALF)
	local planet = PlanetView.new(folder, CENTRE)
	-- the ship is far from the edge, so only the orbit band shows
	RingsView.new(folder, CENTRE):Update({ Position = CENTRE, IsCaptured = false }, ArenaConfig)

	for _, entry in SHIPS do
		ShipView.new(folder):Update({
			Position = CENTRE + entry.at,
			Facing = entry.facing,
			FlameDirection = -entry.facing,
			IsSpearOut = entry.spear,
			IsBoosting = entry.boost,
			IsSlingshotting = entry.slingshot,
			IsStunned = false,
			FlameReach = entry.reach,
			Throttle = entry.throttle,
		}, 0, false)
	end

	local rocks: { Rock.Rock } = {}
	for i, entry in ROCKS do
		-- Pick a Rock.Id whose remainder mod 3 equals entry.variant (1, 2 or 3), while keeping every Id unique.
		local uniqueId = (i - 1) * 3 + entry.variant
		local rock = Rock.new(uniqueId, RockTypes[entry.typeId], CENTRE + entry.at)
		rock.IsPrimed = entry.primed == true
		table.insert(rocks, rock)
	end
	RockView.new(folder, CENTRE):Update(rocks)
	spawnDebrisShowcase(folder)

	return setmetatable({
		Focus = CENTRE + Vector2.new(0, -1.5),
		_folder = folder,
		_planet = planet,
		_sky = sky,
		_clock = 0,
	}, StyleTile)
end

function StyleTile.Update(self: StyleTile, dt: number)
	self._clock += dt
	self._planet:Update(dt)
	-- Subtle star drift so parallax depth is visible even on the static tile.
	local drift = Vector2.new(math.sin(self._clock * 0.45) * 8, math.cos(self._clock * 0.32) * 5)
	self._sky:Update(CENTRE + drift)
end

function StyleTile.Show(self: StyleTile)
	self._folder.Parent = workspace
end

function StyleTile.Hide(self: StyleTile)
	self._folder.Parent = nil
end

return StyleTile
