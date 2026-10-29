--!strict
local ArenaConfig = require("@shared/Data/ArenaConfig")
local InfernoConfig = require("@shared/Data/InfernoConfig")
local Pilot = require("../Pilot")
local Run = require("@shared/Run/Run")
local RunEvents = require("@shared/Run/RunEvents")
local RunInput = require("@shared/Run/RunInput")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local FRAME = 1 / 60
local DOWN = -math.pi / 2 -- the Inferno comes in from straight below the planet
local LEFT = Vector2.new(-1, 0)
local RIGHT = Vector2.new(1, 0)
local TRACK = ArenaConfig.PlanetRadius + ArenaConfig.OrbitAlt
local CONTACT = ArenaConfig.PlanetRadius + InfernoConfig.BodyRadius

local function play(run: Run.Run, input: RunInput.RunInput, seconds: number)
	for _ = 1, math.round(seconds / FRAME) do
		run:Step(input, FRAME)
	end
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

local function count(log: { { any } }, name: string): number
	local n = 0
	for _, entry in log do
		n += if entry[1] == name then 1 else 0
	end
	return n
end

local function plates(snapshot: Run.Snapshot): { any }
	local out = {}
	for _, rock in snapshot.Rocks do
		if rock.Type.Id == "Plate" then
			table.insert(out, rock)
		end
	end
	return out
end

-- The Inferno straight away, coming up from below, with the ship at `ship` (default: start) facing `heading`.
local function fight(options: { [string]: any }?): Run.Run
	local setup: { [string]: any } = { Waves = {}, Boss = true, BossAngle = DOWN }
	for key, value in (options or {}) :: { [string]: any } do
		setup[key] = value
	end
	local run = Run.new(setup :: any)
	while not run:Snapshot().Boss do
		run:Step(Run.IdleInput, FRAME)
	end
	run:Step(Run.IdleInput, FRAME) -- its first step sets its phase from its plates
	return run
end

-- The first plate's spot (the one east of the body) when the Inferno has just entered from below.
local PLATE = Vector2.new(InfernoConfig.PlateRing, -InfernoConfig.EnterDistance)

-- Primes the east plate with the flame and rams it. The ship starts east of it, facing east.
local function pushThenRamPlate(run: Run.Run)
	play(run, RunInput.steer(RIGHT, 0.5), 0.2)
	assert(plates(run:Snapshot())[1].IsPrimed, "the flame primes the plate")
	run:Step(RunInput.steer(LEFT, 1, true, false), FRAME)
	play(run, RunInput.steer(LEFT), 0.3)
end

