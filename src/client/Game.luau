--!strict
--[[
	Game: the game flow on this client, and the Run it plays.

	Flow: Start (tap to start) -> the guided first call, the first time -> an
	emergency call (12 waves, an upgrade pick after each, then the Inferno) ->
	results, lost or won (tap to play again) -> a fresh call, as often as you
	like, without stopping play mode. The pause button (or Esc, or Roblox's own
	menu opening) pauses the call; the start screen can replay the guided call
	once it's been done, and the guided call can then be skipped. Whether it's
	been done lasts for this visit only until the saved profile (#50) keeps it.

	Each Run comes with its own views in a fresh Arena folder; a restart throws
	both away. Each frame the input adapter turns the player's controls into the
	Run's input, the Run steps, then the views and HUD read its snapshot.
	GameEvents follows the current Run, so anything listening there hears it.

	Input reaches the Run through a replay recorder, rounded the way recordings
	store it, and upgrade picks are recorded with it. In Studio, F7 prints the
	current run's seed and recording to Output as a Luau module: save it under
	tests/Replays to replay the run exactly. Also in Studio, T opens the live
	tuning panel (see Dev/TuningPanel).

	In Studio, and for the experience's owner on any device, a dev bar switches
	the zoom between the two candidates (#18), shows the style tile (#17) and
	jumps straight to the Inferno. The game is paused while the tile shows.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local KngChak = ReplicatedStorage.KngChak
local GameEvents = require(KngChak.GameEvents)
local Replay = require(KngChak.Run.Replay)
local Run = require(KngChak.Run.Run)
local Tuning = require(KngChak.Run.Tuning)
local WaveConfig = require(KngChak.Data.WaveConfig)

local Banner = require(script.Parent.UI.Banner)
local BeaconView = require(script.Parent.Views.BeaconView)
local BossView = require(script.Parent.Views.BossView)
local Callouts = require(script.Parent.UI.Callouts)
local CameraView = require(script.Parent.Views.CameraView)
local Chevron = require(script.Parent.UI.Chevron)
local DevBar = require(script.Parent.Dev.DevBar)
local Device = require(script.Parent.Device)
local FuelArc = require(script.Parent.UI.FuelArc)
local GhostThumb = require(script.Parent.UI.GhostThumb)
local Hud = require(script.Parent.UI.Hud)
local Overlay = require(script.Parent.UI.Overlay)
local PauseButton = require(script.Parent.UI.PauseButton)
local PlanetView = require(script.Parent.Views.PlanetView)
local PlayerInput = require(script.Parent.Input.PlayerInput)
local Radar = require(script.Parent.UI.Radar)
local RingsView = require(script.Parent.Views.RingsView)
local RockView = require(script.Parent.Views.RockView)
local ShieldView = require(script.Parent.Views.ShieldView)
local ShipView = require(script.Parent.Views.ShipView)
local SoundPlayer = require(script.Parent.Audio.SoundPlayer)
local Stage = require(script.Parent.Views.Stage)
local StyleTile = require(script.Parent.Dev.StyleTile)
local ThreatView = require(script.Parent.Views.ThreatView)
local TuningPanel = require(script.Parent.Dev.TuningPanel)
local UpgradeCards = require(script.Parent.UI.UpgradeCards)

local DUMP_KEY = Enum.KeyCode.F7 -- Studio only: print the current run's recording
local ZOOMS = { 50, 35 } -- the CamView candidates the phone playtest compares (#18)
local SKY_HALF = Vector2.new(190, 140) -- the sky covers the arena plus a screen's width around it
local WON = Color3.fromHex("#5ee05e")
local LOST = Color3.fromHex("#ff4d5e")

type Session = {
	run: Run.Run,
	mode: Run.Mode,
	recorder: Replay.Recorder?, -- Studio only, so a long run on a phone doesn't keep every frame
	log: { string },
	folder: Folder,
	beacon: BeaconView.BeaconView,
	boss: BossView.BossView,
	rings: RingsView.RingsView,
	rocks: RockView.RockView,
	shield: ShieldView.ShieldView,
	ship: ShipView.ShipView,
	threats: ThreatView.ThreatView,
}

type State = "Start" | "Playing" | "Paused" | "Finished"

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

-- A new Run in `mode` and its views, with the given tuning overrides (if any).
-- The seed is the only randomness the Run gets; it's picked here, outside it.
local function newSession(mode: Run.Mode, overrides: Tuning.Overrides?, startWave: number?): Session
	local folder = Instance.new("Folder")
	folder.Name = "Arena"
	folder.Parent = workspace

	local seed = Random.new():NextInteger(1, 2 ^ 31 - 2)
	local run = Run.new({ Seed = seed, Mode = mode, Tuning = overrides, StartWave = startWave })
	GameEvents.Follow(run.Events)

	PlanetView.new(folder)
	return {
		run = run,
		mode = mode,
		recorder = if RunService:IsStudio() and not startWave
			then Replay.Recorder.new(seed, if mode == "Call" then nil else mode)
			else nil,
		log = Replay.Log(run),
		folder = folder,
		beacon = BeaconView.new(folder),
		boss = BossView.new(folder),
		rings = RingsView.new(folder),
		rocks = RockView.new(folder),
		shield = ShieldView.new(folder),
		ship = ShipView.new(folder),
		threats = ThreatView.new(folder),
	}
end

local function endSession(session: Session)
	GameEvents.Follow(nil)
	session.run:Destroy()
	session.folder:Destroy()
end

local function clock(seconds: number): string
	return string.format("%d:%02d", seconds // 60, math.floor(seconds % 60))
end

-- The results screen's words for a finished call.
local function results(summary: Run.Summary): (string, string, Color3)
	local reached = if summary.Wave > WaveConfig.LastWave then "the Inferno" else `wave {summary.Wave}`
	local body = `Score {math.floor(summary.Score)} · reached {reached}\n`
		.. `Best combo {summary.BestCombo} · PERFECTs {summary.Perfects} · {clock(summary.Time)}\n`
		.. "Tap to play again"
	if summary.Won then
		return "CALL CLEARED!", body, WON
	end
	return "PLANET LOST", body, LOST
end

return function()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	Device.Setup(playerGui)
	Stage.Light()
	Stage.Sky(workspace, Vector2.zero, SKY_HALF)
	local hud = Hud.new(playerGui)
	local callouts = Callouts.new(playerGui)
	callouts:Listen(GameEvents)
	local banner = Banner.new(playerGui)
	banner:Listen(GameEvents)
	local radar = Radar.new(playerGui)
	local chevron = Chevron.new(playerGui)
	local fuelArc = FuelArc.new(playerGui)
	fuelArc:Listen(GameEvents)
	local ghost = GhostThumb.new(playerGui)
	local sounds = SoundPlayer.new()
	sounds:Listen(GameEvents)
	local overlay = Overlay.new(playerGui)
	local controls = PlayerInput.new(playerGui)
	local camera = CameraView.new()

	local panelOverrides: Tuning.Overrides? = nil
	local zoom: number? = nil -- the dev bar's CamView, or nil for the data's
	local function overrides(): Tuning.Overrides?
		return combine(panelOverrides, zoom)
	end
	local session = newSession("Call")
	local snapshot = session.run:Snapshot()
	local state: State = "Start"
	local guidedDone = false -- whether this player has finished the guided call (this visit)
	local pauseButton: PauseButton.PauseButton

	-- everything drawn over the arena during play
	local function showPlayUi(visible: boolean)
		hud:SetVisible(visible)
		radar:SetVisible(visible)
		chevron:SetVisible(visible)
		fuelArc:SetVisible(visible)
		ghost:SetVisible(visible)
		pauseButton:SetVisible(visible)
	end

	local startCall: () -> ()
	local function begin(mode: Run.Mode, startWave: number?)
		endSession(session)
		-- after the first time the guided call can be skipped
		pauseButton:SetSkip(if mode == "Guided" and guidedDone then startCall else nil)
		banner:Clear()
		session = newSession(mode, overrides(), startWave)
		snapshot = session.run:Snapshot()
		controls:Reset()
		state = "Playing"
		overlay:Hide()
		showPlayUi(true)
	end

	function startCall()
		begin("Call")
	end

	local function startGuided()
		begin("Guided")
	end

	local function resume()
		if state ~= "Paused" then
			return
		end
		state = "Playing"
		session.run:SetPaused(false)
		controls:Reset()
		overlay:Hide()
		showPlayUi(true)
	end

	local function pause()
		if state ~= "Playing" then
			return
		end
		state = "Paused"
		session.run:SetPaused(true)
		showPlayUi(false)
		local restart = if session.mode == "Guided" then "Start wave 1" else "Restart call"
		overlay:Show("PAUSED", "Tap to resume", resume, { Text = restart, OnTap = startCall })
	end

	local function toggle()
		if state == "Paused" then
			resume()
		else
			pause()
		end
	end
	pauseButton = PauseButton.new(playerGui, toggle)
	GuiService.MenuOpened:Connect(pause) -- Roblox's own menu covers the game

	local cards = UpgradeCards.new(playerGui, function(index: number)
		if state ~= "Playing" or snapshot.Phase ~= "UpgradePick" then
			return
		end
		local recorder = session.recorder
		if recorder then
			recorder:Pick(index)
		end
		session.run:PickUpgrade(index)
		controls:Reset()
	end)

	local function showStart()
		state = "Start"
		showPlayUi(false)
		local body = "Defend the planet.\nTap to start"
		if guidedDone then
			overlay:Show("KNG CHAK", body, startCall, { Text = "How to fly", OnTap = startGuided })
		else
			overlay:Show("KNG CHAK", body, startGuided)
		end
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
					showPlayUi(state == "Playing" and not showingTile)
					overlay:SetSuppressed(showingTile)
					controls:Reset()
				end,
			},
			{
				name = "Inferno",
				label = function()
					return "Inferno"
				end,
				onClick = function()
					begin("Call", WaveConfig.LastWave + 1) -- past the last wave: the Inferno at once
				end,
			},
		})
	end

	showStart()

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

		if state == "Playing" and (snapshot.Phase == "Over" or snapshot.Phase == "Won") then
			if session.mode == "Guided" then
				guidedDone = true
				startCall() -- then wave 1 starts
				snapshot = session.run:Snapshot()
			else
				state = "Finished"
				showPlayUi(false)
				local title, body, color = results(session.run:Summary())
				overlay:Show(title, body, startCall, nil, color)
			end
		end

		local tuning = session.run:GetTuning()
		local arena = tuning.Arena
		if showingTile and tile then
			camera:LookAt(tile.Focus, arena)
		else
			camera:Update(snapshot.Ship.Position, arena, dt)
		end
		local now = os.clock()
		session.rings:Update(snapshot.Ship, arena)
		session.ship:Update(snapshot.Ship)
		session.rocks:Update(snapshot.Rocks)
		session.boss:Update(snapshot.Boss, tuning.Inferno)
		session.beacon:Update(snapshot.Guided and snapshot.Guided.Beacon, now)
		session.shield:Update(snapshot.PlanetShield, snapshot.PlanetMaxShield, arena)
		session.threats:Update(snapshot, arena, now)
		if not showingTile then
			local focus, viewHalf = camera:View()
			radar:Update(snapshot, arena, focus, viewHalf, now)
			chevron:Update(snapshot, arena.PlanetRadius, now)
			fuelArc:Update(snapshot, tuning.Ship, now)
			ghost:Update(snapshot, now)
		end
		hud:Update(snapshot)
		local playing = state == "Playing" and not showingTile
		cards:Update(snapshot, playing)
		banner:SetVisible(playing and snapshot.Phase ~= "UpgradePick") -- the cards take the screen
		sounds:UpdateEngine(snapshot.Ship, state == "Playing" and not showingTile, dt)
	end)
end
