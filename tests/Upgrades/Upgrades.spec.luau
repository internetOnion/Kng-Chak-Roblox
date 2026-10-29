--!strict
local ArenaConfig = require("@shared/Data/ArenaConfig")
local ComboConfig = require("@shared/Data/ComboConfig")
local RockTypes = require("@shared/Data/RockTypes")
local Run = require("@shared/Run/Run")
local RunEvents = require("@shared/Run/RunEvents")
local RunInput = require("@shared/Run/RunInput")
local ShipConfig = require("@shared/Data/ShipConfig")
local TestKit = require("@testkit")
local Upgrades = require("@shared/Data/Upgrades")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local FRAME = 1 / 60
local SHIP = Vector2.new(0, -40)
local TRACK = ArenaConfig.PlanetRadius + ArenaConfig.OrbitAlt
local LEFT = Vector2.new(-1, 0)
local RIGHT = Vector2.new(1, 0)
local OUT = Vector2.new(0, -1)

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

-- A run whose one-rock wave clears at once, so the first offer comes straight away.
local function offered(setup: { [string]: any }?): Run.Run
	local options: { [string]: any } = {
		Seed = 1,
		Waves = {
			{
				Wave = 1,
				Total = 1,
				Mix = { { Type = RockTypes.Rock, Weight = 1 } },
				InFlightCap = 1,
				FirstGroupDelay = 0,
				GroupInterval = 1,
				SpeedMult = 3,
			},
		},
	}
	for key, value in (setup or {}) :: { [string]: any } do
		options[key] = value
	end
	local run = Run.new(options :: any)
	for _ = 1, 60 * 60 do
		run:Step(Run.IdleInput, FRAME)
		local phase = run:Snapshot().Phase
		if phase ~= "Playing" and phase ~= "Breather" then
			break
		end
	end
	return run
end

-- The ship out in the arena facing `heading`, with these rocks at offsets from it, and these upgrades.
local function arena(heading: number, rocks: { Run.RockSetup }, upgrades: { [string]: number }?): Run.Run
	local setups = {}
	for _, rock in rocks do
		table.insert(setups, { Type = rock.Type, Position = SHIP + rock.Position })
	end
	return Run.new({ Waves = {}, ShipStart = SHIP, ShipHeading = heading, Rocks = setups, Upgrades = upgrades })
end

-- The ship still in orbit at the bottom of the planet, under a rock `above` it.
local function underRock(above: number, upgrades: { [string]: number }?): Run.Run
	local run = Run.new({
		Waves = {},
		ShipStart = Vector2.new(0, -TRACK),
		ShipHeading = 0,
		Rocks = {
			{ Type = RockTypes.Rock, Position = Vector2.new(0, ArenaConfig.PlanetRadius + 1) }, -- damage to heal
			{ Type = RockTypes.Rock, Position = Vector2.new(0, -(TRACK + above)) },
		},
		Tuning = { Ship = { OrbitEntryMin = 0 } },
		Upgrades = upgrades,
	})
	run:Step(RunInput.Idle, FRAME)
	return run
end

--[[
	Whether the flame primes iron at `offset` from a ship held still against the
	arena's west edge, flying into it at full throttle (the flame points east),
	within `seconds` (default 0.4), with these upgrades.
]]
local function primes(offset: Vector2, upgrades: { [string]: number }?, seconds: number?): boolean
	local at = Vector2.new(-ArenaConfig.ArenaRadius, 0)
	local run = Run.new({
		Waves = {},
		ShipStart = at,
		ShipHeading = math.pi,
		Rocks = { { Type = RockTypes.Iron, Position = at + offset } },
		Upgrades = upgrades,
	})
	play(run, RunInput.steer(LEFT), seconds or 0.4)
	local rock = run:Snapshot().Rocks[1]
	return rock ~= nil and rock.IsPrimed
end

