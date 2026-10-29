--!strict
--[[
	ShipController: the ship's public API (milestone 1, contract 4, area 1).

	Other areas code against these fields and nothing else. Flight (task 5) fills
	them in; until then the values are fake and the ship sits still at its start.

	    ship.Position    Vector2  arena position
	    ship.Velocity    Vector2  arena units per second
	    ship.Facing      Vector2  unit vector the nose points along
	    ship.Throttle    number   0..1, how hard the engine pushes (sets the flame's reach)
	    ship.IsBoosting  boolean

	Read the fields but never set them from outside the Ship area.

	Events:
	    Bumped (rock: Rock, knock: Vector2)  a rock hit the ship's back half; knock is the
	                                         velocity it gets knocked away with
]]

local ArenaConfig = require("../Data/ArenaConfig")
local Rock = require("../Rocks/Rock")
local Signal = require("../Util/Signal")

local ShipController = {}
ShipController.__index = ShipController

export type ShipController = typeof(setmetatable(
	{} :: {
		Position: Vector2,
		Velocity: Vector2,
		Facing: Vector2,
		Throttle: number,
		IsBoosting: boolean,
		Bumped: Signal.Signal,
	},
	ShipController
))

function ShipController.new(start: Vector2?): ShipController
	return setmetatable({
		Position = start or ArenaConfig.ShipStart,
		Velocity = Vector2.zero,
		Facing = Vector2.new(0, -1), -- nose away from the planet
		Throttle = 0,
		IsBoosting = false,
		Bumped = Signal.new(),
	}, ShipController)
end

-- Combat calls this when a rock hits the ship's back half (task 13).
-- Flight (task 5) will apply the knock; for now it only fires Bumped.
function ShipController.Bump(self: ShipController, rock: Rock.Rock, knock: Vector2)
	self.Bumped:Fire(rock, knock)
end

function ShipController.Destroy(self: ShipController)
	self.Bumped:DisconnectAll()
end

return ShipController
