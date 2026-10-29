--!strict
local ArenaConfig = require("@shared/Data/ArenaConfig")
local RockTypes = require("@shared/Data/RockTypes")
local Run = require("@shared/Run/Run")
local RunInput = require("@shared/Run/RunInput")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local FRAME = 1 / 60
local BAND_TOP = ArenaConfig.PlanetRadius + ArenaConfig.OrbitAlt + ArenaConfig.DragBandHeight

local function play(run: Run.Run, seconds: number)
	for _ = 1, math.round(seconds / FRAME) do
		run:Step(RunInput.Idle, FRAME)
	end
end

-- A rock falling from `height` (distance from the planet's centre) on the far side from the ship.
local function falling(height: number, tuning: any?): Run.Run
	return Run.new({
		Waves = {},
		ShipStart = Vector2.new(0, -40),
		Rocks = { { Type = RockTypes.Rock, Position = Vector2.new(0, height) } },
		Tuning = tuning,
	})
end

local function fallSpeed(run: Run.Run): number
	local rock = run:Snapshot().Rocks[1]
	return rock.Velocity:Dot(-rock.Position.Unit)
end

describe("Drag band", function()
	it("leaves a rock above the band at its fall speed", function()
		local run = falling(BAND_TOP + 10)
		play(run, 1)
		expect(run:Snapshot().Rocks[1].Position.Magnitude > BAND_TOP).toBe(true)
		expect(fallSpeed(run)).toBeCloseTo(RockTypes.Rock.FallSpeed, 1e-6)
	end)

	it("slows a rock in the band to the data's fraction of its fall speed", function()
		local run = falling(BAND_TOP - 0.2)
		play(run, 1.5)
		local rock = run:Snapshot().Rocks[1]
		expect(rock.Position.Magnitude < BAND_TOP).toBe(true)
		expect(fallSpeed(run)).toBeCloseTo(RockTypes.Rock.FallSpeed * ArenaConfig.DragBandMult, 0.05)
	end)

	it("takes the band's height and slowdown from the run's tuning", function()
		local run = falling(30, { Arena = { DragBandHeight = 20, DragBandMult = 0.25 } })
		play(run, 2)
		expect(fallSpeed(run)).toBeCloseTo(RockTypes.Rock.FallSpeed * 0.25, 0.05)
	end)
end)
