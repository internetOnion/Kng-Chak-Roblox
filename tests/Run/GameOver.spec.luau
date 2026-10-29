--!strict
local RockTypes = require("@shared/Data/RockTypes")
local Run = require("@shared/Run/Run")
local RunEvents = require("@shared/Run/RunEvents")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local FRAME = 1 / 60

local function record(run: Run.Run): { { any } }
	local log = {}
	for _, name in RunEvents.Names do
		RunEvents.Get(run.Events, name):Connect(function(...)
			table.insert(log, { name, ... })
		end)
	end
	return log
end

local function play(run: Run.Run, seconds: number)
	for _ = 1, math.round(seconds / FRAME) do
		run:Step(Run.IdleInput, FRAME)
	end
end

local function count(log: { { any } }, name: string): number
	local n = 0
	for _, entry in log do
		if entry[1] == name then
			n += 1
		end
	end
	return n
end

-- A planet with room for exactly two plain rock hits, and a wave of four quick rocks.
local function doomed(): Run.Run
	return Run.new({
		Tuning = { Arena = { PlanetMaxHp = 2 * RockTypes.Rock.DamagePercent } },
		Waves = {
			{
				Wave = 1,
				Total = 4,
				Mix = { { Type = RockTypes.Rock, Weight = 1 } },
				InFlightCap = 4,
				FirstGroupDelay = 0,
				GroupInterval = 1.5,
				SpeedMult = 3,
			},
		},
	})
end

describe("Game over", function()
	it("ends the run when planet HP reaches 0, firing GameOver once with the wave, then RunFinished", function()
		local run = doomed()
		local log = record(run)
		play(run, 60)
		expect(count(log, "PlanetHit")).toBe(2)
		expect(count(log, "GameOver")).toBe(1)
		local over = log[#log - 1]
		expect(over[1]).toBe("GameOver")
		expect(over[2]).toBe(1)
		local last = log[#log]
		expect(last[1]).toBe("RunFinished")
		expect(last[2].Won).toBe(false)
		expect(last[2].Wave).toBe(1)
		local snapshot = run:Snapshot()
		expect(snapshot.PlanetHp).toBe(0)
		expect(snapshot.Phase).toBe("Over")
	end)

	it("freezes the run once it's over", function()
		local run = doomed()
		local over = false
		run.Events.GameOver:Connect(function()
			over = true
		end)
		while not over do
			run:Step(Run.IdleInput, FRAME)
		end
		local before = run:Snapshot()
		play(run, 5)
		local after = run:Snapshot()
		expect(#after.Rocks).toBe(#before.Rocks)
		for i, rock in after.Rocks do
			expect(rock.Position).toBe(before.Rocks[i].Position)
		end
		expect(after.Ship.Position).toBe(before.Ship.Position)
	end)

	it("starts a fresh run at full HP and wave 1 with no rocks", function()
		local old = doomed()
		play(old, 60)
		local fresh = Run.new({ Seed = 2 })
		local log = record(fresh)
		play(fresh, 0.1)
		local snapshot = fresh:Snapshot()
		expect(snapshot.PlanetHp).toBe(snapshot.PlanetMaxHp)
		expect(snapshot.Wave).toBe(1)
		expect(#snapshot.Rocks).toBe(0)
		expect(log[1][1]).toBe("WaveAnnounced")
		expect(log[2][1]).toBe("WaveStarted")
	end)
end)
