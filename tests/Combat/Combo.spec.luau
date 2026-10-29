--!strict
local ArenaConfig = require("@shared/Data/ArenaConfig")
local ComboConfig = require("@shared/Data/ComboConfig")
local RockTypes = require("@shared/Data/RockTypes")
local Run = require("@shared/Run/Run")
local RunEvents = require("@shared/Run/RunEvents")
local RunInput = require("@shared/Run/RunInput")
local ShipConfig = require("@shared/Data/ShipConfig")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local FRAME = 1 / 60
local SHIP = Vector2.new(0, -40) -- far from the planet, so rocks barely fall during a test
local TRACK = ArenaConfig.PlanetRadius + ArenaConfig.OrbitAlt
local RIGHT = Vector2.new(1, 0)
local LEFT = Vector2.new(-1, 0)
local OUT = Vector2.new(0, -1) -- straight out from the bottom of the planet
-- A rock already touching the top of the planet: it hits on the first step, so there's damage to heal.
local HITS_PLANET = { Type = RockTypes.Rock, Position = Vector2.new(0, ArenaConfig.PlanetRadius + 1) }
local DAMAGED = ArenaConfig.PlanetMaxHp - RockTypes.Rock.DamagePercent

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

local function find(log: { { any } }, name: string): { any }?
	for _, entry in log do
		if entry[1] == name then
			return entry
		end
	end
	return nil
end

-- The ship out in the arena facing `heading`, with these rocks (offsets from the ship).
local function arena(heading: number, rocks: { Run.RockSetup }, tuning: any?): Run.Run
	local setups = { HITS_PLANET }
	for _, rock in rocks do
		table.insert(setups, { Type = rock.Type, Position = SHIP + rock.Position })
	end
	local run = Run.new({ Waves = {}, ShipStart = SHIP, ShipHeading = heading, Rocks = setups, Tuning = tuning })
	run:Step(RunInput.Idle, FRAME)
	assert(run:Snapshot().PlanetHp == DAMAGED, "the planet took a hit")
	return run
end

-- Primes a rock with the flame (the ship faces left, the rock is behind it), then turns and rams it.
local function pushThenRam(tuning: any?): (Run.Run, { { any } })
	local run = arena(math.pi, { { Type = RockTypes.Rock, Position = Vector2.new(4, 0) } }, tuning)
	local log = record(run)
	play(run, RunInput.steer(LEFT), 0.15)
	assert(run:Snapshot().Rocks[1].IsPrimed, "the push primes it")
	run:Step(RunInput.steer(RIGHT, 1, true, false), FRAME)
	play(run, RunInput.steer(RIGHT), 0.4)
	return run, log
end

-- The ship sits still in orbit at the bottom of the planet, with a rock `above` it.
local function underRock(above: number): Run.Run
	local run = Run.new({
		Waves = {},
		ShipStart = Vector2.new(0, -TRACK),
		ShipHeading = 0,
		Rocks = { HITS_PLANET, { Type = RockTypes.Rock, Position = Vector2.new(0, -(TRACK + above)) } },
		Tuning = { Ship = { OrbitEntryMin = 0 } },
	})
	run:Step(RunInput.Idle, FRAME)
	return run
end

describe("Heals", function()
	it("heals nothing for a plain ram", function()
		local run = arena(0, { { Type = RockTypes.Rock, Position = Vector2.new(6, 0) } })
		local log = record(run)
		run:Step(RunInput.steer(RIGHT, 1, true, false), FRAME)
		play(run, RunInput.steer(RIGHT), 0.2)
		expect((find(log, "RockBroken") :: any)[3]).toBe("Ram")
		expect(find(log, "Healed")).toBe(nil)
		expect(run:Snapshot().PlanetHp).toBe(DAMAGED)
	end)

	it("heals the push-break amount for a push then a break", function()
		local run, log = pushThenRam()
		expect((find(log, "RockBroken") :: any)[3]).toBe("PushBreak")
		expect(run:Snapshot().PlanetHp).toBe(DAMAGED + ComboConfig.HealPushBreak)
		expect((find(log, "Healed") :: any)[2]).toBe(ComboConfig.HealPushBreak)
	end)

	it("heals the dive amount for a slingshot break of an unpushed rock", function()
		local run = underRock(12)
		local log = record(run)
		play(run, RunInput.steer(OUT), 0.5)
		expect((find(log, "RockBroken") :: any)[3]).toBe("Dive")
		expect(run:Snapshot().PlanetHp).toBe(DAMAGED + ComboConfig.HealDive)
	end)

	it("heals the PERFECT amount for a primed rock broken by a slingshot, with a PERFECT", function()
		local run = underRock(6)
		local log = record(run)
		play(run, RunInput.Idle, 0.4) -- the flare primes it
		play(run, RunInput.steer(OUT), 0.5)
		expect((find(log, "RockBroken") :: any)[3]).toBe("Perfect")
		expect(find(log, "Perfect") ~= nil).toBe(true)
		expect(run:Snapshot().PlanetHp).toBe(DAMAGED + ComboConfig.HealPerfect)
	end)
end)

