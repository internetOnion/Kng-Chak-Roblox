--!strict
local RockTypes = require("@shared/Data/RockTypes")
local Run = require("@shared/Run/Run")
local RunEvents = require("@shared/Run/RunEvents")
local RunInput = require("@shared/Run/RunInput")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local FRAME = 1 / 60
local SHIP = Vector2.new(0, -40)
local RIGHT = Vector2.new(1, 0)
local SPLIT = RockTypes.Cluster.Split :: RockTypes.Split

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

-- Rams a cluster 6 units to the right of the ship with a boost, and keeps flying on.
local function ramCluster(seed: number?): (Run.Run, { { any } })
	local run = Run.new({
		Seed = seed,
		Waves = {},
		ShipStart = SHIP,
		ShipHeading = 0,
		Rocks = { { Type = RockTypes.Cluster, Position = SHIP + Vector2.new(6, 0) } },
	})
	local log = record(run)
	run:Step(RunInput.steer(RIGHT, 1, true, false), FRAME)
	play(run, RunInput.steer(RIGHT, 1, false, true), 0.1)
	return run, log
end

describe("Cluster split", function()
	it("splits a broken cluster into its shards", function()
		local run, log = ramCluster()
		expect((find(log, "RockBroken") :: any)[2].Type.Id).toBe("Cluster")
		local split = find(log, "RockSplit")
		expect(split ~= nil).toBe(true)
		expect(#(split :: any)[3]).toBe(SPLIT.Count)
		local rocks = run:Snapshot().Rocks
		expect(#rocks).toBe(3)
		for _, rock in rocks do
			expect(rock.Type).toBe(RockTypes.Shard)
		end
	end)

	it("sends the shards flying apart", function()
		local run = ramCluster()
		play(run, RunInput.Idle, 0.3)
		local rocks = run:Snapshot().Rocks
		for i = 1, #rocks do
			for j = i + 1, #rocks do
				expect((rocks[i].Position - rocks[j].Position).Magnitude > 2).toBe(true)
			end
		end
	end)

	it("keeps the boosting spear from breaking the shards it just made", function()
		local run, log = ramCluster()
		local broken = 0
		for _, entry in log do
			if entry[1] == "RockBroken" then
				broken += 1
			end
		end
		expect(broken).toBe(1)
		expect(#run:Snapshot().Rocks).toBe(SPLIT.Count)
	end)

	it("makes shards that act as their own rock type and hit for its damage", function()
		local run = Run.new({
			Waves = {},
			ShipStart = SHIP,
			Rocks = { { Type = RockTypes.Shard, Position = Vector2.new(0, 12) } },
		})
		local log = record(run)
		play(run, RunInput.Idle, 2)
		local hit = find(log, "PlanetHit")
		expect(hit ~= nil).toBe(true)
		expect((hit :: any)[2].Type.Id).toBe("Shard")
		expect((hit :: any)[3]).toBe(RockTypes.Shard.DamagePercent)
	end)

	it("splits the same way on the same seed", function()
		local first = ramCluster(3)
		local second = ramCluster(3)
		play(first, RunInput.Idle, 0.2)
		play(second, RunInput.Idle, 0.2)
		local a, b = first:Snapshot().Rocks, second:Snapshot().Rocks
		for i = 1, #a do
			expect(a[i].Position).toBe(b[i].Position)
		end
	end)
end)
