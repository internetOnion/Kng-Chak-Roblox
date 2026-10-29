--!strict
local Replay = require("@shared/Run/Replay")
local Bot = (require("../Replays/Bot") :: any) :: Replay.Recording
local Run = require("@shared/Run/Run")
local RunInput = require("@shared/Run/RunInput")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

describe("Replay", function()
	it("replays a saved recording to exactly the events and ending it recorded", function()
		local log, final = Replay.Play(Bot)
		expect(log).toEqual(Bot.Events)
		expect(final).toBe(Bot.Final)
	end)

	it("gives the same run whatever the global random state, so the Run uses only its seed", function()
		math.randomseed(1)
		local first = { Replay.Play(Bot) }
		math.randomseed(987654)
		local second = { Replay.Play(Bot) }
		expect(first).toEqual(second)
	end)

	it("plays out differently on another seed", function()
		local other = table.clone(Bot)
		other.Seed = Bot.Seed + 1
		local _, final = Replay.Play(other)
		expect(final == Bot.Final).toBe(false)
	end)

	it("records exactly the input it hands the Run", function()
		local recorder = Replay.Recorder.new(5)
		local run = Run.new({ Seed = 5 })
		local log = Replay.Log(run)
		local raw = RunInput.steer(Vector2.new(0.123456789, 0.987654321), 0.333333333, true, true)
		for i = 1, 90 do
			run:Step(recorder:Record(raw, 1 / 60 + i * 1e-7))
		end
		local recording = recorder:Finish(log, run)
		local _, final = Replay.Play(recording)
		expect(final).toBe(recording.Final)
	end)
end)