describe("Upgrade cards", function()
	it("offers 3 different cards from different families once a wave clears, and waits", function()
		local run = offered()
		local snapshot = run:Snapshot()
		expect(snapshot.Phase).toBe("UpgradePick")
		local offer = snapshot.Offer :: { string }
		expect(#offer).toBe(3)
		local families = {}
		for _, id in offer do
			local family = Upgrades.ById[id].Family
			expect(families[family]).toBe(nil)
			families[family] = true
		end
		-- nothing moves while the cards are up
		local before = snapshot.Ship.Position
		play(run, RunInput.steer(RIGHT), 1)
		expect(run:Snapshot().Ship.Position).toBe(before)
		expect(run:Snapshot().Time).toBe(snapshot.Time)
	end)

	it("applies the picked card and moves on to the next wave", function()
		local run = Run.new({ Seed = 3, Tuning = { Arena = { PlanetMaxHp = 1e6 } } })
		local log = record(run)
		for _ = 1, 60 * 200 do
			run:Step(Run.IdleInput, FRAME)
			if run:Snapshot().Phase == "UpgradePick" then
				break
			end
		end
		local offer = run:Snapshot().Offer :: { string }
		expect(run:PickUpgrade(2)).toBe(true)
		local picked = find(log, "UpgradePicked") :: { any }
		expect(picked[2]).toBe(offer[2])
		expect(picked[3]).toBe(1)
		local snapshot = run:Snapshot()
		expect(snapshot.Upgrades[offer[2]]).toBe(1)
		expect(snapshot.Phase).toBe("Breather")
		expect((find(log, "WaveAnnounced") :: any)[2]).toBe(1)
		expect(log[#log][1]).toBe("WaveAnnounced")
		expect(log[#log][2]).toBe(2)
		expect(run:PickUpgrade(1)).toBe(false) -- the offer is gone
	end)

	it("draws families apart on every seed, and the same cards for the same seed", function()
		for seed = 1, 12 do
			local offer = offered({ Seed = seed }):Snapshot().Offer :: { string }
			local families = {}
			for _, id in offer do
				families[Upgrades.ById[id].Family] = true
			end
			local count = 0
			for _ in families do
				count += 1
			end
			expect(count).toBe(3)
			expect(offered({ Seed = seed }):Snapshot().Offer).toEqual(offer)
		end
	end)

	it("never offers an upgrade at its stack limit, and offers what's left", function()
		local maxed = {}
		for _, upgrade in Upgrades.List do
			maxed[upgrade.Id] = upgrade.MaxStacks
		end
		maxed.Firebreak = 1
		maxed.LongHose = 0
		local offer = table.clone(offered({ Upgrades = maxed }):Snapshot().Offer :: { string })
		table.sort(offer)
		expect(offer).toEqual({ "Firebreak", "LongHose" })
	end)

	it("skips the pick when every upgrade is at its limit", function()
		local maxed = {}
		for _, upgrade in Upgrades.List do
			maxed[upgrade.Id] = upgrade.MaxStacks
		end
		local run = offered({ Upgrades = maxed })
		expect(run:Snapshot().Offer).toBe(nil)
		expect(run:Snapshot().Phase).toBe("Breather")
	end)

	it("stacks a card each time it's picked, up to its limit", function()
		local run = offered({ Upgrades = { StickyHeat = 1 } })
		expect(run:GetTuning().Ship.PrimedTime).toBe(ShipConfig.PrimedTime + 3)
		local maxedRun = offered({ Upgrades = { StickyHeat = 2 } })
		expect(maxedRun:GetTuning().Ship.PrimedTime).toBe(ShipConfig.PrimedTime + 6)
		expect(table.find(maxedRun:Snapshot().Offer :: { string }, "StickyHeat")).toBe(nil)
	end)

	it("changes tuning only through the run, never the data", function()
		local run = Run.new({ Waves = {}, Upgrades = { LongHose = 2 } })
		expect(run:GetTuning().Ship.PushRange).toBeCloseTo(ShipConfig.PushRange * 1.4)
		expect(ShipConfig.PushRange).toBe(10)
		expect(Run.new({ Waves = {} }):GetTuning().Ship.PushRange).toBe(ShipConfig.PushRange)
	end)

	it("stacks on top of tuning overrides", function()
		local run = Run.new({ Waves = {}, Tuning = { Ship = { PushRange = 20 } }, Upgrades = { LongHose = 1 } })
		expect(run:GetTuning().Ship.PushRange).toBeCloseTo(24)
		run:SetTuning({ Ship = { PushRange = 5 } })
		expect(run:GetTuning().Ship.PushRange).toBeCloseTo(6)
	end)
end)

describe("Flame upgrades", function()
	it("Long Hose: the flame reaches 20% farther a stack", function()
		local far = Vector2.new(12, 0) -- its near edge is just past the plain flame's reach
		expect(primes(far)).toBe(false)
		expect(primes(far, { LongHose = 1 })).toBe(true)
		local farther = Vector2.new(14, 0)
		expect(primes(farther, { LongHose = 1 })).toBe(false)
		expect(primes(farther, { LongHose = 2 })).toBe(true)
		local run = Run.new({ Waves = {}, ShipStart = SHIP, Upgrades = { LongHose = 1 } })
		play(run, RunInput.steer(LEFT), 1)
		expect(run:Snapshot().Ship.FlameReach).toBeCloseTo(ShipConfig.PushRange * 1.2, 0.01)
	end)

	it("Wide Nozzle: the push cone is 30% wider a stack", function()
		local function at(degrees: number): Vector2
			return Vector2.new(math.cos(math.rad(degrees)), math.sin(math.rad(degrees))) * 6
		end
		-- outside the plain cone (42°), inside one stack's (54.6°)
		expect(primes(at(48), nil, 0.25)).toBe(false)
		expect(primes(at(48), { WideNozzle = 1 }, 0.25)).toBe(true)
		-- outside one stack's, inside two (67.2°)
		expect(primes(at(61), { WideNozzle = 1 }, 0.25)).toBe(false)
		expect(primes(at(61), { WideNozzle = 2 }, 0.25)).toBe(true)
	end)

	it("Sticky Heat: a primed rock stays primed 3 s longer", function()
		local function primedAfter(seconds: number, upgrades: { [string]: number }?): boolean
			local run = arena(math.pi, { { Type = RockTypes.Iron, Position = Vector2.new(4, 0) } }, upgrades)
			play(run, RunInput.steer(LEFT), 0.15)
			play(run, RunInput.Idle, seconds)
			return run:Snapshot().Rocks[1].IsPrimed
		end
		expect(primedAfter(ShipConfig.PrimedTime + 1)).toBe(false)
		expect(primedAfter(ShipConfig.PrimedTime + 1, { StickyHeat = 1 })).toBe(true)
		expect(primedAfter(ShipConfig.PrimedTime + 3.5, { StickyHeat = 1 })).toBe(false)
	end)
end)

describe("Spear upgrades", function()
	it("Tempered Tip: the spear stays out 0.3 s longer a boost", function()
		local function spearTime(upgrades: { [string]: number }?): number
			local run = arena(0, {}, upgrades)
			run:Step(RunInput.steer(RIGHT, 1, true, false), FRAME)
			local t = FRAME
			while run:Snapshot().Ship.IsSpearOut do
				run:Step(RunInput.steer(RIGHT), FRAME)
				t += FRAME
			end
			return t
		end
		local plain = spearTime()
		expect(plain).toBeCloseTo(ShipConfig.BoostDuration, FRAME * 1.5)
		expect(spearTime({ TemperedTip = 1 }) - plain).toBeCloseTo(0.3, FRAME * 1.5)
		expect(spearTime({ TemperedTip = 2 }) - plain).toBeCloseTo(0.6, FRAME * 1.5)
	end)

	it("Extra Tank: one more boost's worth of fuel, filled when picked", function()
		local run = Run.new({ Waves = {}, Upgrades = { ExtraTank = 1 } })
		local snapshot = run:Snapshot()
		expect(snapshot.FuelMax).toBe(ShipConfig.FuelMax + ShipConfig.BoostCost)
		-- four boosts back to back, where the plain tank has three
		local boosts = 0
		run.Events.Boosted:Connect(function()
			boosts += 1
		end)
		for _ = 1, 4 do
			run:Step(RunInput.steer(RIGHT, 1, true, false), FRAME)
			play(run, RunInput.steer(RIGHT), 0.05)
		end
		expect(boosts).toBe(4)

		local picking = offered({ Upgrades = {} })
		local offer = picking:Snapshot().Offer :: { string }
		local index = table.find(offer, "ExtraTank")
		if index then
			local before = picking:Snapshot().Ship.Fuel
			picking:PickUpgrade(index)
			expect(picking:Snapshot().Ship.Fuel).toBe(before + ShipConfig.BoostCost)
		end
	end)

	it("Shockwave: breaking a primed rock primes every rock within 4", function()
		local function nearbyPrimed(upgrades: { [string]: number }?): (boolean, boolean)
			local run = arena(math.pi, {
				{ Type = RockTypes.Rock, Position = Vector2.new(4, 0) },
				{ Type = RockTypes.Rock, Position = Vector2.new(4, 4.5) }, -- outside the flame; its edge ends up within 4
				{ Type = RockTypes.Rock, Position = Vector2.new(4, -12) }, -- out of reach
			}, upgrades)
			local log = record(run)
			play(run, RunInput.steer(LEFT), 0.15)
			run:Step(RunInput.steer(RIGHT, 1, true, false), FRAME)
			play(run, RunInput.steer(RIGHT), 0.3)
			-- a rock the shockwave primes adds its combo point as a "Shockwave" move
			local near, far = false, false
			for i, entry in log do
				local nextEntry = log[i + 1]
				if entry[1] == "RockPrimed" and nextEntry and nextEntry[3] == "Shockwave" then
					near = near or entry[2].Id == 2
					far = far or entry[2].Id == 3
				end
			end
			assert((find(log, "RockBroken") :: any)[2].Id == 1, "the primed rock broke")
			return near, far
		end
		local near, far = nearbyPrimed({ Shockwave = 1 })
		expect(near).toBe(true)
		expect(far).toBe(false)
		expect((nearbyPrimed())).toBe(false)
	end)
end)

describe("Orbit upgrades", function()
	it("Quick Release: the slingshot cooldown is 30% shorter a stack", function()
		local run = Run.new({ Waves = {}, Upgrades = { QuickRelease = 2 } })
		expect(run:GetTuning().Ship.SlingshotCooldown).toBeCloseTo(ShipConfig.SlingshotCooldown * 0.4)
	end)

	it("Long Dive: the slingshot flies 20% faster a stack", function()
		local function diveSpeed(upgrades: { [string]: number }?): number
			local run = underRock(30, upgrades)
			run:Step(RunInput.steer(OUT), FRAME)
			local ship = run:Snapshot().Ship
			assert(ship.IsSlingshotting, "the slingshot launched")
			return ship.Velocity.Magnitude
		end
		expect(diveSpeed()).toBeCloseTo(ShipConfig.SlingshotSpeed, 1e-3)
		expect(diveSpeed({ LongDive = 1 })).toBeCloseTo(ShipConfig.SlingshotSpeed * 1.2, 1e-3)
	end)

	it("Firebreak: a PERFECT heals 2% more a stack", function()
		local function perfectHeal(upgrades: { [string]: number }?): number
			local run = underRock(6, upgrades)
			local log = record(run)
			play(run, RunInput.Idle, 0.4)
			play(run, RunInput.steer(OUT), 0.5)
			assert((find(log, "RockBroken") :: any)[3] == "Perfect", "a PERFECT")
			return (find(log, "Healed") :: any)[2]
		end
		expect(perfectHeal()).toBe(ComboConfig.HealPerfect)
		expect(perfectHeal({ Firebreak = 1 })).toBe(ComboConfig.HealPerfect + 2)
		expect(perfectHeal({ Firebreak = 2 })).toBe(ComboConfig.HealPerfect + 4)
	end)
end)

describe("Shield Plating", function()
	it("raises the shield cap from 25% to 35%", function()
		local run = Run.new({ Waves = {}, Upgrades = { ShieldPlating = 1 } })
		expect(run:Snapshot().PlanetMaxShield).toBe(ArenaConfig.PlanetMaxShield + 10)
		expect(Run.new({ Waves = {} }):Snapshot().PlanetMaxShield).toBe(ArenaConfig.PlanetMaxShield)
	end)
end)

describe("Upgrade data", function()
	it("has 10 upgrades in the Flame, Spear, Orbit and Any families, each changing real tuning values", function()
		expect(#Upgrades.List).toBe(10)
		local run = Run.new({ Waves = {} })
		local tuning = run:GetTuning() :: any
		for _, upgrade in Upgrades.List do
			expect(table.find({ "Flame", "Spear", "Orbit", "Any" }, upgrade.Family) ~= nil).toBe(true)
			expect(upgrade.MaxStacks >= 1).toBe(true)
			for _, effect in upgrade.Effects do
				expect(type(tuning[effect.Section][effect.Key])).toBe("number")
			end
		end
	end)
end)
