--!strict
local GameEvents = require("@shared/GameEvents")
local RockTypes = require("@shared/Data/RockTypes")
local Run = require("@shared/Run/Run")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

-- A run whose one rock hits the planet within a second.
local function newRun(): Run.Run
	return Run.new({ Rocks = { { Type = RockTypes.Rock, Position = Vector2.new(0, 12) } } })
end

local function play(run: Run.Run)
	for _ = 1, 60 do
		run:Step(Run.IdleInput, 1 / 60)
	end
end

describe("GameEvents", function()
	it("passes on the events of the Run it follows", function()
		local hits: { { any } } = {}
		local connection = GameEvents.PlanetHit:Connect(function(rock, damagePercent)
			table.insert(hits, { rock.Type.Id, damagePercent })
		end)
		local run = newRun()
		GameEvents.Follow(run.Events)
		play(run)
		GameEvents.Follow(nil)
		connection:Disconnect()
		expect(hits).toEqual({ { "Rock" :: any, RockTypes.Rock.DamagePercent } })
	end)

	it("keeps its listeners when it switches to a new Run, and drops the old one", function()
		local count = 0
		local connection = GameEvents.PlanetHit:Connect(function()
			count += 1
		end)
		local old, new = newRun(), newRun()
		GameEvents.Follow(old.Events)
		GameEvents.Follow(new.Events)
		play(old)
		play(new)
		GameEvents.Follow(nil)
		connection:Disconnect()
		expect(count).toBe(1)
	end)

	it("passes on nothing once it follows no Run", function()
		local count = 0
		local connection = GameEvents.PlanetHit:Connect(function()
			count += 1
		end)
		local run = newRun()
		GameEvents.Follow(run.Events)
		GameEvents.Follow(nil)
		play(run)
		connection:Disconnect()
		expect(count).toBe(0)
	end)
end)
