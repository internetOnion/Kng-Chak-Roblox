--!strict
local ArenaConfig = require("@shared/Data/ArenaConfig")
local Run = require("@shared/Run/Run")
local RunInput = require("@shared/Run/RunInput")
local ShipConfig = require("@shared/Data/ShipConfig")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local FRAME = 1 / 60
local RIGHT = Vector2.new(1, 0)

local function play(run: Run.Run, input: RunInput.RunInput, seconds: number)
	for _ = 1, math.round(seconds / FRAME) do
		run:Step(input, FRAME)
	end
end

local function ship(run: Run.Run)
	return run:Snapshot().Ship
end

local function brake(): RunInput.RunInput
	local input = table.clone(RunInput.Idle)
	input.Brake = true
	return input
end

local BOOST = RunInput.steer(RIGHT, 1, true, false)
local HOLD_BOOST = RunInput.steer(RIGHT, 1, false, true)

describe("Flight", function()
	it("turns the nose toward where you steer, then thrusts that way up to max speed", function()
		local run = Run.new({ ShipStart = Vector2.new(-45, -20) })
		play(run, RunInput.steer(RIGHT), 3)
		local s = ship(run)
		expect(s.Facing.X).toBeCloseTo(1, 1e-3)
		expect(s.Velocity.Magnitude).toBeCloseTo(ShipConfig.MaxSpeed, 0.1)
		expect(s.Position.X > 0).toBe(true)
	end)

	it("doesn't thrust until the nose is inside the thrust cone", function()
		-- the nose starts pointing down; steering straight up needs a half turn first
		local run = Run.new({ ShipStart = Vector2.new(0, -40) })
		play(run, RunInput.steer(Vector2.new(0, 1)), 0.2)
		expect(ship(run).Velocity.Magnitude).toBeCloseTo(0, 1e-6)
		expect(ship(run).IsThrusting).toBe(false)
		play(run, RunInput.steer(Vector2.new(0, 1)), 1)
		expect(ship(run).Velocity.Y > 5).toBe(true)
	end)

	it("sets speed from how hard you steer", function()
		local run = Run.new({ ShipStart = Vector2.new(0, -40) })
		play(run, RunInput.steer(RIGHT, 0.5), 3)
		expect(ship(run).Velocity.Magnitude).toBeCloseTo(ShipConfig.MaxSpeed * 0.5, 0.2)
	end)

	it("brakes to a stop", function()
		local run = Run.new({ ShipStart = Vector2.new(0, -40) })
		play(run, RunInput.steer(RIGHT), 2)
		play(run, brake(), 3)
		expect(ship(run).Velocity.Magnitude < 0.1).toBe(true)
	end)

	it("slides along the arena edge and never leaves it", function()
		-- flying right from near the bottom edge runs into the edge, which bends the path round
		local run = Run.new({ ShipStart = Vector2.new(0, -60), ShipHeading = 0 })
		local farthest = 0
		for _ = 1, 300 do
			run:Step(RunInput.steer(RIGHT), FRAME)
			farthest = math.max(farthest, ship(run).Position.Magnitude)
		end
		expect(farthest <= ArenaConfig.ArenaRadius + 1e-3).toBe(true)
		expect(ship(run).Position.Magnitude).toBeCloseTo(ArenaConfig.ArenaRadius, 1e-3)
		expect(ship(run).Position.X > 50).toBe(true) -- slid round the edge instead of stopping where it hit
	end)

	it("can't fly into the planet", function()
		local run = Run.new({ ShipStart = Vector2.new(0, -24), ShipHeading = math.pi / 2 })
		local closest = math.huge
		for _ = 1, 180 do
			run:Step(RunInput.steer(Vector2.new(0, 1)), FRAME)
			closest = math.min(closest, ship(run).Position.Magnitude)
		end
		expect(closest >= ArenaConfig.PlanetRadius + ArenaConfig.OrbitAlt - 1e-3).toBe(true)
	end)

	it("flies with the run's tuning, so a data change changes the feel", function()
		local run = Run.new({ ShipStart = Vector2.new(0, -40), Tuning = { Ship = { MaxSpeed = 10 } } })
		play(run, RunInput.steer(RIGHT), 3)
		expect(ship(run).Velocity.Magnitude).toBeCloseTo(10, 0.1)
	end)

	it("refuses a tuning value the data doesn't have", function()
		expect(function()
			Run.new({ Tuning = { Ship = { MaxSpeeed = 10 } } })
		end).toThrow()
	end)
end)

