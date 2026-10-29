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
	Also in Studio, T opens the live tuning panel (see Dev/TuningPanel).

	In Studio, and for the experience's owner on any device, a dev bar switches
	the zoom between the two candidates (#18) and shows the style tile (#17).
	The game is paused while the tile shows.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local KngChak = ReplicatedStorage.KngChak
local GameEvents = require(KngChak.GameEvents)
local Replay = require(KngChak.Run.Replay)
local Run = require(KngChak.Run.Run)
local Tuning = require(KngChak.Run.Tuning)

local Callouts = require(script.Parent.UI.Callouts)
local CameraView = require(script.Parent.Views.CameraView)
local DevBar = require(script.Parent.Dev.DevBar)
local Device = require(script.Parent.Device)
local Hud = require(script.Parent.UI.Hud)
local Overlay = require(script.Parent.UI.Overlay)
local PlanetView = require(script.Parent.Views.PlanetView)
local PlayerInput = require(script.Parent.Input.PlayerInput)
local RingsView = require(script.Parent.Views.RingsView)
local RockView = require(script.Parent.Views.RockView)
local ShieldView = require(script.Parent.Views.ShieldView)
local ShipView = require(script.Parent.Views.ShipView)
local Stage = require(script.Parent.Views.Stage)
local StyleTile = require(script.Parent.Dev.StyleTile)
local TuningPanel = require(script.Parent.Dev.TuningPanel)

local DUMP_KEY = Enum.KeyCode.F7 -- Studio only: print the current run's recording
local ZOOMS = { 50, 35 } -- the CamView candidates the phone playtest compares (#18)
local SKY_HALF = Vector2.new(190, 140) -- the sky covers the arena plus a screen's width around it

type Session = {
	run: Run.Run,
	recorder: Replay.Recorder?, -- Studio only, so a long run on a phone doesn't keep every frame
	log: { string },
	folder: Folder,
	rings: RingsView.RingsView,
	rocks: RockView.RockView,
	shield: ShieldView.ShieldView,
	ship: ShipView.ShipView,
}

type State = "Start" | "Playing" | "Over"

-- The tuning panel's overrides with the dev bar's zoom on top.
local function combine(panel: Tuning.Overrides?, zoom: number?): Tuning.Overrides?
	if not zoom then
		return panel
	end
	local out: Tuning.Overrides = {}
	if panel then
		for section, values in panel do
			out[section] = table.clone(values)
		end
	end
	local arena: { [string]: any } = out.Arena or {}
	arena.CamView = zoom
	out.Arena = arena
	return out
end

-- A new Run and its views, with the given tuning overrides (if any).
-- The seed is the only randomness the Run gets; it's picked here, outside it.
local function newSession(overrides: Tuning.Overrides?): Session
	local folder = Instance.new("Folder")
	folder.Name = "Arena"
	folder.Parent = workspace

	local seed = Random.new():NextInteger(1, 2 ^ 31 - 2)
	local run = Run.new({ Seed = seed, Tuning = overrides })
	GameEvents.Follow(run.Events)

	PlanetView.new(folder)
	return {
		run = run,
		recorder = if RunService:IsStudio() then Replay.Recorder.new(seed) else nil,
		log = Replay.Log(run),
		folder = folder,
		rings = RingsView.new(folder),
		rocks = RockView.new(folder),
		shield = ShieldView.new(folder),
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
	Stage.Light()
	Stage.Sky(workspace, Vector2.zero, SKY_HALF)
	local hud = Hud.new(playerGui)
	local callouts = Callouts.new(playerGui)
	callouts:Listen(GameEvents)
	local overlay = Overlay.new(playerGui)
	local controls = PlayerInput.new(playerGui)
	local camera = CameraView.new()

	local panelOverrides: Tuning.Overrides? = nil
	local zoom: number? = nil -- the dev bar's CamView, or nil for the data's
	local function overrides(): Tuning.Overrides?
		return combine(panelOverrides, zoom)
	end
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
		session = newSession(overrides())
		snapshot = session.run:Snapshot()
		play()
	end

	if RunService:IsStudio() then
		TuningPanel.new(playerGui, function(changes: Tuning.Overrides)
			panelOverrides = changes
			session.run:SetTuning(overrides())
		end)
		UserInputService.InputBegan:Connect(function(input: InputObject)
			local recorder = session.recorder
			if input.KeyCode == DUMP_KEY and recorder then
				local recording = recorder:Finish(session.log, session.run)
				print(`[Replay] seed {recording.Seed}, {#recording.Frames} frames, {#recording.Events} events:`)
				if panelOverrides and next(panelOverrides) then
					warn("[Replay] the tuning panel changed values during this run, so it won't replay exactly")
				end
				print(Replay.Encode(recording))
			end
		end)
	end

	local tile: StyleTile.StyleTile? = nil
	local showingTile = false
	if DevBar.IsAllowed() then
		DevBar.new(playerGui, {
			{
				name = "Zoom",
				label = function()
					return `Zoom {zoom or session.run:GetTuning().Arena.CamView}`
				end,
				onClick = function()
					local current = zoom or session.run:GetTuning().Arena.CamView
					local index = table.find(ZOOMS, current) or 0
					zoom = ZOOMS[index % #ZOOMS + 1]
					session.run:SetTuning(overrides())
				end,
			},
			{
				name = "StyleTile",
				label = function()
					return if showingTile then "Back to game" else "Style tile"
				end,
				onClick = function()
					showingTile = not showingTile
					local shown = tile or StyleTile.new()
					tile = shown
					if showingTile then
						shown:Show()
					else
						shown:Hide()
					end
					hud:SetVisible(state == "Playing" and not showingTile)
					overlay:SetSuppressed(showingTile)
					controls:Reset()
				end,
			},
		})
	end

	hud:SetVisible(false)
	overlay:Show("KNG CHAK", "Defend the planet.\nTap to start", play)

	RunService.RenderStepped:Connect(function(dt: number)
		if state == "Playing" and not showingTile then
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
		if showingTile and tile then
			camera:LookAt(tile.Focus, arena)
		else
			camera:Update(snapshot.Ship.Position, arena, dt)
		end
		session.rings:Update(snapshot.Ship, arena)
		session.ship:Update(snapshot.Ship)
		session.rocks:Update(snapshot.Rocks)
		session.shield:Update(snapshot.PlanetShield, snapshot.PlanetMaxShield, arena)
		hud:Update(snapshot)
	end)
end