describe("Combo", function()
	it("adds each move's combo points: push, then a push-break", function()
		local run, log = pushThenRam()
		local changes: { string } = {}
		for _, entry in log do
			if entry[1] == "ComboChanged" then
				table.insert(changes, `{entry[2]} {entry[3]}`)
			end
		end
		expect(changes).toEqual({
			`{ComboConfig.PushPoints} Push`,
			`{ComboConfig.PushPoints + ComboConfig.PushBreakPoints} PushBreak`,
		})
		expect(run:Snapshot().Combo).toBe(ComboConfig.PushPoints + ComboConfig.PushBreakPoints)
	end)

	it("adds a point for a slingshot and the PERFECT's points for a PERFECT", function()
		local run = underRock(6)
		play(run, RunInput.Idle, 0.4)
		play(run, RunInput.steer(OUT), 0.5)
		local expected = ComboConfig.PushPoints + ComboConfig.SlingshotPoints + ComboConfig.PerfectPoints
		expect(run:Snapshot().Combo).toBe(expected)
	end)

	it("raises the score multiplier with the combo", function()
		local run = arena(0, {
			{ Type = RockTypes.Rock, Position = Vector2.new(6, 0) },
			{ Type = RockTypes.Rock, Position = Vector2.new(14, 0) },
		})
		run:Step(RunInput.steer(RIGHT, 1, true, false), FRAME)
		play(run, RunInput.steer(RIGHT, 1, false, true), 0.5)
		local snapshot = run:Snapshot()
		expect(snapshot.Combo).toBe(2)
		expect(snapshot.Multiplier).toBeCloseTo(1 + 2 * ComboConfig.MultPerCombo)
		-- the second break is scored at the first's combo
		local score = RockTypes.Rock.Score
		expect(snapshot.Score).toBeCloseTo(score + score * (1 + ComboConfig.MultPerCombo))
	end)

	it("runs out after the combo window while rocks are in the air", function()
		local run = arena(0, {
			{ Type = RockTypes.Rock, Position = Vector2.new(6, 0) },
			{ Type = RockTypes.Rock, Position = Vector2.new(-30, 0) },
		})
		local log = record(run)
		run:Step(RunInput.steer(RIGHT, 1, true, false), FRAME)
		play(run, RunInput.Idle, 0.3)
		expect(run:Snapshot().Combo).toBe(1)
		play(run, RunInput.Idle, ComboConfig.Window - 0.5)
		expect(run:Snapshot().Combo).toBe(1)
		play(run, RunInput.Idle, 0.5)
		expect(run:Snapshot().Combo).toBe(0)
		local last = log[#log]
		expect(last[1]).toBe("ComboChanged")
		expect(last[3]).toBe("Timeout")
	end)

	it("doesn't run out while there's nothing in the air to hit", function()
		local run = arena(0, { { Type = RockTypes.Rock, Position = Vector2.new(6, 0) } })
		run:Step(RunInput.steer(RIGHT, 1, true, false), FRAME)
		play(run, RunInput.Idle, ComboConfig.Window + 1)
		expect(run:Snapshot().Combo).toBe(1)
	end)

	it("is lost on a bump", function()
		local run = arena(0, {
			{ Type = RockTypes.Rock, Position = Vector2.new(6, 0) },
			{ Type = RockTypes.Rock, Position = Vector2.new(32, 0) }, -- reached after the boost, nose first
		})
		local log = record(run)
		run:Step(RunInput.steer(RIGHT, 1, true, false), FRAME)
		play(run, RunInput.steer(RIGHT), 0.3)
		expect(run:Snapshot().Combo).toBe(1)
		play(run, RunInput.steer(RIGHT), 0.8)
		expect(find(log, "ShipBumped") ~= nil).toBe(true)
		local lost = log[#log]
		expect(lost[1]).toBe("ComboChanged")
		expect(lost[2]).toBe(0)
		expect(lost[3]).toBe("Bump")
	end)

	it("is lost when a rock hits the planet", function()
		local run = Run.new({
			Waves = {},
			ShipStart = SHIP,
			ShipHeading = 0,
			Rocks = {
				{ Type = RockTypes.Rock, Position = SHIP + Vector2.new(6, 0) },
				{ Type = RockTypes.Rock, Position = Vector2.new(0, ArenaConfig.PlanetRadius + 3) },
			},
		})
		run:Step(RunInput.steer(RIGHT, 1, true, false), FRAME)
		play(run, RunInput.Idle, 0.3)
		expect(run:Snapshot().Combo).toBe(1)
		play(run, RunInput.Idle, 1)
		expect(run:Snapshot().PlanetHp < ArenaConfig.PlanetMaxHp).toBe(true)
		expect(run:Snapshot().Combo).toBe(0)
	end)
end)

describe("Fuel from combos", function()
	it("gives fuel back for a push then a break", function()
		local run, log = pushThenRam()
		local refund = find(log, "FuelRefunded")
		expect(refund ~= nil).toBe(true)
		expect((refund :: any)[2] > 0).toBe(true)
		expect(run:Snapshot().Ship.Fuel > ShipConfig.FuelMax - ShipConfig.BoostCost + 20).toBe(true)
	end)

	it("refills fuel faster with a combo going", function()
		local run = pushThenRam({ Combo = { PushBreakRefuel = 0 } })
		play(run, RunInput.Idle, 0.5) -- the boost is long over
		local combo = run:Snapshot().Combo
		local before = run:Snapshot().Ship.Fuel
		play(run, RunInput.Idle, 1)
		local regen = ShipConfig.FuelRegen * (1 + combo * ComboConfig.RegenPerCombo)
		expect(run:Snapshot().Ship.Fuel - before).toBeCloseTo(regen, 1e-6)
	end)
end)
