--# selene: allow(incorrect_standard_library_use)
--[[
	Records the replay fixture: `lune run record-replay` from the repo root.

	A tiny bot plays a Run for a while (it flies at the nearest rock and boosts
	when close), through the same Recorder the live game uses, with a frame rate
	that wobbles like a real device's. The recording and the event log it produced
	are written to tests/Replays/Bot.luau, which tests/Run/Replay.spec.luau replays.
	Re-run this after a change that's meant to change how a run plays out.
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

-- The same Roblox globals the test runner installs.
task = require("@lune/task")
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3
Color3 = roblox.Color3
CFrame = roblox.CFrame
Enum = roblox.Enum

local Replay = require("../src/shared/Run/Replay")
local Run = require("../src/shared/Run/Run")
local RunInput = require("../src/shared/Run/RunInput")

local SEED = 20261029
local SECONDS = 20
local OUT = "tests/Replays/Bot.luau"

local run = Run.new({ Seed = SEED })
local log = Replay.Log(run)
local recorder = Replay.Recorder.new(SEED)

local elapsed, frame = 0, 0
while elapsed < SECONDS do
	frame += 1
	local dt = 1 / 30 + 0.004 * math.sin(frame * 0.7) -- a wobbly ~30 fps
	local snapshot = run:Snapshot()
	local ship = snapshot.Ship

	local nearest, best = nil, math.huge
	for _, rock in snapshot.Rocks do
		local distance = (rock.Position - ship.Position).Magnitude
		if distance < best then
			nearest, best = rock, distance
		end
	end

	local input = RunInput.Idle
	if nearest then
		local close = best < 9 and ship.Fuel >= 30 and not ship.IsBoosting
		input = RunInput.steer(nearest.Position - ship.Position, math.clamp(best / 15, 0.2, 1), close, close)
	end
	run:Step(recorder:Record(input, dt))
	elapsed += dt
end

fs.writeFile(OUT, Replay.Encode(recorder:Finish(log, run)) .. "\n")
print(`Wrote {OUT}: {frame} frames, {#log} events`)
