--!strict
local Pilot = require("../Pilot")
local Replay = require("@shared/Run/Replay")
local RockTypes = require("@shared/Data/RockTypes")
local Run = require("@shared/Run/Run")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local FRAME = 1 / 30

-- Plays `frames` frames with the pilot, picking the first card of every offer.
local function fly(run: Run.Run, frames: number)
	for _ = 1, frames do
		if run:Snapshot().Phase == "UpgradePick" then
			run:PickUpgrade(1)
		end
		run:Step(Pilot.Input(run:Snapshot(), run:GetTuning()), FRAME)
	end
end

describe("Pause", function()
	it("freezes the run: nothing moves and no time passes", function()
		local run = Run.new({ Seed = 5 })
		fly(run, 300)
		run:SetPaused(true)
		local before = run:Snapshot()
		expect(before.IsPaused).toBe(true)
		fly(run, 300)
		local after = run:Snapshot()
		expect(after.Time).toBe(before.Time)
		expect(after.Ship.Position).toBe(before.Ship.Position)
		for i, rock in after.Rocks do
			expect(rock.Position).toBe(before.Rocks[i].Position)
		end
	end)

	it("resumes exactly where it was: a paused run plays out the same as one never paused", function()
		local function playOut(pauseFor: number): ({ string }, string)
			local run = Run.new({ Seed = 8 })
			local log = Replay.Log(run)
			fly(run, 400)
			run:SetPaused(true)
			fly(run, pauseFor)
			run:SetPaused(false)
			fly(run, 800)
			return log, Replay.Summary(run)
		end
		local log, final = playOut(0)
		local pausedLog, pausedFinal = playOut(250)
		expect(pausedLog).toEqual(log)
		expect(pausedFinal).toBe(final)
	end)
end)

describe("Run summary", function()
	it("sums up a lost call: the wave reached, score, best combo and PERFECTs", function()
		-- the pilot breaks rocks for a score, but a planet this frail falls anyway
		local run = Run.new({ Seed = 3, Tuning = { Arena = { PlanetMaxHp = 8, PlanetMaxShield = 0 } } })
		local finished = nil
		run.Events.RunFinished:Connect(function(summary)
			finished = summary
		end)
		local frames = 0
		while not finished and frames < 30 * 900 do
			fly(run, 1)
			frames += 1
		end
		local summary = finished :: Run.Summary
		expect(summary.Won).toBe(false)
		expect(summary.Mode).toBe("Call")
		local snapshot = run:Snapshot()
		expect(snapshot.Phase).toBe("Over")
		expect(summary.Wave).toBe(snapshot.Wave)
		expect(summary.Score).toBe(snapshot.Score)
		expect(summary.BestCombo).toBe(snapshot.BestCombo)
		expect(summary.Time).toBeCloseTo(snapshot.Time)
		expect(run:Summary()).toEqual(summary)
	end)

	it("counts every PERFECT", function()
		local run = Run.new({
			Waves = {},
			ShipStart = Vector2.new(0, -12.6),
			ShipHeading = 0,
			Rocks = { { Type = RockTypes.Rock, Position = Vector2.new(0, -18.6) } },
			Tuning = { Ship = { OrbitEntryMin = 0 } },
		})
		for _ = 1, 25 do
			run:Step(Run.IdleInput, 1 / 60)
		end
		for _ = 1, 30 do
			run:Step({
				Move = Vector2.new(0, -1),
				MoveStrength = 1,
				BoostPressed = false,
				BoostHeld = false,
				Brake = false,
			}, 1 / 60)
		end
		expect(run:Summary().Perfects).toBe(1)
	end)
end)
