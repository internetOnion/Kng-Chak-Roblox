--!strict
local Run = require("@shared/Run/Run")
local RunInput = require("@shared/Run/RunInput")
local ShipConfig = require("@shared/Data/ShipConfig")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local function play(run: Run.Run, seconds: number)
	for _ = 1, math.round(seconds * 60) do
		run:Step(RunInput.steer(Vector2.new(1, 0)), 1 / 60)
	end
end

describe("Tuning", function()
	it("changes a running Run's feel straight away, without touching the data", function()
		local run = Run.new({ Waves = {}, ShipStart = Vector2.new(-50, -20), ShipHeading = 0 })
		play(run, 2)
		expect(run:Snapshot().Ship.Velocity.Magnitude).toBeCloseTo(ShipConfig.MaxSpeed, 0.1)
		run:SetTuning({ Ship = { MaxSpeed = 10 } })
		play(run, 1.5)
		expect(run:Snapshot().Ship.Velocity.Magnitude).toBeCloseTo(10, 0.1)
		expect(run:GetTuning().Ship.MaxSpeed).toBe(10)
		expect(ShipConfig.MaxSpeed).toBe(22)
	end)

	it("goes back to the data's values when the overrides are cleared", function()
		local run = Run.new({ Waves = {}, Tuning = { Ship = { MaxSpeed = 10 } } })
		run:SetTuning(nil)
		expect(run:GetTuning().Ship.MaxSpeed).toBe(ShipConfig.MaxSpeed)
	end)

	it("can't be written to", function()
		local tuning = Run.new({ Waves = {} }):GetTuning()
		expect(function()
			(tuning.Ship :: any).MaxSpeed = 1
		end).toThrow()
		expect(function()
			(ShipConfig :: any).MaxSpeed = 1
		end).toThrow()
	end)
end)
