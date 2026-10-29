--!strict
local ArenaConfig = require("@shared/Data/ArenaConfig")
local RockTypes = require("@shared/Data/RockTypes")
local Run = require("@shared/Run/Run")
local RunEvents = require("@shared/Run/RunEvents")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local FRAME = 1 / 60

-- Steps a run with no input for `seconds`, in frames of `frame` seconds (default 1/60).
local function play(run: Run.Run, seconds: number, frame: number?)
	local dt = frame or FRAME
	for _ = 1, math.round(seconds / dt) do
		run:Step(Run.IdleInput, dt)
	end
end

-- Records every event a run fires, in order, as { name, ...arguments }.
local function record(run: Run.Run): { { any } }
	local log = {}
	for _, name in RunEvents.Names do
		RunEvents.Get(run.Events, name):Connect(function(...)
			table.insert(log, { name, ... })
		end)
	end
	return log
end

-- Seconds for a rock of `rockType` dropped at `distance` from the planet's centre to reach it.
local function fallTime(rockType: RockTypes.RockType, distance: number): number
	return (distance - ArenaConfig.PlanetRadius - rockType.Radius) / rockType.FallSpeed
end

describe("Run", function()
	describe("a rock falling onto the planet", function()
		local rockType = RockTypes.Rock
		local start = Vector2.new(0, 20)
		local arrival = fallTime(rockType, start.Magnitude)

		-- no drag band slowdown, so the rock falls at one speed all the way (see Rocks/DragBand.spec)
		local function newRun(): Run.Run
			return Run.new({
				Waves = {},
				Rocks = { { Type = rockType, Position = start } },
				Tuning = { Arena = { DragBandMult = 1 } },
			})
		end

		it("starts with the planet at full HP and the rock in the arena", function()
			local snapshot = newRun():Snapshot()
			expect(snapshot.PlanetHp).toBe(ArenaConfig.PlanetMaxHp)
			expect(#snapshot.Rocks).toBe(1)
			expect(snapshot.Rocks[1].Type.Id).toBe("Rock")
			expect(snapshot.Rocks[1].Position).toBe(start)
		end)

		it("moves toward the planet at its type's fall speed", function()
			local run = newRun()
			play(run, 1)
			local rock = run:Snapshot().Rocks[1]
			expect(rock.Position.X).toBeCloseTo(0)
			expect(rock.Position.Y).toBeCloseTo(start.Y - rockType.FallSpeed, 1e-3)
			expect(rock.Velocity.Y).toBeCloseTo(-rockType.FallSpeed)
		end)

		it("does nothing to the planet before it arrives", function()
			local run = newRun()
			local log = record(run)
			play(run, arrival - 0.1)
			expect(#log).toBe(0)
			expect(run:Snapshot().PlanetHp).toBe(ArenaConfig.PlanetMaxHp)
			expect(#run:Snapshot().Rocks).toBe(1)
		end)

		it("fires PlanetHit with its damage on contact, lowers HP by that much and is gone", function()
			local run = newRun()
			local log = record(run)
			play(run, arrival + 0.1)
			expect(#log).toBe(1)
			expect(log[1][1]).toBe("PlanetHit")
			expect(log[1][2].Type.Id).toBe("Rock")
			expect(log[1][3]).toBe(rockType.DamagePercent)
			local snapshot = run:Snapshot()
			expect(snapshot.PlanetHp).toBe(ArenaConfig.PlanetMaxHp - rockType.DamagePercent)
			expect(#snapshot.Rocks).toBe(0)
		end)

		it("hits only once, however long the run keeps going", function()
			local run = newRun()
			local log = record(run)
			play(run, arrival + 5)
			expect(#log).toBe(1)
		end)
	end)

	it("damages the planet by each rock type's own amount", function()
		local run = Run.new({
			Waves = {},
			Rocks = {
				{ Type = RockTypes.Iron, Position = Vector2.new(15, 0) },
				{ Type = RockTypes.Shard, Position = Vector2.new(-15, 0) },
			},
		})
		play(run, 5)
		local expected = ArenaConfig.PlanetMaxHp - RockTypes.Iron.DamagePercent - RockTypes.Shard.DamagePercent
		expect(run:Snapshot().PlanetHp).toBe(expected)
	end)

	it("gives the same result at any frame rate", function()
		local function after(frame: number)
			local run = Run.new({ Waves = {}, Rocks = { { Type = RockTypes.Rock, Position = Vector2.new(30, 40) } } })
			play(run, 3, frame)
			return run:Snapshot().Rocks[1].Position
		end
		local smooth = after(1 / 120)
		for _, frame in { 1 / 60, 1 / 30, 0.1 } do
			local position = after(frame)
			expect(position.X).toBeCloseTo(smooth.X)
			expect(position.Y).toBeCloseTo(smooth.Y)
		end
	end)

	it("hands out snapshots that can't change the run", function()
		local run = Run.new({ Waves = {}, Rocks = { { Type = RockTypes.Rock, Position = Vector2.new(0, 40) } } })
		local snapshot = run:Snapshot()
		expect(function()
			(snapshot.Rocks[1] :: any).Position = Vector2.zero
		end).toThrow()
		expect(function()
			(snapshot :: any).PlanetHp = 0
		end).toThrow()
		expect(run:Snapshot().Rocks[1].Position).toBe(Vector2.new(0, 40))
	end)
end)
