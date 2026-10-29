--!strict
local ArenaConfig = require("@shared/Data/ArenaConfig")
local ComboConfig = require("@shared/Data/ComboConfig")
local RockTypes = require("@shared/Data/RockTypes")
local Run = require("@shared/Run/Run")
local RunEvents = require("@shared/Run/RunEvents")
local RunInput = require("@shared/Run/RunInput")
local TestKit = require("@testkit")
local WaveConfig = require("@shared/Data/WaveConfig")
local WaveModifiers = require("@shared/Data/WaveModifiers")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local FRAME = 1 / 30
local TRACK = ArenaConfig.PlanetRadius + ArenaConfig.OrbitAlt
-- So idle runs survive whole calls: every rock gets through, and the planet shrugs it off.
local TOUGH = { Arena = { PlanetMaxHp = 1e6 } }

local function record(run: Run.Run): { { any } }
	local log = {}
	for _, name in RunEvents.Names do
		RunEvents.Get(run.Events, name):Connect(function(...)
			table.insert(log, { name, ... })
		end)
	end
	return log
end

-- Plays idle for up to `seconds`, picking the first card of every offer. Stops when `done` returns true.
local function playCall(run: Run.Run, seconds: number, done: ((Run.Snapshot) -> boolean)?)
	for _ = 1, math.round(seconds / FRAME) do
		if run:Snapshot().Phase == "UpgradePick" then
			run:PickUpgrade(1)
		end
		run:Step(Run.IdleInput, FRAME)
		if done and done(run:Snapshot()) then
			return
		end
	end
end

-- Rock types spawned in each wave, by wave: the first appearance of each rock id.
local function spawnsByWave(run: Run.Run, seconds: number, untilWave: number): { [number]: { string } }
	local seen, out = {}, {}
	playCall(run, seconds, function(snapshot)
		for _, rock in snapshot.Rocks do
			if not seen[rock.Id] then
				seen[rock.Id] = true
				local list = out[snapshot.Wave] or {}
				out[snapshot.Wave] = list
				table.insert(list, rock.Type.Id)
			end
		end
		return snapshot.Wave > untilWave
	end)
	return out
end

-- The WaveAnnounced events of a log: wave -> { intro, modifiers }.
local function announced(log: { { any } }): { [number]: { any } }
	local out = {}
	for _, entry in log do
		if entry[1] == "WaveAnnounced" then
			out[entry[2]] = { entry[3], entry[4] }
		end
	end
	return out
end