describe("Inferno phase 1: armour", function()
	it("arrives after the last wave at the arena edge with 6 plates", function()
		local run = fight()
		local snapshot = run:Snapshot()
		local boss = snapshot.Boss :: Run.BossSnapshot
		expect(snapshot.Phase).toBe("Boss")
		expect(boss.Phase).toBe(1)
		expect(boss.Plates).toBe(InfernoConfig.Plates)
		expect(boss.PlatesLeft).toBe(InfernoConfig.Plates)
		expect(#plates(snapshot)).toBe(InfernoConfig.Plates)
		expect(boss.Position.Magnitude).toBeCloseTo(InfernoConfig.EnterDistance, 0.1)
		expect(boss.Position.Magnitude < ArenaConfig.ArenaRadius).toBe(true)
	end)

	it("clangs a ram off a plate that isn't primed", function()
		local run = fight({ ShipStart = PLATE + Vector2.new(6, 0), ShipHeading = math.pi })
		local log = record(run)
		run:Step(RunInput.steer(LEFT, 1, true, false), FRAME)
		play(run, RunInput.steer(LEFT), 0.2)
		expect(count(log, "RockClanged")).toBe(1)
		expect(count(log, "RockBroken")).toBe(0)
		expect((run:Snapshot().Boss :: Run.BossSnapshot).PlatesLeft).toBe(InfernoConfig.Plates)
	end)

	it("breaks a plate that was primed first", function()
		local run = fight({ ShipStart = PLATE + Vector2.new(4.5, 0), ShipHeading = 0 })
		local log = record(run)
		pushThenRamPlate(run)
		local broken = nil
		for _, entry in log do
			if entry[1] == "RockBroken" then
				broken = entry
				break
			end
		end
		expect(broken[2].Type.Id).toBe("Plate")
		expect(broken[3]).toBe("PushBreak")
		expect((run:Snapshot().Boss :: Run.BossSnapshot).PlatesLeft).toBe(InfernoConfig.Plates - 1)
	end)

	it("reaches the planet in the phase's time if ignored, dealing 40% and bouncing back", function()
		-- the ship waits off to the side, out of its way
		local run = fight({ ShipStart = Vector2.new(50, 30), Tuning = { Arena = { PlanetMaxHp = 1000 } } })
		local log = record(run)
		local t = FRAME
		while count(log, "BossHit") == 0 and t < 200 do
			run:Step(Run.IdleInput, FRAME)
			t += FRAME
		end
		expect(t).toBeCloseTo(InfernoConfig.Phase1Time, 0.1)
		local hit = nil
		for _, entry in log do
			if entry[1] == "BossHit" then
				hit = entry
			end
		end
		expect(hit[2]).toBe(InfernoConfig.ContactDamage)
		local snapshot = run:Snapshot()
		expect(snapshot.PlanetHp).toBe(1000 - InfernoConfig.ContactDamage)
		expect((snapshot.Boss :: Run.BossSnapshot).Position.Magnitude).toBeCloseTo(InfernoConfig.EnterDistance, 0.5)
	end)

	it("keeps broken plates broken after the bounce", function()
		local run = fight({ ShipStart = PLATE + Vector2.new(4.5, 0), ShipHeading = 0 })
		pushThenRamPlate(run)
		local log = record(run)
		while count(log, "BossHit") == 0 do
			run:Step(Run.IdleInput, FRAME)
		end
		play(run, Run.IdleInput, 1)
		local boss = run:Snapshot().Boss :: Run.BossSnapshot
		expect(boss.PlatesLeft).toBe(InfernoConfig.Plates - 1)
		expect(boss.Phase).toBe(1)
		expect(#plates(run:Snapshot())).toBe(InfernoConfig.Plates - 1)
	end)

	it("counts down: the time to impact shrinks as it descends", function()
		local run = fight({ ShipStart = Vector2.new(50, 30) })
		local first = (run:Snapshot().Boss :: Run.BossSnapshot).TimeToImpact
		expect(first).toBeCloseTo(InfernoConfig.Phase1Time, 0.1)
		play(run, Run.IdleInput, 10)
		expect((run:Snapshot().Boss :: Run.BossSnapshot).TimeToImpact).toBeCloseTo(first - 10, 0.1)
	end)

	it("loses the call when its hits take the planet's last HP", function()
		local run = fight({ ShipStart = Vector2.new(50, 30), Tuning = { Inferno = { Phase1Time = 5 } } })
		local log = record(run)
		play(run, Run.IdleInput, 20)
		expect(count(log, "BossHit")).toBe(3) -- 40 + 40 + the last 20
		expect(run:Snapshot().Phase).toBe("Over")
		expect(log[#log][1]).toBe("RunFinished")
		expect(log[#log][2].Won).toBe(false)
	end)
end)

describe("Inferno phases 2-3: burn-off and core", function()
	it(
		"starts phase 2 at half the plates, descends faster and sheds a comet or cluster on the data's interval",
		function()
			-- two plates: breaking the east one leaves half
			local run = fight({
				ShipStart = PLATE + Vector2.new(4.5, 0),
				ShipHeading = 0,
				Tuning = { Inferno = { Plates = 2 }, Arena = { PlanetMaxHp = 1000 } },
			})
			local log = record(run)
			pushThenRamPlate(run)
			play(run, Run.IdleInput, FRAME * 2)
			local boss = run:Snapshot().Boss :: Run.BossSnapshot
			expect(boss.Phase).toBe(2)
			expect(count(log, "BossPhaseChanged")).toBe(1)
			local speed1 = (InfernoConfig.EnterDistance - CONTACT) / InfernoConfig.Phase1Time
			local speed2 = (InfernoConfig.EnterDistance - CONTACT) / InfernoConfig.Phase2Time
			local before = boss.Position.Magnitude
			play(run, Run.IdleInput, 1)
			local after = (run:Snapshot().Boss :: Run.BossSnapshot).Position.Magnitude
			expect(before - after).toBeCloseTo(speed2, 0.01)
			expect(speed2 > speed1).toBe(true)

			-- sheds on the interval: count new comets and clusters over three intervals
			local seen, shed = {}, 0
			for _, rock in run:Snapshot().Rocks do
				seen[rock.Id] = true
			end
			for _ = 1, math.round(InfernoConfig.ShedInterval * 3 / FRAME) do
				run:Step(Run.IdleInput, FRAME)
				for _, rock in run:Snapshot().Rocks do
					if not seen[rock.Id] then
						seen[rock.Id] = true
						if rock.Type.Id == "Comet" or rock.Type.Id == "Cluster" then
							shed += 1
						end
					end
				end
			end
			expect(shed).toBe(3)
		end
	)

	it("exposes the core in phase 3, which only PERFECTs crack: exactly 3 of them win the call", function()
		-- no plates, so the core is out at once; it sits just above the orbit at the bottom
		local run = fight({
			ShipStart = Vector2.new(0, -TRACK),
			ShipHeading = 0,
			Tuning = {
				Inferno = { Plates = 0, EnterDistance = TRACK + 6 },
				Ship = { OrbitEntryMin = 0 },
				Arena = { PlanetMaxHp = 1e6 },
			},
		})
		local log = record(run)
		local boss = run:Snapshot().Boss :: Run.BossSnapshot
		expect(boss.Phase).toBe(3)
		expect(boss.CoreHitsLeft).toBe(InfernoConfig.CoreHits)

		local core = nil
		for _, rock in run:Snapshot().Rocks do
			if rock.Type.Id == "Core" then
				core = rock
			end
		end
		expect(core.Type.BreaksBy).toBe("Perfect")
		local hitsLeft = {}
		run.Events.CoreCracked:Connect(function(_, left: number)
			table.insert(hitsLeft, left)
		end)
		local t = 0
		while run:Snapshot().Phase ~= "Won" and t < 180 do
			run:Step(Pilot.Input(run:Snapshot(), run:GetTuning()), FRAME)
			t += FRAME
		end
		expect(run:Snapshot().Phase).toBe("Won")
		expect(hitsLeft).toEqual({ 2, 1 })
		local perfectsOnCore = 0
		for _, entry in log do
			if entry[1] == "Perfect" and entry[2].Type.Id == "Core" then
				perfectsOnCore += 1
			end
		end
		expect(perfectsOnCore).toBe(InfernoConfig.CoreHits)
		local finished = log[#log]
		expect(finished[1]).toBe("RunFinished")
		expect(finished[2].Won).toBe(true)
	end)

	it("plays the whole fight: plates, burn-off, the core, and the win", function()
		for seed = 1, 3 do
			local run = Run.new({ Seed = seed, Waves = {}, Boss = true, Tuning = { Arena = { PlanetMaxHp = 1e6 } } })
			local log = record(run)
			local t = 0
			while run:Snapshot().Phase ~= "Won" and t < 600 do
				run:Step(Pilot.Input(run:Snapshot(), run:GetTuning()), 1 / 30)
				t += 1 / 30
			end
			local phases = {}
			for _, entry in log do
				if entry[1] == "BossPhaseChanged" then
					table.insert(phases, entry[2])
				end
			end
			expect(phases).toEqual({ 1, 2, 3 })
			expect(run:Snapshot().Phase).toBe("Won")
			expect(run:Summary().Won).toBe(true)
		end
	end)

	it("descends fastest in phase 3", function()
		local run = fight({ ShipStart = Vector2.new(50, 30), Tuning = { Inferno = { Plates = 0 } } })
		local before = (run:Snapshot().Boss :: Run.BossSnapshot).Position.Magnitude
		play(run, Run.IdleInput, 1)
		local after = (run:Snapshot().Boss :: Run.BossSnapshot).Position.Magnitude
		expect(before - after).toBeCloseTo((InfernoConfig.EnterDistance - CONTACT) / InfernoConfig.Phase3Time, 0.01)
	end)
end)
