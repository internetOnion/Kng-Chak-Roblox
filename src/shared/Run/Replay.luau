--!strict
--[[
	Replay: record the input a player gives a Run, and play it back exactly.

	A Run uses no randomness but its seed and reads no clock, so the same seed
	and the same input, frame by frame, give the same run. The live game feeds
	the Run through a Recorder, which rounds each frame's input slightly
	(Quantize) so the recording holds exactly what the Run saw.

	    local recorder = Replay.Recorder.new(seed)
	    local input, dt = recorder:Record(rawInput, rawDt)
	    run:Step(input, dt)
	    local log = Replay.Log(run)                        -- right after creating the run
	    print(Replay.Encode(recorder:Finish(log, run)))     -- a Luau module, for tests/Replays

	    Replay.Play(recording) --> the event log and summary, to compare with the recording's

	Event logs are lists of short strings (event name and arguments), so two logs
	compare with a plain equality check.
]]

local Run = require("./Run")
local RunEvents = require("./RunEvents")
local RunInput = require("./RunInput")

-- One frame: { dt, moveX, moveY, strength, flags } with flags 1 = boost pressed, 2 = boost held, 4 = brake.
export type Frame = { number }

export type Recording = {
	Seed: number,
	Frames: { Frame },
	Events: { string }, -- the event log the recorded run produced
	Final: string, -- a summary of how it ended (see Summary)
}

-- Recordings keep 6 decimals of frame time and 4 of input. Dividing by these exact integers gives the
-- same doubles that reading the decimals back does, so a saved recording replays bit for bit.
local DT_SCALE = 1e6
local MOVE_SCALE = 1e4

local Replay = {}

local function round(x: number, scale: number): number
	return math.round(x * scale) / scale
end

local function describe(value: any): string
	if type(value) == "table" and type(value.Type) == "table" then
		return `{value.Type.Id}#{value.Id}`
	elseif type(value) == "table" then
		local parts = {}
		for _, item in value do
			table.insert(parts, describe(item))
		end
		return `[{table.concat(parts, ",")}]`
	elseif typeof(value) == "Vector2" then
		return string.format("(%.2f,%.2f)", value.X, value.Y)
	elseif type(value) == "number" then
		return string.format("%.3f", value)
	end
	return tostring(value)
end

-- The run's event log from now on, filled in as events fire.
function Replay.Log(run: Run.Run): { string }
	local log = {}
	for _, name in RunEvents.Names do
		RunEvents.Get(run.Events, name):Connect(function(...)
			local parts = { name }
			for i = 1, select("#", ...) do
				table.insert(parts, describe((select(i, ...))))
			end
			table.insert(log, table.concat(parts, " "))
		end)
	end
	return log
end

-- A one-line summary of where a run stands: wave, score, planet HP and the ship's position and speed.
function Replay.Summary(run: Run.Run): string
	local snapshot = run:Snapshot()
	local ship = snapshot.Ship
	return string.format(
		"wave %d score %d hp %.3f ship %s speed %.3f rocks %d",
		snapshot.Wave,
		snapshot.Score,
		snapshot.PlanetHp,
		describe(ship.Position),
		ship.Velocity.Magnitude,
		#snapshot.Rocks
	)
end

-- The input and frame time rounded to what a recording stores.
function Replay.Quantize(input: RunInput.RunInput, dt: number): (RunInput.RunInput, number)
	return table.freeze({
		Move = Vector2.new(round(input.Move.X, MOVE_SCALE), round(input.Move.Y, MOVE_SCALE)),
		MoveStrength = round(input.MoveStrength, MOVE_SCALE),
		BoostPressed = input.BoostPressed,
		BoostHeld = input.BoostHeld,
		Brake = input.Brake,
	}),
		round(dt, DT_SCALE)
end

local function toFrame(input: RunInput.RunInput, dt: number): Frame
	local flags = (if input.BoostPressed then 1 else 0)
		+ (if input.BoostHeld then 2 else 0)
		+ (if input.Brake then 4 else 0)
	return { dt, input.Move.X, input.Move.Y, input.MoveStrength, flags }
end

local function fromFrame(frame: Frame): (RunInput.RunInput, number)
	local flags = frame[5]
	return table.freeze({
		Move = Vector2.new(frame[2], frame[3]),
		MoveStrength = frame[4],
		BoostPressed = flags % 2 == 1,
		BoostHeld = math.floor(flags / 2) % 2 == 1,
		Brake = math.floor(flags / 4) % 2 == 1,
	}),
		frame[1]
end

local Recorder = {}
Recorder.__index = Recorder

export type Recorder = typeof(setmetatable({} :: { _seed: number, _frames: { Frame } }, Recorder))

function Recorder.new(seed: number): Recorder
	return setmetatable({ _seed = seed, _frames = {} }, Recorder)
end

-- Records a frame and returns the exact input and dt to step the Run with.
function Recorder.Record(self: Recorder, input: RunInput.RunInput, dt: number): (RunInput.RunInput, number)
	local quantized, step = Replay.Quantize(input, dt)
	table.insert(self._frames, toFrame(quantized, step))
	return quantized, step
end

-- The recording so far, with the event log the run produced and the run's summary now.
function Recorder.Finish(self: Recorder, events: { string }, run: Run.Run): Recording
	return {
		Seed = self._seed,
		Frames = table.clone(self._frames),
		Events = table.clone(events),
		Final = Replay.Summary(run),
	}
end

Replay.Recorder = Recorder

-- Plays a recording on a fresh Run with its seed. Returns the event log it produces and its summary at the end.
function Replay.Play(recording: Recording): ({ string }, string)
	local run = Run.new({ Seed = recording.Seed })
	local log = Replay.Log(run)
	for _, frame in recording.Frames do
		run:Step(fromFrame(frame))
	end
	local final = Replay.Summary(run)
	run:Destroy()
	return log, final
end

-- The recording as the source of a Luau module (`return { ... }`), to save under tests/Replays.
function Replay.Encode(recording: Recording): string
	local lines = { "-- A recorded Run: replaying its frames on its seed must give exactly these events.", "return {" }
	table.insert(lines, `\tSeed = {string.format("%d", recording.Seed)},`)
	table.insert(lines, "\tFrames = {")
	for _, frame in recording.Frames do
		table.insert(
			lines,
			string.format("\t\t{ %.6f, %.4f, %.4f, %.4f, %d },", frame[1], frame[2], frame[3], frame[4], frame[5])
		)
	end
	table.insert(lines, "\t},")
	table.insert(lines, "\tEvents = {")
	for _, event in recording.Events do
		table.insert(lines, `\t\t{string.format("%q", event)},`)
	end
	table.insert(lines, "\t},")
	table.insert(lines, `\tFinal = {string.format("%q", recording.Final)},`)
	table.insert(lines, "}")
	return table.concat(lines, "\n")
end

return table.freeze(Replay)