describe("The emergency call", function()
	it("plays waves 1 to 12 from the wave data, an upgrade pick after each, then the Inferno", function()
		local run = Run.new({ Seed = 11, Tuning = TOUGH })
		local log = record(run)
		playCall(run, 1500, function(snapshot)
			return snapshot.Phase == "Boss"
		end)
		local order = {}
		for _, entry in log do
			if entry[1] == "WaveStarted" or entry[1] == "WaveCleared" or entry[1] == "UpgradePicked" then
				table.insert(order, entry[1])
			elseif entry[1] == "BossPhaseChanged" then
				table.insert(order, `Boss {entry[2]}`)
			end
		end
		local expected = {}
		for _ = 1, WaveConfig.LastWave do
			table.insert(expected, "WaveStarted")
			table.insert(expected, "WaveCleared")
			table.insert(expected, "UpgradePicked")
		end
		table.insert(expected, "Boss 1")
		expect(order).toEqual(expected)
		expect(run:Snapshot().Wave).toBe(WaveConfig.LastWave)
	end)

	it("sends each wave its rock count, and only the threats introduced so far", function()
		local byWave = spawnsByWave(Run.new({ Seed = 4, Tuning = TOUGH }), 1500, 8)
		for wave = 1, 7 do
			local types = byWave[wave]
			expect(#types).toBe(WaveConfig.WaveBase + wave * WaveConfig.WavePerLevel)
			for _, id in types do
				local from = if id == "Comet"
					then WaveConfig.CometFrom
					elseif id == "Iron" then WaveConfig.IronFrom
					elseif id == "Cluster" then WaveConfig.ClusterFrom
					else 1
				expect(wave >= from).toBe(true)
			end
		end
	end)

	it("introduces comets, iron and clusters on waves 3, 5 and 7: first in the wave, with a tip", function()
		local intros = { [3] = "Comet", [5] = "Iron", [7] = "Cluster" }
		for wave, id in intros do
			local run = Run.new({ Seed = 9, StartWave = wave, Tuning = TOUGH })
			local log = record(run)
			local byWave = spawnsByWave(run, 120, wave)
			expect(byWave[wave][1]).toBe(id)
			expect(announced(log)[wave][1]).toBe(id)
			expect(WaveModifiers.Intros[id] ~= nil).toBe(true)
		end
		local log = record(Run.new({ Seed = 9 }))
		expect(#log).toBe(0) -- nothing fires before the first step
	end)

	it("announces no intro on waves that bring nothing new", function()
		local run = Run.new({ Seed = 9, Tuning = TOUGH })
		local log = record(run)
		playCall(run, 400, function(snapshot)
			return snapshot.Wave >= 4
		end)
		local waves = announced(log)
		expect(waves[1][1]).toBe("Rock")
		expect(waves[2][1]).toBe(nil)
		expect(waves[3][1]).toBe("Comet")
		expect(waves[4][1]).toBe(nil)
	end)

	it("ends each wave with the pick, then the next wave's banner, then a breather before it starts", function()
		local run = Run.new({ Seed = 2, Tuning = TOUGH })
		local log = record(run)
		local t, announcedAt, startedAt = 0, nil, nil
		playCall(run, 200, function()
			t += FRAME
			local last = log[#log]
			if last[1] == "WaveAnnounced" and last[2] == 2 and not announcedAt then
				announcedAt = t
			elseif last[1] == "WaveStarted" and last[2] == 2 then
				startedAt = t
				return true
			end
			return false
		end)
		local names = {}
		for _, entry in log do
			if entry[1] ~= "PlanetHit" and entry[1] ~= "ComboChanged" then
				table.insert(names, entry[1])
			end
		end
		expect(names).toEqual({
			"WaveAnnounced",
			"WaveStarted",
			"WaveCleared",
			"UpgradeOffered",
			"UpgradePicked",
			"WaveAnnounced",
			"WaveStarted",
		})
		expect(startedAt - announcedAt).toBeCloseTo(WaveConfig.Breather, FRAME * 1.5)
	end)

	it("plans the same waves for the same seed", function()
		local a = spawnsByWave(Run.new({ Seed = 21, StartWave = 6, Tuning = TOUGH }), 300, 7)
		local b = spawnsByWave(Run.new({ Seed = 21, StartWave = 6, Tuning = TOUGH }), 300, 7)
		expect(a).toEqual(b)
		expect(#a[6]).toBe(WaveConfig.WaveBase + 6 * WaveConfig.WavePerLevel)
	end)
end)

describe("Wave modifiers", function()
	-- Each seed's announced modifiers for waves 7 to 12.
	local function modifiersFor(seed: number): { [number]: { string } }
		local run = Run.new({ Seed = seed, StartWave = 7, Tuning = TOUGH })
		local log = record(run)
		playCall(run, 900, function(snapshot)
			return snapshot.Phase == "Boss"
		end)
		local out = {}
		for wave, entry in announced(log) do
			out[wave] = entry[2]
		end
		return out
	end

	it("gives waves 8-11 one modifier each and the surge on wave 10 two, never repeating the wave before's", function()
		for seed = 1, 6 do
			local mods = modifiersFor(seed)
			expect(#mods[7]).toBe(0)
			expect(#mods[8]).toBe(1)
			expect(#mods[9]).toBe(1)
			expect(#mods[10]).toBe(2)
			expect(#mods[11]).toBe(1)
			expect(#mods[12]).toBe(0)
			expect(mods[10][1] == mods[10][2]).toBe(false)
			for wave = 9, 11 do
				for _, id in mods[wave] do
					expect(table.find(mods[wave - 1], id)).toBe(nil)
				end
			end
		end
	end)

	it("picks different modifiers on different seeds", function()
		local seen, kinds = {}, 0
		for seed = 1, 12 do
			local run = Run.new({ Seed = seed, StartWave = 8 })
			local log = record(run)
			run:Step(Run.IdleInput, FRAME)
			local id = announced(log)[8][2][1]
			if not seen[id] then
				seen[id] = true
				kinds += 1
			end
		end
		expect(kinds > 2).toBe(true)
	end)

	it("heals the surge amount when a surge wave is survived", function()
		-- a one-rock wave 1 made a surge
		local run = Run.new({
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
			Tuning = { Waves = { RemixStart = 1, RemixEnd = 1, SurgeEvery = 1 } },
		})
		local log = record(run)
		playCall(run, 60, function(snapshot)
			return snapshot.Phase == "UpgradePick"
		end)
		local healed
		for _, entry in log do
			if entry[1] == "Healed" then
				healed = entry
			end
		end
		expect(healed[2]).toBe(WaveConfig.SurgeHeal)
		expect(healed[3]).toBe("Surge")
		local snapshot = run:Snapshot()
		expect(snapshot.PlanetHp + snapshot.PlanetShield).toBe(
			100 - RockTypes.Rock.DamagePercent + WaveConfig.SurgeHeal
		)
	end)

	-- A seed whose wave 8 gets `id`.
	local function seedWith(id: string): number
		for seed = 1, 200 do
			local run = Run.new({ Seed = seed, StartWave = 8, Tuning = TOUGH })
			local log = record(run)
			run:Step(Run.IdleInput, FRAME)
			local mods = announced(log)[8][2]
			if mods[1] == id then
				return seed
			end
		end
		error(`no seed gives wave 8 {id}`)
	end

	it("slips exactly one golden rock into a golden rock wave", function()
		local seed = seedWith("GoldenRock")
		local byWave = spawnsByWave(Run.new({ Seed = seed, StartWave = 8, Tuning = TOUGH }), 300, 8)
		local golds = 0
		for _, id in byWave[8] do
			golds += if id == "Gold" then 1 else 0
		end
		expect(golds).toBe(1)
		expect(#byWave[8]).toBe(WaveConfig.WaveBase + 8 * WaveConfig.WavePerLevel)
	end)

	it("lands a pincer wave's groups on both sides of the planet", function()
		local seed = seedWith("Pincer")
		local run = Run.new({ Seed = seed, StartWave = 8, Tuning = TOUGH })
		local first: { Vector2 } = {}
		playCall(run, 20, function(snapshot)
			if #snapshot.Rocks >= 2 then
				for _, rock in snapshot.Rocks do
					table.insert(first, rock.Position)
				end
				return true
			end
			return false
		end)
		-- the first two rocks of the group are about half a turn apart
		local a, b = first[1], first[2]
		local between = math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1))
		expect(between > math.pi * 0.75).toBe(true)
	end)

	it("splits clusters into 4 shards and thins the drag band while those modifiers play", function()
		local bloom = Run.new({ Seed = seedWith("Bloom"), StartWave = 8, Tuning = TOUGH })
		playCall(bloom, 10, function(snapshot)
			return snapshot.Phase == "Playing"
		end)
		expect(bloom:GetTuning().Waves.ExtraShards).toBe(1)
		local lowDrag = Run.new({ Seed = seedWith("LowDrag"), StartWave = 8, Tuning = TOUGH })
		playCall(lowDrag, 10, function(snapshot)
			return snapshot.Phase == "Playing"
		end)
		expect(lowDrag:GetTuning().Arena.DragBandMult).toBe(0.8)
		expect(Run.new():GetTuning().Arena.DragBandMult).toBe(ArenaConfig.DragBandMult)
	end)
end)

describe("Golden rock", function()
	-- The ship in orbit under a golden rock: the flare primes it, then a slingshot dives into it.
	local function perfectOnGold(): (Run.Run, { { any } })
		local run = Run.new({
			Waves = {},
			ShipStart = Vector2.new(0, -TRACK),
			ShipHeading = 0,
			Rocks = {
				{ Type = RockTypes.Rock, Position = Vector2.new(0, ArenaConfig.PlanetRadius + 1) }, -- damage to heal
				{ Type = RockTypes.Gold, Position = Vector2.new(0, -(TRACK + 6)) },
			},
			Tuning = { Ship = { OrbitEntryMin = 0 } },
		})
		run:Step(RunInput.Idle, 1 / 60)
		local log = record(run)
		for _ = 1, 24 do
			run:Step(RunInput.Idle, 1 / 60)
		end
		for _ = 1, 30 do
			run:Step(RunInput.steer(Vector2.new(0, -1)), 1 / 60)
		end
		return run, log
	end

	it("breaks only with a PERFECT, and heals the golden amount", function()
		local run, log = perfectOnGold()
		local broken, healed
		for _, entry in log do
			if entry[1] == "RockBroken" then
				broken = entry
			elseif entry[1] == "Healed" then
				healed = entry
			end
		end
		expect(broken[2].Type.Id).toBe("Gold")
		expect(broken[3]).toBe("Perfect")
		expect(healed[2]).toBe(ComboConfig.HealGold)
		local snapshot = run:Snapshot()
		expect(snapshot.PlanetHp + snapshot.PlanetShield).toBe(
			100 - RockTypes.Rock.DamagePercent + ComboConfig.HealGold
		)
	end)
end)
