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
local BAND_TOP = ArenaConfig.PlanetRadius + ArenaConfig.OrbitBandTop
local DOWN = Vector2.new(0, -1)

local function play(run: Run.Run, input: RunInput.RunInput, seconds: number)
	for _ = 1, math.round(seconds / FRAME) do
		run:Step(input, FRAME)
	end
end

local function ship(run: Run.Run)
	return run:Snapshot().Ship
end

local function record(run: Run.Run): { { any } }
	local log = {}
	for _, name in RunEvents.Names do
		RunEvents.Get(run.Events, name):Connect(function(...)
			table.insert(log, { name, ... })
		end)
	end
	return log
end

local function find(log: { { any } }, name: string): { any }?
	for _, entry in log do
		if entry[1] == name then
			return entry
		end
	end
	return nil
end

-- A run with no waves and the ship locking into orbit at the bottom of the planet, with these rocks.
local function orbiting(rocks: { Run.RockSetup }?): Run.Run
	local run = Run.new({
		Waves = {},
		ShipStart = Vector2.new(0, -(BAND_TOP - 0.5)),
		ShipHeading = 0,
		Rocks = rocks,
	})
	run:Step(RunInput.Idle, FRAME)
	assert(ship(run).IsInOrbit, "the ship locks on")
	return run
end

-- Steers straight out from the planet, wherever the ship is.
local function out(run: Run.Run, boost: boolean?): RunInput.RunInput
	return RunInput.steer(ship(run).Position.Unit, 1, boost, boost)
end

describe("Slingshot dive", function()
	it("launches a fast dive with the spear out when you flick outward from orbit", function()
		local run = orbiting()
		local log = record(run)
		play(run, RunInput.Idle, 0.3)
		run:Step(out(run), FRAME)
		local s = ship(run)
		expect(find(log, "Slingshot") ~= nil).toBe(true)
		expect(s.IsInOrbit).toBe(false)
		expect(s.IsSlingshotting).toBe(true)
		expect(s.IsSpearOut).toBe(true)
		expect(s.Velocity.Magnitude).toBeCloseTo(ShipConfig.SlingshotSpeed, 1e-6)
	end)

	it("costs no fuel within the capture time", function()
		local run = orbiting()
		play(run, RunInput.Idle, ShipConfig.CaptureTime - 0.5)
		local before = ship(run).Fuel
		run:Step(out(run), FRAME)
		expect(ship(run).IsSlingshotting).toBe(true)
		expect(ship(run).Fuel >= before).toBe(true)
	end)

	it("captures the ship after the capture time, so aiming out no longer leaves", function()
		local run = orbiting()
		local log = record(run)
		play(run, RunInput.Idle, ShipConfig.CaptureTime + 0.1)
		expect(find(log, "OrbitCaptured") ~= nil).toBe(true)
		expect(ship(run).IsCaptured).toBe(true)
		play(run, out(run), 0.3)
		expect(ship(run).IsInOrbit).toBe(true)
		expect(find(log, "Slingshot")).toBe(nil)
	end)

	it("lets a captured ship out with a boost, which costs a boost's fuel and isn't a slingshot", function()
		local run = orbiting()
		local log = record(run)
		play(run, RunInput.Idle, ShipConfig.CaptureTime + 0.1)
		local before = ship(run).Fuel
		run:Step(out(run, true), FRAME)
		local s = ship(run)
		expect(s.IsInOrbit).toBe(false)
		expect(s.IsBoosting).toBe(true)
		expect(s.IsSlingshotting).toBe(false)
		expect(s.Fuel).toBeCloseTo(before - ShipConfig.BoostCost, 1)
		expect(find(log, "Slingshot")).toBe(nil)
	end)

	it("locks onto the rock ahead and breaks the rock it reaches", function()
		local run = orbiting({ { Type = RockTypes.Rock, Position = Vector2.new(0, -26) } })
		local log = record(run)
		play(run, RunInput.Idle, 0.2)
		run:Step(out(run), FRAME)
		local slingshot = find(log, "Slingshot")
		expect(slingshot ~= nil).toBe(true)
		expect((slingshot :: any)[2] ~= nil).toBe(true)
		expect((slingshot :: any)[2].Type.Id).toBe("Rock")
		expect(ship(run).LockId).toBe(run:Snapshot().Rocks[1].Id)
		play(run, out(run), ShipConfig.SlingshotDuration)
		local broken = find(log, "RockBroken")
		expect(broken ~= nil).toBe(true)
		expect((broken :: any)[3]).toBe("Dive")
		expect(#run:Snapshot().Rocks).toBe(0)
	end)

	it("locks onto a rock off to the side of the launch, inside the lock cone", function()
		-- the ship launches straight down; the rock sits about 25° off to the side
		local angle = math.rad(-90 + 11)
		local rockAt = Vector2.new(math.cos(angle), math.sin(angle)) * 26
		local run = orbiting({ { Type = RockTypes.Rock, Position = rockAt } })
		local log = record(run)
		run:Step(RunInput.steer(DOWN), FRAME)
		play(run, RunInput.Idle, ShipConfig.SlingshotDuration)
		expect(find(log, "RockBroken") ~= nil).toBe(true)
	end)

	it("is short with no rock ahead", function()
		local run = orbiting()
		local log = record(run)
		run:Step(out(run), FRAME)
		local slingshot = find(log, "Slingshot")
		expect(slingshot ~= nil).toBe(true)
		expect((slingshot :: any)[2]).toBe(nil)
		play(run, RunInput.Idle, ShipConfig.SlingshotNoTarget - 0.05)
		expect(ship(run).IsSlingshotting).toBe(true)
		play(run, RunInput.Idle, 0.1)
		expect(ship(run).IsSlingshotting).toBe(false)
		expect(ship(run).IsSpearOut).toBe(false)
	end)

	it("needs the slingshot cooldown before leaving gives another", function()
		local run = orbiting()
		local log = record(run)
		run:Step(out(run), FRAME)
		play(run, RunInput.steer(-ship(run).Position.Unit), 1.2) -- dive back into the band
		expect(ship(run).IsInOrbit).toBe(true)
		local slingshots = 0
		for _, entry in log do
			if entry[1] == "Slingshot" then
				slingshots += 1
			end
		end
		run:Step(out(run), FRAME)
		expect(ship(run).IsInOrbit).toBe(false)
		expect(ship(run).IsSlingshotting).toBe(false)
		expect(slingshots).toBe(1)
	end)
end)
