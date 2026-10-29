--!strict
--[[
	Game: the game flow on this client, and the Run it plays.

	Flow: Start (tap to start) -> Playing -> Over (planet lost: tap to play again)
	-> Playing with a fresh Run, as often as you like, without stopping play mode.

	Each Run comes with its own views in a fresh Arena folder; a restart throws
	both away. Each frame the input adapter turns the player's controls into the
	Run's input, the Run steps, then the views and HUD read its snapshot.
	GameEvents follows the current Run, so anything listening there hears it.

	Input reaches the Run through a replay recorder, rounded the way recordings
	store it. In Studio, F7 prints the current run's seed and recording to Output
	as a Luau module: save it under tests/Replays to replay the run exactly.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local KngChak = ReplicatedStorage.KngChak
local GameEvents = require(KngChak.GameEvents)
local Replay = require(KngChak.Run.Replay)
local Run = require(KngChak.Run.Run)

local CameraView = require(script.Parent.Views.CameraView)
local Device = require(script.Parent.Device)
local Hud = require(script.Parent.UI.Hud)
local Overlay = require(script.Parent.UI.Overlay)
local PlanetView = require(script.Parent.Views.PlanetView)
local PlayerInput = require(script.Parent.Input.PlayerInput)
local RingsView = require(script.Parent.Views.RingsView)
local RockView = require(script.Parent.Views.RockView)
local ShipView = require(script.Parent.Views.ShipView)

local DUMP_KEY = Enum.KeyCode.F7 -- Studio only: print the current run's recording

type Session = {
	run: Run.Run,
	recorder: Replay.Recorder?, -- Studio only, so a long run on a phone doesn't keep every frame
	log: { string },
	folder: Folder,
	rings: RingsView.RingsView,
	rocks: RockView.RockView,
	ship: ShipView.ShipView,
}

type State = "Start" | "Playing" | "Over"

-- A new Run and its views. The seed is the only randomness the Run gets; it's picked here, outside it.
local function newSession(): Session
	local folder = Instance.new("Folder")
	folder.Name = "Arena"
	folder.Parent = workspace

	local seed = Random.new():NextInteger(1, 2 ^ 31 - 2)
	local run = Run.new({ Seed = seed })
	GameEvents.Follow(run.Events)

	PlanetView.new(folder)
	return {
		run = run,
		recorder = if RunService:IsStudio() then Replay.Recorder.new(seed) else nil,
		log = Replay.Log(run),
		folder = folder,
		rings = RingsView.new(folder),
		rocks = RockView.new(folder),
		ship = ShipView.new(folder),
	}
end

local function endSession(session: Session)
	GameEvents.Follow(nil)
	session.run:Destroy()
	session.folder:Destroy()
end

return function()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	Device.Setup(playerGui)
	local hud = Hud.new(playerGui)
	local overlay = Overlay.new(playerGui)
	local controls = PlayerInput.new(playerGui)
	local camera = CameraView.new()

	local session = newSession()
	local snapshot = session.run:Snapshot()
	local state: State = "Start"

	local function play()
		controls:Reset()
		state = "Playing"
		overlay:Hide()
		hud:SetVisible(true)
	end

	local function restart()
		endSession(session)
		session = newSession()
		snapshot = session.run:Snapshot()
		play()
	end

	if RunService:IsStudio() then
		UserInputService.InputBegan:Connect(function(input: InputObject)
			local recorder = session.recorder
			if input.KeyCode == DUMP_KEY and recorder then
				local recording = recorder:Finish(session.log, session.run)
				print(`[Replay] seed {recording.Seed}, {#recording.Frames} frames, {#recording.Events} events:`)
				print(Replay.Encode(recording))
			end
		end)
	end

	hud:SetVisible(false)
	overlay:Show("KNG CHAK", "Defend the planet.\nTap to start", play)

	RunService.RenderStepped:Connect(function(dt: number)
		if state == "Playing" then
			local input = controls:Read(snapshot.Ship.Position)
			local recorder = session.recorder
			if recorder then
				session.run:Step(recorder:Record(input, dt))
			else
				session.run:Step(Replay.Quantize(input, dt))
			end
		end
		snapshot = session.run:Snapshot()

		if state == "Playing" and snapshot.Phase == "Over" then
			state = "Over"
			hud:SetVisible(false)
			overlay:Show(
				"PLANET LOST",
				`Wave {snapshot.Wave} · Score {math.floor(snapshot.Score)}\nTap to play again`,
				restart
			)
		end

		local arena = session.run:GetTuning().Arena
		camera:Update(snapshot.Ship.Position, arena, dt)
		session.rings:Update(snapshot.Ship.Position, arena)
		session.ship:Update(snapshot.Ship)
		session.rocks:Update(snapshot.Rocks)
		hud:Update(snapshot)
	end)
end
