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
local SHIP = Vector2.new(0, -40) -- far from the planet, so rocks barely fall during a test
local RIGHT = Vector2.new(1, 0)
local BOOST_RIGHT = RunInput.steer(RIGHT, 1, true, false)

-- A run with the ship at SHIP facing right, these rocks (offsets from the ship) and no waves.
local function arena(rocks: { { any } }): Run.Run
	local setups = {}
	for _, rock in rocks do
		table.insert(setups, { Type = rock[1], Position = SHIP + rock[2] })
	end
	return Run.new({ Waves = {}, ShipStart = SHIP, ShipHeading = 0, Rocks = setups })
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

local function play(run: Run.Run, input: RunInput.RunInput, seconds: number)
	for _ = 1, math.round(seconds / FRAME) do
		run:Step(input, FRAME)
	end
end

describe("Ram break and bump", function()
	it("breaks a rock hit by the front of the ship with the spear out", function()
		local run = arena({ { RockTypes.Rock, Vector2.new(6, 0) } })
		local log = record(run)
		run:Step(BOOST_RIGHT, FRAME)
		play(run, RunInput.steer(RIGHT), 0.2)
		local broken = find(log, "RockBroken")
		expect(broken ~= nil).toBe(true)
		expect((broken :: any)[2].Type.Id).toBe("Rock")
		expect((broken :: any)[3]).toBe("Ram")
		expect(#run:Snapshot().Rocks).toBe(0)
		expect(find(log, "ShipBumped")).toBe(nil)
	end)

	it("adds the rock's score for a plain ram, and doesn't heal the planet", function()
		-- one rock hits the planet first, then the ship rams another
		local run = Run.new({
			Waves = {},
			ShipStart = SHIP,
			ShipHeading = 0,
			Rocks = {
				{ Type = RockTypes.Rock, Position = Vector2.new(0, 12) },
				{ Type = RockTypes.Rock, Position = SHIP + Vector2.new(6, 0) },
			},
		})
		run:Step(BOOST_RIGHT, FRAME)
		play(run, RunInput.steer(RIGHT), 0.2)
		expect(run:Snapshot().Score).toBe(RockTypes.Rock.Score)
		play(run, RunInput.Idle, 1)
		expect(run:Snapshot().PlanetHp).toBe(ArenaConfig.PlanetMaxHp - RockTypes.Rock.DamagePercent)
	end)

	it("bumps the ship away when a rock hits its back half, even boosting", function()
		local run = arena({ { RockTypes.Rock, Vector2.new(-2, 0) } })
		local log = record(run)
		run:Step(BOOST_RIGHT, FRAME)
		local bumped = find(log, "ShipBumped")
		expect(bumped ~= nil).toBe(true)
		local knock = (bumped :: any)[3] :: Vector2
		expect(knock.X > 0).toBe(true) -- away from the rock behind
		expect(knock.Magnitude).toBeCloseTo(ShipConfig.BumpKnock, 1e-3)
		expect(find(log, "RockBroken")).toBe(nil)
		local ship = run:Snapshot().Ship
		expect(ship.IsStunned).toBe(true)
		expect(ship.IsBoosting).toBe(false)
	end)

	it("bumps the ship off a rock it noses into without the spear", function()
		local run = arena({ { RockTypes.Rock, Vector2.new(2.5, 0) } })
		local log = record(run)
		run:Step(RunInput.steer(RIGHT), FRAME)
		local bumped = find(log, "ShipBumped")
		expect(bumped ~= nil).toBe(true)
		expect(((bumped :: any)[3] :: Vector2).X < 0).toBe(true)
		expect(find(log, "RockBroken")).toBe(nil)
		expect(#run:Snapshot().Rocks).toBe(1)
	end)

	it("stuns the ship for the data's stun time, with no control", function()
		local run = arena({ { RockTypes.Rock, Vector2.new(2.5, 0) } })
		run:Step(RunInput.steer(RIGHT), FRAME)
		play(run, RunInput.steer(RIGHT), ShipConfig.StunTime - 0.1)
		expect(run:Snapshot().Ship.IsStunned).toBe(true)
		expect(run:Snapshot().Ship.IsThrusting).toBe(false)
		play(run, RunInput.steer(RIGHT), 0.15)
		expect(run:Snapshot().Ship.IsStunned).toBe(false)
	end)
end)

describe("Flame push and prime", function()
	it("reaches farther with more throttle, and farthest while boosting", function()
		local function reach(input: RunInput.RunInput): number
			local run = arena({})
			if input.BoostPressed then
				run:Step(input, FRAME)
				play(run, RunInput.steer(RIGHT, 1, false, true), 0.6)
			else
				play(run, input, 1)
			end
			return run:Snapshot().Ship.FlameReach
		end
		local low, full = ShipConfig.PushRangeMin, ShipConfig.PushRange
		expect(reach(RunInput.steer(RIGHT, 0.5))).toBeCloseTo(low + (full - low) * 0.5, 0.05)
		expect(reach(RunInput.steer(RIGHT, 1))).toBeCloseTo(full, 0.05)
		expect(reach(BOOST_RIGHT)).toBeCloseTo(ShipConfig.PushBoostRange, 0.05)
		expect(reach(RunInput.Idle)).toBe(0)
	end)

	it("pushes and primes a rock behind the ship, away from the ship and the planet", function()
		local run = arena({ { RockTypes.Rock, Vector2.new(-4, 0) } })
		local log = record(run)
		play(run, RunInput.steer(RIGHT), 0.2)
		expect(find(log, "RockPrimed") ~= nil).toBe(true)
		local rock = run:Snapshot().Rocks[1]
		expect(rock.IsPrimed).toBe(true)
		expect(rock.Velocity.X < 0).toBe(true) -- away from the ship
		expect(rock.Velocity.Y < 0).toBe(true) -- away from the planet (the ship is below it)
	end)

	it("fires RockPrimed only when the rock becomes primed, not on every push", function()
		local run = arena({ { RockTypes.Rock, Vector2.new(-4, 0) } })
		local log = record(run)
		play(run, RunInput.steer(RIGHT), 1)
		local primed = 0
		for _, entry in log do
			if entry[1] == "RockPrimed" then
				primed += 1
			end
		end
		expect(primed).toBe(1)
	end)

	it("leaves a rock out of reach alone", function()
		local run = arena({ { RockTypes.Rock, Vector2.new(-9, 0) } })
		play(run, RunInput.steer(RIGHT, 0.2), 0.5)
		expect(run:Snapshot().Rocks[1].IsPrimed).toBe(false)
	end)

	it("cools a primed rock down after the data's primed time", function()
		local run = arena({ { RockTypes.Rock, Vector2.new(-4, 0) } })
		play(run, RunInput.steer(RIGHT), 0.1)
		expect(run:Snapshot().Rocks[1].IsPrimed).toBe(true)
		play(run, RunInput.Idle, ShipConfig.PrimedTime - 0.6)
		expect(run:Snapshot().Rocks[1].IsPrimed).toBe(true)
		play(run, RunInput.Idle, 0.7)
		expect(run:Snapshot().Rocks[1].IsPrimed).toBe(false)
	end)

	it("moves iron much less than a plain rock under the same push", function()
		local function kick(rockType: RockTypes.RockType): number
			local run = arena({ { rockType, Vector2.new(-4, 0) } })
			local before = run:Snapshot().Rocks[1].Velocity
			play(run, RunInput.steer(RIGHT), 0.1)
			return (run:Snapshot().Rocks[1].Velocity - before).Magnitude
		end
		local plain, iron = kick(RockTypes.Rock), kick(RockTypes.Iron)
		expect(iron < plain * 0.5).toBe(true)
	end)
end)
