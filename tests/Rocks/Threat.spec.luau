--!strict
local ArenaConfig = require("@shared/Data/ArenaConfig")
local RockTypes = require("@shared/Data/RockTypes")
local Run = require("@shared/Run/Run")
local RunInput = require("@shared/Run/RunInput")
local TestKit = require("@testkit")
local Threat = require("@shared/Rocks/Threat")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local R = ArenaConfig.PlanetRadius

local function run(rocks: { Run.RockSetup }): Run.Run
	return Run.new({ Waves = {}, ShipStart = Vector2.new(0, -40), Rocks = rocks })
end

describe("Threat", function()
	it("names the rock that will hit soonest as the threat", function()
		local r = run({
			{ Type = RockTypes.Rock, Position = Vector2.new(30, 0) }, -- 20 up at 3/s: ~6.7 s
			{ Type = RockTypes.Comet, Position = Vector2.new(-40, 0) }, -- 30 up at 7.5/s: 4 s
			{ Type = RockTypes.Iron, Position = Vector2.new(0, 20) }, -- 10 up at 1.8/s: ~5.6 s
		})
		local snapshot = r:Snapshot()
		expect(snapshot.ThreatId).toBe(snapshot.Rocks[2].Id)
	end)

	it("names exactly one threat, and none with no rocks", function()
		expect(run({}):Snapshot().ThreatId).toBe(nil)
		local snapshot = run({
			{ Type = RockTypes.Rock, Position = Vector2.new(30, 0) },
			{ Type = RockTypes.Rock, Position = Vector2.new(-30, 0) },
		}):Snapshot()
		local id = snapshot.ThreatId
		expect(id == snapshot.Rocks[1].Id or id == snapshot.Rocks[2].Id).toBe(true)
	end)

	it("moves on to the next rock once the threat is gone", function()
		local r = run({
			{ Type = RockTypes.Rock, Position = Vector2.new(0, R + 2) },
			{ Type = RockTypes.Rock, Position = Vector2.new(30, 0) },
		})
		local second = r:Snapshot().Rocks[2].Id
		for _ = 1, 120 do
			r:Step(RunInput.Idle, 1 / 60)
		end
		expect(#r:Snapshot().Rocks).toBe(1)
		expect(r:Snapshot().ThreatId).toBe(second)
	end)

	it("lands a rock on the surface straight below it", function()
		local snapshot = run({ { Type = RockTypes.Rock, Position = Vector2.new(30, 40) } }):Snapshot()
		local landing = Threat.ImpactPoint(snapshot.Rocks[1], R)
		expect(landing.Magnitude).toBeCloseTo(R)
		expect(landing.X).toBeCloseTo(R * 0.6)
		expect(landing.Y).toBeCloseTo(R * 0.8)
	end)
end)
