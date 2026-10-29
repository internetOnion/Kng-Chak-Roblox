--!strict
--[[
	Run: one emergency call, as a headless simulation.

	    local run = Run.new({
	        Rocks = { { Type = RockTypes.Rock, Position = Vector2.new(0, 40) } },
	    })
	    run.Events.PlanetHit:Connect(function(rock, damagePercent) ... end)

	    -- every frame:
	    run:Step(input, dt)
	    local snapshot = run:Snapshot()

	The Run holds the game rules. It knows nothing about Parts, cameras or GUIs and
	creates no Instances: views read its snapshot and events and never change it.
	Step splits the frame's time into fixed sub-steps, so results don't depend on
	the frame rate.

	First slice: rocks fall onto the planet and damage it. Flight, combat, waves
	and the rest are built on top of this, one feature at a time.
]]

local PlanetHealth = require("../Combat/PlanetHealth")
local Rock = require("../Rocks/Rock")
local RockTypes = require("../Data/RockTypes")
local RunEvents = require("./RunEvents")

local STEP = 1 / 60 -- seconds per fixed sub-step
local MAX_FRAME = 0.25 -- a longer frame (a hitch) only advances this much, so nothing teleports
local EPSILON = 1e-9 -- absorbs float error, so 1/30 s always makes exactly two sub-steps

-- The player's flight input for one frame. Touch, mouse and gamepad all produce this shape.
export type Input = {
	Move: Vector2, -- direction to steer toward (unit length), or zero
	MoveStrength: number, -- 0..1, how hard to thrust that way
	BoostPressed: boolean, -- boost went down this frame
	BoostHeld: boolean,
	Brake: boolean,
}

export type RockSetup = {
	Type: RockTypes.RockType,
	Position: Vector2,
}

export type Setup = {
	Rocks: { RockSetup }?, -- rocks already in the arena when the run starts
}

-- What other code may read. Rebuilt on every Snapshot() call; changing it changes nothing.
export type Snapshot = {
	PlanetHp: number,
	PlanetMaxHp: number,
	Rocks: { Rock.Rock },
}

local Run = {}
Run.__index = Run

Run.IdleInput = table.freeze({
	Move = Vector2.zero,
	MoveStrength = 0,
	BoostPressed = false,
	BoostHeld = false,
	Brake = false,
}) :: Input

export type Run = typeof(setmetatable(
	{} :: {
		Events: RunEvents.RunEvents,
		_planet: PlanetHealth.PlanetHealth,
		_rocks: { Rock.Rock },
		_nextRockId: number,
		_pending: number, -- frame time not simulated yet, less than one sub-step
	},
	Run
))

local function addRock(self: Run, rockType: RockTypes.RockType, position: Vector2)
	table.insert(self._rocks, Rock.new(self._nextRockId, rockType, position))
	self._nextRockId += 1
end

local function tick(self: Run, _input: Input, dt: number)
	local survivors = {}
	for _, rock in self._rocks do
		Rock.Fall(rock, dt)
		if Rock.TouchesPlanet(rock) then
			local damage = rock.Type.DamagePercent
			self.Events.PlanetHit:Fire(Rock.Snapshot(rock), damage)
			self._planet:TakeDamage(damage)
		else
			table.insert(survivors, rock)
		end
	end
	self._rocks = survivors
end

function Run.new(setup: Setup?): Run
	local self = setmetatable({
		Events = RunEvents.new(),
		_planet = PlanetHealth.new(),
		_rocks = {},
		_nextRockId = 1,
		_pending = 0,
	}, Run)
	local rocks = setup and setup.Rocks
	if rocks then
		for _, rock in rocks do
			addRock(self, rock.Type, rock.Position)
		end
	end
	return self
end

-- Advances the run by dt seconds of play, with this frame's input.
function Run.Step(self: Run, input: Input, dt: number)
	self._pending += math.clamp(dt, 0, MAX_FRAME)
	while self._pending >= STEP - EPSILON do
		self._pending = math.max(0, self._pending - STEP)
		tick(self, input, STEP)
	end
end

function Run.Snapshot(self: Run): Snapshot
	local rocks = table.create(#self._rocks)
	for _, rock in self._rocks do
		table.insert(rocks, Rock.Snapshot(rock))
	end
	return table.freeze({
		PlanetHp = self._planet.Hp,
		PlanetMaxHp = self._planet.MaxHp,
		Rocks = table.freeze(rocks),
	})
end

function Run.Destroy(self: Run)
	RunEvents.DisconnectAll(self.Events)
	self._planet:Destroy()
end

return Run
