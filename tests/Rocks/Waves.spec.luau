--!strict
local ArenaConfig = require("@shared/Data/ArenaConfig")
local RockTypes = require("@shared/Data/RockTypes")
local Run = require("@shared/Run/Run")
local RunEvents = require("@shared/Run/RunEvents")
local TestKit = require("@testkit")
local WaveConfig = require("@shared/Data/WaveConfig")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local FRAME = 1 / 60

-- Records every event a run fires, in order, as { name, ...arguments }.
local function record(run: Run.Run): { { any } }
	local log = {}
	for _, name in RunEvents.Names do
		RunEvents.Get(run.Events, name):Connect(function(...)
			table.insert(log, { name, ... })
		end)
	end
	return log
end

local function names(log: { { any } }): { string }
	local out = {}
	for _, entry in log do
		table.insert(out, entry[1])
	end
	return out
end

-- A small, fast wave of plain rocks.
local function plan(total: number, cap: number): Run.WavePlan
	return {
		Wave = 1,
		Total = total,
		Mix = { { Type = RockTypes.Rock, Weight = 1 } },
		InFlightCap = cap,
		FirstGroupDelay = 0.5,
		GroupInterval = 0.5,
		SpeedMult = 1,
	}
end

-- Plays up to `seconds`, calling `each` with the snapshot after every frame. Stops early if `each` returns true.
local function playUntil(run: Run.Run, seconds: number, each: (Run.Snapshot) -> boolean?)
	for _ = 1, math.round(seconds / FRAME) do
		run:Step(Run.IdleInput, FRAME)
		if each(run:Snapshot()) then
			return
		end
	end
end

-- Arena positions where new rocks first appeared, by rock Id.
local function watchSpawns(run: Run.Run, seconds: number): { Vector2 }
	local seen, spawns = {}, {}
	playUntil(run, seconds, function(snapshot)
		for _, rock in snapshot.Rocks do
			if not seen[rock.Id] then
				seen[rock.Id] = true
				table.insert(spawns, rock.Position)
			end
		end
		return nil
	end)
	return spawns
end

describe("Waves", function()
	describe("with a fixed plan", function()
		it("never has more rocks in the air than the cap", function()
			local run = Run.new({ Waves = { plan(12, 3) } })
			local most = 0
			playUntil(run, 120, function(snapshot)
				most = math.max(most, #snapshot.Rocks)
				return nil
			end)
			expect(most).toBe(3)
		end)

		it("announces and starts the wave, and clears right after its last rock is gone", function()
			local run = Run.new({ Waves = { plan(5, 2) }, Offers = false })
			local log = record(run)
			local clearedWithRocksLeft = false
			playUntil(run, 120, function(snapshot)
				local last = log[#log]
				if last and last[1] == "WaveCleared" and #snapshot.Rocks > 0 then
					clearedWithRocksLeft = true
				end
				return nil
			end)
			expect(names(log)).toEqual({
				"WaveAnnounced",
				"WaveStarted",
				"PlanetHit",
				"PlanetHit",
				"PlanetHit",
				"PlanetHit",
				"PlanetHit",
				"WaveCleared",
			})
			expect(log[2][2]).toBe(1)
			expect(log[8][2]).toBe(1)
			expect(clearedWithRocksLeft).toBe(false)
		end)

		it("fires WaveCleared on the same step the last rock goes", function()
			local run = Run.new({ Waves = { plan(1, 1) }, Offers = false })
			local log = record(run)
			playUntil(run, 60, function()
				return #log > 2
			end)
			-- the step that fires PlanetHit for the only rock also clears the wave
			expect(names(log)).toEqual({ "WaveAnnounced", "WaveStarted", "PlanetHit", "WaveCleared" })
		end)

		it("plays nothing more after its last wave", function()
			local run = Run.new({ Waves = { plan(1, 1) }, Offers = false })
			local log = record(run)
			playUntil(run, 90, function()
				return nil
			end)
			expect(#log).toBe(4)
			expect(run:Snapshot().Phase).toBe("Breather")
		end)
	end)

	describe("from the wave data", function()
		it("plays wave 1 from start to clear, then starts wave 2 after the breather", function()
			local run = Run.new({ Seed = 7, Offers = false })
			local log = record(run)
			local clearedAt, startedAgainAt
			local t = 0
			playUntil(run, 300, function()
				t += FRAME
				local last = log[#log]
				if last[1] == "WaveCleared" and not clearedAt then
					clearedAt = t
				elseif last[1] == "WaveStarted" and last[2] == 2 then
					startedAgainAt = t
					return true
				end
				return nil
			end)
			local hits = 0
			for _, entry in log do
				if entry[1] == "PlanetHit" then
					hits += 1
					expect(entry[2].Type.Id).toBe("Rock") -- wave 1 is plain rocks only
				end
			end
			expect(hits).toBe(WaveConfig.WaveBase + WaveConfig.WavePerLevel)
			expect(clearedAt ~= nil).toBe(true)
			expect(startedAgainAt - clearedAt).toBeCloseTo(WaveConfig.Breather, FRAME * 1.5)
		end)

		it("keeps wave 1 to the data's in-flight cap", function()
			local run = Run.new({ Seed = 3 })
			local most = 0
			playUntil(run, 120, function(snapshot)
				most = math.max(most, #snapshot.Rocks)
				return snapshot.Wave > 1
			end)
			expect(most <= WaveConfig.InFlightStart).toBe(true)
		end)

		it("spawns rocks just outside the arena edge, from all sides", function()
			local quadrants = {}
			for seed = 1, 6 do
				for _, position in watchSpawns(Run.new({ Seed = seed }), 40) do
					local distance = position.Magnitude
					expect(distance > ArenaConfig.ArenaRadius).toBe(true)
					expect(distance <= ArenaConfig.ArenaRadius + WaveConfig.SpawnBeyondEdge + WaveConfig.SpawnDepth + 1).toBe(
						true
					)
					quadrants[(if position.X >= 0 then 1 else 0) + (if position.Y >= 0 then 2 else 0)] = true
				end
			end
			expect(quadrants[0] and quadrants[1] and quadrants[2] and quadrants[3]).toBe(true)
		end)

		it("spawns the same rocks for the same seed, and different ones for another", function()
			local a = watchSpawns(Run.new({ Seed = 42 }), 20)
			local b = watchSpawns(Run.new({ Seed = 42 }), 20)
			local c = watchSpawns(Run.new({ Seed = 43 }), 20)
			expect(a).toEqual(b)
			expect(a[1] == c[1]).toBe(false)
		end)

		it("sends a wave's new threat first", function()
			-- with comets arriving from wave 1, wave 1 introduces them
			local run = Run.new({ Seed = 5, Tuning = { Waves = { CometFrom = 1 } } })
			local first
			playUntil(run, 10, function(snapshot)
				first = snapshot.Rocks[1]
				return first ~= nil
			end)
			expect(first.Type.Id).toBe("Comet")
		end)
	end)
end)
