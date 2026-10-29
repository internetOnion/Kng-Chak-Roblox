--!strict
local ArenaConfig = require("@shared/Data/ArenaConfig")
local RockTypes = require("@shared/Data/RockTypes")
local Run = require("@shared/Run/Run")
local RunEvents = require("@shared/Run/RunEvents")
local RunInput = require("@shared/Run/RunInput")
local ShipConfig = require("@shared/Data/ShipConfig")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local FRAME = 1 / 60
local SHIP = Vector2.new(0, -40)
local TRACK = ArenaConfig.PlanetRadius + ArenaConfig.OrbitAlt
local RIGHT = Vector2.new(1, 0)
local LEFT = Vector2.new(-1, 0)

local function play(run: Run.Run, input: RunInput.RunInput, seconds: number)
	for _ = 1, math.round(seconds / FRAME) do
		run:Step(input, FRAME)
	end
end

local function count(run: Run.Run): { [string]: number }
	local counts = {}
	for _, name in RunEvents.Names do
		counts[name] = 0
		RunEvents.Get(run.Events, name):Connect(function()
			counts[name] += 1
		end)
	end
	return counts
end

-- The ship out in the arena facing `heading`, with one rock at `offset` from it.
local function arena(rockType: RockTypes.RockType, offset: Vector2, heading: number?): Run.Run
	return Run.new({
		Waves = {},
		ShipStart = SHIP,
		ShipHeading = heading or 0,
		Rocks = { { Type = rockType, Position = SHIP + offset } },
	})
end

-- Rams the rock 6 units to the right of the ship with a boost.
local function ram(rockType: RockTypes.RockType): (Run.Run, { [string]: number })
	local run = arena(rockType, Vector2.new(6, 0))
	local counts = count(run)
	run:Step(RunInput.steer(RIGHT, 1, true, false), FRAME)
	play(run, RunInput.steer(RIGHT), 0.25)
	return run, counts
end

-- Primes the rock behind the ship with the flame, then turns round and rams it.
local function pushThenRam(rockType: RockTypes.RockType): (Run.Run, { [string]: number })
	local run = arena(rockType, Vector2.new(4.5, 0), math.pi)
	local counts = count(run)
	play(run, RunInput.steer(LEFT), 0.15)
	assert(run:Snapshot().Rocks[1].IsPrimed, "the push primes it")
	run:Step(RunInput.steer(RIGHT, 1, true, false), FRAME)
	play(run, RunInput.steer(RIGHT), 0.4)
	return run, counts
end

-- Slingshots out of orbit into an unprimed rock waiting farther out.
local function slingshotInto(rockType: RockTypes.RockType): (Run.Run, { [string]: number })
	local run = Run.new({
		Waves = {},
		ShipStart = Vector2.new(0, -TRACK),
		ShipHeading = 0,
		Rocks = { { Type = rockType, Position = Vector2.new(0, -(TRACK + 12)) } },
		Tuning = { Ship = { OrbitEntryMin = 0 } },
	})
	local counts = count(run)
	run:Step(RunInput.Idle, FRAME)
	play(run, RunInput.steer(Vector2.new(0, -1)), 0.5)
	return run, counts
end

describe("Comet rules", function()
	it("clangs off an unpushed comet instead of breaking it, knocking the ship back", function()
		local run, counts = ram(RockTypes.Comet)
		expect(counts.RockClanged).toBe(1)
		expect(counts.RockBroken).toBe(0)
		expect(#run:Snapshot().Rocks).toBe(1)
		local ship = run:Snapshot().Ship
		expect(ship.IsSpearOut).toBe(false)
		expect(ship.Velocity.X < 0).toBe(true) -- knocked back, away from the comet
	end)

	it("stuns the ship briefly on a clang", function()
		local run = arena(RockTypes.Comet, Vector2.new(6, 0))
		run:Step(RunInput.steer(RIGHT, 1, true, false), FRAME)
		local stunned = false
		for _ = 1, 15 do
			run:Step(RunInput.steer(RIGHT), FRAME)
			stunned = stunned or run:Snapshot().Ship.IsStunned
		end
		expect(stunned).toBe(true)
		play(run, RunInput.Idle, ShipConfig.ClangStunTime + 0.1)
		expect(run:Snapshot().Ship.IsStunned).toBe(false)
	end)

	it("slows a pushed comet to its slow fall speed", function()
		local run = arena(RockTypes.Comet, Vector2.new(-4, 0))
		local before = run:Snapshot().Rocks[1].FallSpeed
		play(run, RunInput.steer(RIGHT), 0.15)
		local comet = run:Snapshot().Rocks[1]
		expect(comet.IsPrimed).toBe(true)
		expect(before > (RockTypes.Comet.SlowFallSpeed :: number)).toBe(true)
		expect(comet.FallSpeed).toBe(RockTypes.Comet.SlowFallSpeed)
		play(run, RunInput.Idle, 6) -- long after priming wears off, it still falls slowly
		comet = run:Snapshot().Rocks[1]
		expect(comet.IsPrimed).toBe(false)
		expect(comet.Velocity:Dot(-comet.Position.Unit)).toBeCloseTo(RockTypes.Comet.SlowFallSpeed :: number, 0.1)
	end)

	it("breaks a pushed comet", function()
		local _, counts = pushThenRam(RockTypes.Comet)
		expect(counts.RockBroken).toBe(1)
		expect(counts.RockClanged).toBe(0)
	end)

	it("clangs a slingshot off an unpushed comet too", function()
		local _, counts = slingshotInto(RockTypes.Comet)
		expect(counts.RockClanged).toBe(1)
		expect(counts.RockBroken).toBe(0)
	end)
end)

describe("Iron rules", function()
	it("clangs a plain ram off iron", function()
		local run, counts = ram(RockTypes.Iron)
		expect(counts.RockClanged).toBe(1)
		expect(counts.RockBroken).toBe(0)
		expect(#run:Snapshot().Rocks).toBe(1)
	end)

	it("keeps the combo through a clang", function()
		local run = Run.new({
			Waves = {},
			ShipStart = SHIP,
			ShipHeading = 0,
			Rocks = {
				{ Type = RockTypes.Rock, Position = SHIP + Vector2.new(5, 0) },
				{ Type = RockTypes.Iron, Position = SHIP + Vector2.new(11, 0) },
			},
		})
		local counts = count(run)
		run:Step(RunInput.steer(RIGHT, 1, true, false), FRAME)
		play(run, RunInput.steer(RIGHT), 0.3)
		expect(counts.RockBroken).toBe(1)
		expect(counts.RockClanged).toBe(1)
		expect(run:Snapshot().Combo).toBe(1)
	end)

	it("breaks primed iron", function()
		local _, counts = pushThenRam(RockTypes.Iron)
		expect(counts.RockBroken).toBe(1)
		expect(counts.RockClanged).toBe(0)
	end)

	it("lets a slingshot break unprimed iron", function()
		local _, counts = slingshotInto(RockTypes.Iron)
		expect(counts.RockBroken).toBe(1)
		expect(counts.RockClanged).toBe(0)
	end)
end)

describe("Gold rules", function()
	it("clangs anything but a PERFECT off gold", function()
		local _, rammed = ram(RockTypes.Gold)
		expect(rammed.RockClanged).toBe(1)
		local _, dived = slingshotInto(RockTypes.Gold)
		expect(dived.RockClanged).toBe(1)
		expect(dived.RockBroken).toBe(0)
	end)
end)
