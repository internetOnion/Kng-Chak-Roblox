--!strict
local ArenaConfig = require("@shared/Data/ArenaConfig")
local GuidedConfig = require("@shared/Data/GuidedConfig")
local Run = require("@shared/Run/Run")
local RunEvents = require("@shared/Run/RunEvents")
local RunInput = require("@shared/Run/RunInput")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local FRAME = 1 / 30

local function record(run: Run.Run): { { any } }
	local log = {}
	for _, name in RunEvents.Names do
		RunEvents.Get(run.Events, name):Connect(function(...)
			table.insert(log, { name, ... })
		end)
	end
	return log
end

local function steps(log: { { any } }): { string }
	local out = {}
	for _, entry in log do
		if entry[1] == "GuidedStep" then
			table.insert(out, entry[3])
		end
	end
	return out
end

local function dummy(snapshot: Run.Snapshot): any
	local guided = snapshot.Guided :: Run.GuidedSnapshot
	for _, rock in snapshot.Rocks do
		if rock.Id == guided.DummyId then
			return rock
		end
	end
	return nil
end

-- What a player who knows the moves does on each step. `ram` makes step 3 a plain ram instead.
local function player(snapshot: Run.Snapshot, ram: boolean?): RunInput.RunInput
	local ship = snapshot.Ship
	local guided = snapshot.Guided :: Run.GuidedSnapshot
	local name = guided.StepName
	if name == "Move" then
		return RunInput.steer((guided.Beacon :: Vector2) - ship.Position)
	end
	local rock = dummy(snapshot)
	if not rock then
		return RunInput.Idle
	end
	local offset = rock.Position - ship.Position
	local canBoost = ship.Fuel >= 30 and not ship.IsSpearOut
	if name == "Boost" or (name == "PushBreak" and (rock.IsPrimed or ram)) then
		return RunInput.steer(offset, 1, offset.Magnitude < 10 and canBoost)
	elseif name == "PushBreak" then
		if offset.Magnitude > 6.5 then
			return RunInput.steer(offset - offset.Unit * 4.5, 0.6)
		end
		return RunInput.steer(-offset, 0.6)
	end
	-- Slingshot: into the band, then aim out at it once it's above
	if not ship.IsInOrbit then
		return if ship.IsSlingshotting then RunInput.steer(offset) else RunInput.steer(-ship.Position)
	end
	if ship.Position.Unit:Dot(rock.Position.Unit) > 0.95 then
		return RunInput.steer(offset)
	end
	return RunInput.Idle
end

-- Plays the guided call with `driver` for up to `seconds`.
local function play(run: Run.Run, seconds: number, driver: (Run.Snapshot) -> RunInput.RunInput)
	for _ = 1, math.round(seconds / FRAME) do
		local snapshot = run:Snapshot()
		if snapshot.Phase == "Won" then
			return
		end
		run:Step(driver(snapshot), FRAME)
	end
end

describe("Guided first call", function()
	it("walks a new player through move, boost, push then break, and orbit plus slingshot, in order", function()
		local run = Run.new({ Seed = 1, Mode = "Guided" })
		local log = record(run)
		play(run, 120, player)
		expect(steps(log)).toEqual({ "Move", "Boost", "PushBreak", "Slingshot" })
		local snapshot = run:Snapshot()
		expect(snapshot.Phase).toBe("Won")
		expect(snapshot.Wave).toBe(0) -- no waves in the guided call
		local finished = log[#log]
		expect(finished[1]).toBe("RunFinished")
		expect(finished[2].Mode).toBe("Guided")
		expect(finished[2].Won).toBe(true)
		-- the push then break visibly heals the planet
		local healed = false
		for _, entry in log do
			healed = healed or (entry[1] == "Healed" and entry[3] == "PushBreak")
		end
		expect(healed).toBe(true)
		expect(snapshot.PlanetHp > GuidedConfig.StartHp).toBe(true)
	end)

	it("takes 60-90 seconds or less for a player who knows the moves", function()
		local run = Run.new({ Seed = 1, Mode = "Guided" })
		play(run, 120, player)
		expect(run:Snapshot().Phase).toBe("Won")
		expect(run:Summary().Time < 90).toBe(true)
	end)

	it("only advances a step once its move is done", function()
		local run = Run.new({ Seed = 1, Mode = "Guided" })
		local log = record(run)
		play(run, 30, function()
			return RunInput.Idle
		end)
		expect(steps(log)).toEqual({ "Move" })
		-- a plain ram doesn't count as push then break: a new dummy comes each time and the step stays
		local rams = 0
		run.Events.RockBroken:Connect(function(_, cause: string)
			local guided = run:Snapshot().Guided :: Run.GuidedSnapshot
			if cause == "Ram" and guided.StepName == "PushBreak" then
				rams += 1
			end
		end)
		play(run, 60, function(snapshot)
			return if rams >= 3 then RunInput.Idle else player(snapshot, true)
		end)
		local snapshot = run:Snapshot()
		expect(rams >= 3).toBe(true)
		expect((snapshot.Guided :: Run.GuidedSnapshot).StepName).toBe("PushBreak")
		expect(dummy(snapshot) ~= nil).toBe(true)
	end)

	it("never damages the planet: a dummy that gets through is replaced", function()
		local run = Run.new({ Seed = 1, Mode = "Guided" })
		local log = record(run)
		-- reach step 2, then wait for its dummy to fall all the way
		play(run, 20, function(snapshot)
			return if (snapshot.Guided :: Run.GuidedSnapshot).StepName == "Move"
				then player(snapshot)
				else RunInput.Idle
		end)
		local first = (run:Snapshot().Guided :: Run.GuidedSnapshot).DummyId
		local fall = (GuidedConfig.BoostRockAt.Magnitude - ArenaConfig.PlanetRadius) / (3 * GuidedConfig.DummySpeed)
		-- park the ship far from the dummy's path
		play(run, fall * 1.5, function(snapshot)
			return RunInput.steer(Vector2.new(-40, 30) - snapshot.Ship.Position, 0.5)
		end)
		local snapshot = run:Snapshot()
		expect(snapshot.PlanetHp).toBe(GuidedConfig.StartHp)
		for _, entry in log do
			expect(entry[1] == "PlanetHit" or entry[1] == "GameOver").toBe(false)
		end
		local guided = snapshot.Guided :: Run.GuidedSnapshot
		expect(guided.StepName).toBe("Boost")
		expect(guided.DummyId ~= first).toBe(true)
	end)
end)
