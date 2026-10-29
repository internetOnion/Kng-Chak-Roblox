--!strict
--[[
	StyleTile: the Toy Box style tile, drawn by the game's own views.

	The same scene as variant A of the art-style prototype, at real game scale
	under the game's camera and lighting: the Ember planet and orbit band, the
	Lancer cruising (soft nose) and boosting (spear and boost flame), every rock
	type and one primed rock. Because it uses the real views and assets, what you
	see here is what the game draws; change an asset and the tile changes too.

	It's built off to the side of the arena, so it never mixes with a Run.

	    local tile = StyleTile.new()
	    tile:Show() ... tile:Hide()
	    camera:LookAt(tile.Focus, arena)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaConfig = require(KngChak.Data.ArenaConfig)
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

-- The prototype's layout, relative to the planet.
local CRUISE = { at = Vector2.new(-17, 13), facing = Vector2.new(1, -0.35).Unit }
local BOOST = { at = Vector2.new(6, 21), facing = Vector2.new(1, 0) }
local ROCKS = {
	{ id = "Shard", at = Vector2.new(21, 7) },
	{ id = "Rock", at = Vector2.new(22, -5) },
	{ id = "Comet", at = Vector2.new(15, -15) },
	{ id = "Iron", at = Vector2.new(2, -21) },
	{ id = "Cluster", at = Vector2.new(-11, -19) },
	{ id = "Gold", at = Vector2.new(-21, -6) },
	{ id = "Rock", at = Vector2.new(15, 21), primed = true },
}

local StyleTile = {}
StyleTile.__index = StyleTile

export type StyleTile = typeof(setmetatable(
	{} :: {
		Focus: Vector2, -- where to point the camera
		_folder: Folder,
	},
	StyleTile
))

function StyleTile.new(): StyleTile
	local folder = Instance.new("Folder")
	folder.Name = "StyleTile"

	Stage.Sky(folder, CENTRE, SKY_HALF)
	PlanetView.new(folder, CENTRE)
	-- the ship is far from the edge, so only the orbit band shows
	RingsView.new(folder, CENTRE):Update(CENTRE, ArenaConfig)

	ShipView.new(folder):Update({
		Position = CENTRE + CRUISE.at,
		Facing = CRUISE.facing,
		IsSpearOut = false,
		IsBoosting = false,
		IsStunned = false,
		FlameReach = ShipConfig.PushRangeMin + (ShipConfig.PushRange - ShipConfig.PushRangeMin) * 0.6,
	})
	ShipView.new(folder):Update({
		Position = CENTRE + BOOST.at,
		Facing = BOOST.facing,
		IsSpearOut = true,
		IsBoosting = true,
		IsStunned = false,
		FlameReach = ShipConfig.PushBoostRange,
	})

	local rocks = {}
	for i, entry in ROCKS do
		local rock = Rock.new(i, RockTypes[entry.id], CENTRE + entry.at)
		rock.IsPrimed = entry.primed == true
		table.insert(rocks, rock)
	end
	RockView.new(folder, CENTRE):Update(rocks)

	return setmetatable({ Focus = CENTRE + Vector2.new(0, -1.5), _folder = folder }, StyleTile)
end

function StyleTile.Show(self: StyleTile)
	self._folder.Parent = workspace
end

function StyleTile.Hide(self: StyleTile)
	self._folder.Parent = nil
end

return StyleTile
