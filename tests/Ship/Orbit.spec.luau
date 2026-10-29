--!strict
local ArenaConfig = require("@shared/Data/ArenaConfig")
local Run = require("@shared/Run/Run")
local RunEvents = require("@shared/Run/RunEvents")
local RunInput = require("@shared/Run/RunInput")
local ShipConfig = require("@shared/Data/ShipConfig")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local FRAME = 1 / 60
local TRACK = ArenaConfig.PlanetRadius + ArenaConfig.OrbitAlt
local BAND_TOP = ArenaConfig.PlanetRadius + ArenaConfig.OrbitBandTop
local RIGHT = Vector2.new(1, 0)
local DOWN = Vector2.new(0, -1)

local function play(run: Run.Run, input: RunInput.RunInput, seconds: number)
	for _ = 1, math.round(seconds / FRAME) do
		run:Step(input, FRAME)
	end
end

local function ship(run: Run.Run)
	return run:Snapshot().Ship
end

local function record(run: Run.Run): { string }
	local log = {}
	for _, name in RunEvents.Names do
		RunEvents.Get(run.Events, name):Connect(function()
			table.insert(log, name)
		end)
	end
	return log
end

-- A run with no waves, the ship just inside the band below the planet, nose to the right.
local function inBand(tuning: any?): Run.Run
	return Run.new({ Waves = {}, ShipStart = Vector2.new(0, -(BAND_TOP - 0.5)), ShipHeading = 0, Tuning = tuning })
end

describe("Orbit lock and refuel", function()
	it("locks onto the orbit track when the ship flies into the band", function()
		local run = Run.new({ Waves = {}, ShipStart = Vector2.new(0, -24), ShipHeading = math.pi / 2 })
		local log = record(run)
		play(run, RunInput.steer(Vector2.new(0.3, 1)), 1.5)
		expect(table.find(log, "OrbitLocked") ~= nil).toBe(true)
		expect(ship(run).IsInOrbit).toBe(true)
		play(run, RunInput.Idle, 2)
		expect(ship(run).Position.Magnitude).toBeCloseTo(TRACK, 0.05)
	end)

	it("doesn't lock above the band", function()
		local run = Run.new({ Waves = {}, ShipStart = Vector2.new(0, -(BAND_TOP + 1)), ShipHeading = 0 })
		run:Step(RunInput.Idle, FRAME)
		expect(ship(run).IsInOrbit).toBe(false)
	end)

	it("circles the planet and never touches it, even steering straight at it", function()
		local run = inBand()
		local closest, travelled = math.huge, 0
		local last = ship(run).Position
		for _ = 1, 300 do
			local s = ship(run)
			run:Step(RunInput.steer(-s.Position), FRAME)
			local now = ship(run).Position
			closest = math.min(closest, now.Magnitude)
			travelled += (now - last).Magnitude
			last = now
		end
		expect(ship(run).IsInOrbit).toBe(true)
		expect(closest > ArenaConfig.PlanetRadius + 1).toBe(true)
		expect(travelled > 30).toBe(true) -- it kept going round
	end)

	it("speeds up steering along the orbit and slows down steering against it", function()
		local along = inBand()
		along:Step(RunInput.Idle, FRAME)
		local start = ship(along).Velocity.Magnitude
		play(along, RunInput.steer(RIGHT), 0.3) -- at the bottom, anticlockwise is to the right
		expect(ship(along).Velocity.Magnitude > start + 3).toBe(true)

		local against = inBand()
		against:Step(RunInput.Idle, FRAME)
		play(against, RunInput.steer(-RIGHT), 0.3)
		expect(ship(against).Velocity.Magnitude < start - 3).toBe(true)
	end)

	it("caps orbit speed at the data's orbit max", function()
		local run = inBand()
		for _ = 1, 600 do
			local s = ship(run)
			run:Step(RunInput.steer(Vector2.new(-s.Position.Y, s.Position.X)), FRAME) -- along, anticlockwise
		end
		expect(ship(run).IsInOrbit).toBe(true)
		expect(ship(run).Velocity.Magnitude).toBeCloseTo(ShipConfig.OrbitMaxSpeed, 1e-3)
	end)

	it("refuels at the orbit multiplier while locked", function()
		-- spend fuel on a boost out in the arena, then fly into the band
		local run = Run.new({ Waves = {}, ShipStart = Vector2.new(0, -20), ShipHeading = math.pi / 2 })
		run:Step(RunInput.steer(Vector2.new(0, 1), 1, true, false), FRAME)
		play(run, RunInput.Idle, 0.3)
		expect(ship(run).IsInOrbit).toBe(true)
		local before = ship(run).Fuel
		expect(before < ShipConfig.FuelMax - 5).toBe(true)
		play(run, RunInput.Idle, 0.5)
		expect(ship(run).Fuel - before).toBeCloseTo(ShipConfig.FuelRegen * ShipConfig.OrbitRegenMult * 0.5, 1e-6)
	end)

	it("leaves the orbit when you aim outward, and fires orbit left", function()
		local run = inBand()
		local log = record(run)
		play(run, RunInput.Idle, 0.5)
		play(run, RunInput.steer(DOWN), 0.6) -- straight out from the bottom of the planet
		expect(table.find(log, "OrbitLeft") ~= nil).toBe(true)
		expect(ship(run).IsInOrbit).toBe(false)
		expect(ship(run).Position.Magnitude > BAND_TOP).toBe(true)
	end)

	it("doesn't leave when you aim only a little outward", function()
		local run = inBand()
		play(run, RunInput.Idle, 0.5)
		local s = ship(run)
		local outward = s.Position.Unit
		local along = Vector2.new(-outward.Y, outward.X)
		play(run, RunInput.steer(along + outward * 0.2), 0.05)
		expect(ship(run).IsInOrbit).toBe(true)
	end)

	it("doesn't lock again straight after leaving", function()
		local run = inBand()
		play(run, RunInput.Idle, 0.5)
		local s = ship(run)
		run:Step(RunInput.steer(s.Position.Unit), FRAME)
		expect(ship(run).IsInOrbit).toBe(false)
		play(run, RunInput.Idle, ShipConfig.OrbitRelockTime * 0.5)
		expect(ship(run).IsInOrbit).toBe(false)
	end)
end)
