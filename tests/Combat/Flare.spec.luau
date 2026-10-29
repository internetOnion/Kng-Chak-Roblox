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
local TRACK = ArenaConfig.PlanetRadius + ArenaConfig.OrbitAlt

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

--[[
	The ship sits still on the orbit track at the bottom of the planet (orbit entry
	speed 0, so it doesn't circle away), with a rock `above` units farther out.
]]
local function underRock(above: number, rockType: RockTypes.RockType?): Run.Run
	local run = Run.new({
		Waves = {},
		ShipStart = Vector2.new(0, -TRACK),
		ShipHeading = 0,
		Rocks = { { Type = rockType or RockTypes.Rock, Position = Vector2.new(0, -(TRACK + above)) } },
		Tuning = { Ship = { OrbitEntryMin = 0 } },
	})
	run:Step(RunInput.Idle, FRAME)
	assert(run:Snapshot().Ship.IsInOrbit, "the ship locks on")
	return run
end

local function rock(run: Run.Run)
	return run:Snapshot().Rocks[1]
end

describe("Orbit flare", function()
	it("fans the flame outward, away from the planet, while in orbit", function()
		local run = underRock(30)
		play(run, RunInput.Idle, 0.5)
		local ship = run:Snapshot().Ship
		expect(ship.FlameDirection:Dot(ship.Position.Unit)).toBeCloseTo(1, 1e-3)
		expect(ship.FlameReach).toBeCloseTo(ShipConfig.FlareRange, 0.01)
	end)

	it("primes a rock it touches, pops it up and makes it hang nearly still", function()
		local run = underRock(6)
		local counts = count(run)
		play(run, RunInput.Idle, 0.4)
		expect(counts.RockFlared).toBe(1)
		expect(counts.RockPrimed).toBe(1)
		local r = rock(run)
		expect(r.IsPrimed).toBe(true)
		expect(r.IsFlared).toBe(true)
		expect(r.Position.Magnitude > TRACK + 6).toBe(true) -- popped up
		play(run, RunInput.Idle, ShipConfig.FlareHang - 0.6)
		expect(rock(run).Velocity.Magnitude < 1).toBe(true) -- hanging
		expect(rock(run).HangTime > 0).toBe(true)
	end)

	it("lets the rock fall again after the hang time", function()
		local run = underRock(6)
		play(run, RunInput.Idle, ShipConfig.FlareHang + 0.8)
		local r = rock(run)
		expect(r.HangTime).toBe(0)
		expect(r.Velocity:Dot(-r.Position.Unit) > 0.5).toBe(true)
	end)

	it("flares a rock only once, even when it falls back through the flare", function()
		local run = underRock(6)
		local counts = count(run)
		play(run, RunInput.Idle, 4)
		expect(counts.RockFlared).toBe(1)
	end)

	it("keeps a flared rock primed while the flare still touches it, without lifting it again", function()
		local run = Run.new({
			Waves = {},
			ShipStart = Vector2.new(0, -TRACK),
			ShipHeading = 0,
			Rocks = { { Type = RockTypes.Iron, Position = Vector2.new(0, -(TRACK + 4.5)) } },
			Tuning = { Ship = { OrbitEntryMin = 0, PrimedTime = 0.6 } },
		})
		local counts = count(run)
		play(run, RunInput.Idle, 0.3)
		expect(counts.RockFlared).toBe(1)
		local hang = rock(run).HangTime
		play(run, RunInput.Idle, 1) -- well past the primed time, still in the flare
		expect(rock(run).IsPrimed).toBe(true)
		expect(counts.RockPrimed).toBe(1) -- it never lost its priming
		expect(counts.RockFlared).toBe(1)
		expect(rock(run).HangTime < hang).toBe(true) -- the hang isn't started again
	end)

	it("frees a captured ship, so the slingshot is there to take", function()
		local run = underRock(16)
		play(run, RunInput.Idle, ShipConfig.CaptureTime + 0.2)
		expect(run:Snapshot().Ship.IsCaptured).toBe(true)
		expect(rock(run).IsFlared).toBe(false)
		-- the rock falls into the flare
		play(run, RunInput.Idle, 2)
		expect(rock(run).IsFlared).toBe(true)
		expect(run:Snapshot().Ship.IsCaptured).toBe(false)
	end)

	it("lets a slingshot break a flared rock within the hang time", function()
		local run = underRock(6)
		local counts = count(run)
		play(run, RunInput.Idle, 0.4)
		expect(rock(run).IsFlared).toBe(true)
		play(run, RunInput.steer(Vector2.new(0, -1)), 0.5)
		expect(counts.Slingshot).toBe(1)
		expect(counts.RockBroken).toBe(1)
	end)
end)
