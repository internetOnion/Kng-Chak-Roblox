--# selene: allow(incorrect_standard_library_use)
--[[
	Balance report: `lune run balance` from the repo root.

	Plays full emergency calls headless on fixed seeds and prints a Markdown
	report of HP lost and time taken per wave, and how each call ended. Two
	players fly each seed:

	- Pilot: the scripted player in tests/Pilot (push, break, orbit, slingshot)
	- Idle: no input at all, so every rock gets through (the hardest each wave can hit)

	Each takes the first upgrade card on offer. Tests don't use the clock or
	global randomness, so the report only changes when data or rules do.
	It's a report, never a gate: it always exits 0. CI posts it on pull requests
	that touch the shared code or data (.github/workflows/balance.yml).
]]

local roblox = require("@lune/roblox")

-- The same Roblox globals the test runner installs.
task = require("@lune/task")
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3
Color3 = roblox.Color3
CFrame = roblox.CFrame
Enum = roblox.Enum

local Pilot = require("../tests/Pilot")
local Run = require("../src/shared/Run/Run")
local RunInput = require("../src/shared/Run/RunInput")
local WaveConfig = require("../src/shared/Data/WaveConfig")

local SEEDS = { 101, 202, 303 }
local FRAME = 1 / 30
local LIMIT = 40 * 60 -- seconds: a call that hasn't ended by then is cut off

type Player = {
	name: string,
	input: (Run.Snapshot, any) -> RunInput.RunInput,
}

local PLAYERS: { Player } = {
	{ name = "Pilot", input = Pilot.Input },
	{
		name = "Idle",
		input = function()
			return RunInput.Idle
		end,
	},
}

type WaveRow = { wave: string, time: number, hpLost: number, hpEnd: number }

-- Plays one call; returns a row per wave (and one for the Inferno) and how it ended.
local function play(seed: number, player: Player): ({ WaveRow }, string)
	local run = Run.new({ Seed = seed })
	local rows: { WaveRow } = {}
	local current: WaveRow? = nil
	local started = 0
	local function close(t: number)
		if current then
			current.time = t - started
			current.hpEnd = run:Snapshot().PlanetHp
			table.insert(rows, current)
			current = nil
		end
	end
	local t = 0
	run.Events.WaveStarted:Connect(function(wave: number)
		current = { wave = tostring(wave), time = 0, hpLost = 0, hpEnd = 0 }
		started = t
	end)
	run.Events.WaveCleared:Connect(function()
		close(t)
	end)
	run.Events.BossPhaseChanged:Connect(function(phase: number)
		if phase == 1 then
			current = { wave = "Inferno", time = 0, hpLost = 0, hpEnd = 0 }
			started = t
		end
	end)
	local function lose(amount: number)
		if current then
			current.hpLost += amount
		end
	end
	run.Events.PlanetHit:Connect(function(_, damage: number)
		lose(damage)
	end)
	run.Events.BossHit:Connect(lose)

	while t < LIMIT do
		local snapshot = run:Snapshot()
		if snapshot.Phase == "Won" or snapshot.Phase == "Over" then
			break
		elseif snapshot.Phase == "UpgradePick" then
			run:PickUpgrade(1)
		end
		run:Step(player.input(snapshot, run:GetTuning()), FRAME)
		t += FRAME
	end
	close(t)
	local summary = run:Summary()
	local reached = if summary.Wave > WaveConfig.LastWave then "the Inferno" else `wave {summary.Wave}`
	local ending = if summary.Won
		then "won"
		elseif run:Snapshot().Phase == "Over" then `lost on {reached}`
		else "cut off"
	return rows, string.format("%s in %d:%02d, score %d", ending, t // 60, math.floor(t % 60), summary.Score)
end

local lines = {
	"## Balance report",
	"",
	"Full emergency calls on fixed seeds. *HP lost* is the damage that got through in that wave",
	"(the shield soaks it first); *HP after* is the planet's HP when the wave ended.",
	"",
}
for _, player in PLAYERS do
	table.insert(lines, `### {player.name}`)
	table.insert(lines, "")
	for _, seed in SEEDS do
		local rows, ending = play(seed, player)
		table.insert(lines, `**Seed {seed}:** {ending}`)
		table.insert(lines, "")
		table.insert(lines, "| Wave | Time (s) | HP lost | HP after |")
		table.insert(lines, "|---|---:|---:|---:|")
		for _, row in rows do
			table.insert(lines, string.format("| %s | %.0f | %.0f | %.0f |", row.wave, row.time, row.hpLost, row.hpEnd))
		end
		table.insert(lines, "")
	end
end
print(table.concat(lines, "\n"))