describe("Boost and fuel", function()
	it("starts with a full tank", function()
		expect(ship(Run.new()).Fuel).toBe(ShipConfig.FuelMax)
	end)

	it("costs one burst of fuel, puts the spear out and flies at boost speed", function()
		local run = Run.new({ ShipStart = Vector2.new(0, -40) })
		run:Step(BOOST, FRAME)
		local s = ship(run)
		expect(s.Fuel).toBeCloseTo(ShipConfig.FuelMax - ShipConfig.BoostCost)
		expect(s.IsBoosting).toBe(true)
		expect(s.IsSpearOut).toBe(true)
		expect(s.Velocity.Magnitude).toBeCloseTo(ShipConfig.BoostSpeed)
		expect(s.Facing.X).toBeCloseTo(1) -- a boost snaps the nose round
	end)

	it("ends after one burst and puts the soft nose back", function()
		local run = Run.new({ ShipStart = Vector2.new(0, -40) })
		run:Step(BOOST, FRAME)
		play(run, RunInput.steer(RIGHT), ShipConfig.BoostDuration + 0.05)
		expect(ship(run).IsBoosting).toBe(false)
		expect(ship(run).IsSpearOut).toBe(false)
	end)

	it("does nothing with too little fuel", function()
		local run = Run.new({ ShipStart = Vector2.new(0, -40) })
		local presses = math.floor(ShipConfig.FuelMax / ShipConfig.BoostCost)
		for _ = 1, presses do
			run:Step(BOOST, FRAME)
		end
		local left = ship(run).Fuel
		expect(left < ShipConfig.BoostCost).toBe(true)
		play(run, RunInput.steer(RIGHT), ShipConfig.BoostDuration + 0.05)
		run:Step(BOOST, FRAME)
		expect(ship(run).IsBoosting).toBe(false)
		expect(ship(run).Fuel > left).toBe(true) -- only regen moved it
	end)

	it("keeps boosting while held, draining fuel", function()
		local run = Run.new({ ShipStart = Vector2.new(0, -40) })
		run:Step(BOOST, FRAME)
		play(run, HOLD_BOOST, 1)
		local s = ship(run)
		expect(s.IsBoosting).toBe(true)
		expect(s.Fuel < ShipConfig.FuelMax - ShipConfig.BoostCost - 20).toBe(true)
	end)

	it("refills fuel at the data's rate when not boosting", function()
		local run = Run.new({ ShipStart = Vector2.new(0, -40) })
		run:Step(BOOST, FRAME)
		play(run, RunInput.Idle, 1)
		local before = ship(run).Fuel
		play(run, RunInput.Idle, 2)
		expect(ship(run).Fuel - before).toBeCloseTo(ShipConfig.FuelRegen * 2, 1e-6)
	end)

	it("never lets fuel pass the tank's size", function()
		local run = Run.new()
		play(run, RunInput.Idle, 2)
		expect(ship(run).Fuel).toBe(ShipConfig.FuelMax)
	end)

	it("fires Boosted once per boost burst, and not when there's too little fuel", function()
		local run = Run.new({ ShipStart = Vector2.new(0, -40), Tuning = { Ship = { FuelRegen = 0 } } })
		local boosts = 0
		run.Events.Boosted:Connect(function()
			boosts += 1
		end)
		for _ = 1, 5 do
			run:Step(BOOST, FRAME)
			play(run, RunInput.steer(RIGHT), ShipConfig.BoostDuration + 0.05)
		end
		expect(boosts).toBe(math.floor(ShipConfig.FuelMax / ShipConfig.BoostCost))
	end)

	it("keeps a boost pressed on a frame too short for a sub-step", function()
		local run = Run.new({ ShipStart = Vector2.new(0, -40) })
		run:Step(BOOST, 0.001)
		run:Step(RunInput.steer(RIGHT), FRAME)
		expect(ship(run).IsBoosting).toBe(true)
	end)
end)
