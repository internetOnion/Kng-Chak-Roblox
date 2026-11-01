--!strict
--[[
	Game: the game flow on this client, and the Run it plays.

	Flow: Start (tap to start) -> the Controls & Core Moves card, the first time ->
	an emergency call (12 waves, an upgrade pick after each, then the Inferno) ->
	results, lost or won (tap to play again) -> a fresh call, as often as you like,
	without stopping play mode. The pause button (or Esc, or Roblox's own menu
	opening) pauses the call; both Start and Pause include a Controls button to
	reopen the visual controls guide anytime, and a music toggle (also beside Pause
	during play, or M on keyboard) turns the soundtrack off or on. Whether controls
	have been seen or music muted lasts for this visit until the saved profile (#50)
	keeps it.

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
local BossView = require(script.Parent.Views.BossView)
local Callouts = require(script.Parent.UI.Callouts)
local CameraView = require(script.Parent.Views.CameraView)
local Chevron = require(script.Parent.UI.Chevron)
local ControlsPanel = require(script.Parent.UI.ControlsPanel)
local DevBar = require(script.Parent.Dev.DevBar)
local Device = require(script.Parent.Device)
local FuelArc = require(script.Parent.UI.FuelArc)
local Haptics = require(script.Parent.Input.Haptics)
local Hud = require(script.Parent.UI.Hud)
local MusicButton = require(script.Parent.UI.MusicButton)
local MusicPlayer = require(script.Parent.Audio.MusicPlayer)
local Outlines = require(script.Parent.Views.Outlines)
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
local VfxView = require(script.Parent.Views.VfxView)

local DUMP_KEY = Enum.KeyCode.F7 -- Studio only: print the current run's recording
local ZOOMS = { 50, 35 } -- the CamView candidates the phone playtest compares (#18)
local SKY_HALF = Vector2.new(190, 140) -- the sky covers the arena plus a screen's width around it

type Session = {
	run: Run.Run,
	recorder: Replay.Recorder?, -- Studio only, so a long run on a phone doesn't keep every frame
	log: { string },
	folder: Folder,
	planet: PlanetView.PlanetView,
	boss: BossView.BossView,
	rings: RingsView.RingsView,
	rocks: RockView.RockView,
	shield: ShieldView.ShieldView,
	ship: ShipView.ShipView,
	threats: ThreatView.ThreatView,
	vfx: VfxView.VfxView,
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

-- A new Run and its views, with the given tuning overrides (if any).
-- The seed is the only randomness the Run gets; it's picked here, outside it.
local function newSession(overrides: Tuning.Overrides?, startWave: number?): Session
	local folder = Instance.new("Folder")
	folder.Name = "Arena"
	folder.Parent = workspace

	local seed = Random.new():NextInteger(1, 2 ^ 31 - 2)
	local run = Run.new({ Seed = seed, Tuning = overrides, StartWave = startWave })
	GameEvents.Follow(run.Events)

	local planet = PlanetView.new(folder)
	local ship = ShipView.new(folder)
	ship:Listen(run.Events)
	local vfx = VfxView.new(folder)
	vfx:Listen(run.Events)
	return {
		run = run,
		recorder = if RunService:IsStudio() and not startWave then Replay.Recorder.new(seed) else nil,
		log = Replay.Log(run),
		folder = folder,
		planet = planet,
		boss = BossView.new(folder),
		rings = RingsView.new(folder),
		rocks = RockView.new(folder),
		shield = ShieldView.new(folder),
		ship = ship,
		threats = ThreatView.new(folder),
		vfx = vfx,
	}
end

local function endSession(session: Session)
	GameEvents.Follow(nil)
	session.planet:Destroy()
	session.ship:Destroy()
	session.rocks:Destroy()
	session.boss:Destroy()
	session.vfx:Destroy()
	session.run:Destroy()
	session.folder:Destroy()
end

return function()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	Device.Setup(playerGui)
	Stage.Light()
	local sky = Stage.Sky(workspace, Vector2.zero, SKY_HALF)
	local hud = Hud.new(playerGui)
	local callouts = Callouts.new(playerGui)
	callouts:Listen(GameEvents)
	local banner = Banner.new(playerGui)
	banner:Listen(GameEvents)
	local radar = Radar.new(playerGui)
	local chevron = Chevron.new(playerGui)
	local fuelArc = FuelArc.new(playerGui)
	fuelArc:Listen(GameEvents)
	local sounds = SoundPlayer.new()
	sounds:Listen(GameEvents)
	local music = MusicPlayer.new()
	local haptics = Haptics.new(playerGui)
	local musicButton: MusicButton.MusicButton
	local overlay: Overlay.Overlay
	local function toggleMusic()
		local muted = not music:IsMuted()
		music:SetMuted(muted)
		musicButton:SetMuted(muted)
		overlay:SetMusicMuted(muted)
	end
	haptics:Listen(GameEvents)
	overlay = Overlay.new(playerGui, function()
		sounds:Play("UiClick")
	end, toggleMusic)
	musicButton = MusicButton.new(playerGui, function()
		sounds:Play("UiClick")
		toggleMusic()
	end)
	local controlsPanel = ControlsPanel.new(playerGui)
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
	local seenControls = false -- whether this player has seen the controls card (this visit)
	local pauseButton: PauseButton.PauseButton

	-- everything drawn over the arena during play
	local function showPlayUi(visible: boolean)
		hud:SetVisible(visible)
		radar:SetVisible(visible)
		chevron:SetVisible(visible)
		fuelArc:SetVisible(visible)
		pauseButton:SetVisible(visible)
		musicButton:SetVisible(visible)
		banner:SetVisible(visible)
		callouts:SetVisible(visible)
	end

	local function begin(startWave: number?)
		endSession(session)
		banner:Clear()
		callouts:Clear()
		controlsPanel:Hide()
		session = newSession(overrides(), startWave)
		snapshot = session.run:Snapshot()
		controls:Reset()
		state = "Playing"
		overlay:Hide()
		showPlayUi(true)
	end

	local function startCall()
		begin()
	end

	local showStart: () -> ()
	local showPause: () -> ()

	local function returnToTitle()
		endSession(session)
		banner:Clear()
		callouts:Clear()
		controlsPanel:Hide()
		session = newSession(overrides())
		snapshot = session.run:Snapshot()
		controls:Reset()
		showStart()
	end

	local function resume()
		if state ~= "Paused" then
			return
		end
		controlsPanel:Hide()
		state = "Playing"
		session.run:SetPaused(false)
		controls:Reset()
		overlay:Hide()
		showPlayUi(true)
	end

	function showPause()
		overlay:ShowPause({
			Wave = snapshot.Wave,
			LastWave = WaveConfig.LastWave,
			IsBoss = snapshot.Boss ~= nil,
			PlanetHp = snapshot.PlanetHp,
			PlanetMaxHp = snapshot.PlanetMaxHp,
			PlanetShield = snapshot.PlanetShield,
			Score = snapshot.Score,
		}, {
			OnResume = resume,
			OnControls = function()
				overlay:Hide()
				controlsPanel:Show("GOT IT", showPause)
			end,
			OnRestart = startCall,
			OnTitle = returnToTitle,
		})
	end

	local function pause()
		if state ~= "Playing" then
			return
		end
		state = "Paused"
		session.run:SetPaused(true)
		showPlayUi(false)
		showPause()
	end

	local function toggle()
		sounds:Play("UiClick")
		if controlsPanel:IsOpen() then
			controlsPanel:Close()
		elseif state == "Paused" then
			resume()
		elseif state == "Playing" then
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

	function showStart()
		state = "Start"
		showPlayUi(false)
		local function onPrimaryTap()
			if seenControls then
				startCall()
			else
				overlay:Hide()
				controlsPanel:Show("START CALL", function()
					seenControls = true
					startCall()
				end)
			end
		end
		local function onControlsTap()
			overlay:Hide()
			controlsPanel:Show("GOT IT", function()
				seenControls = true
				showStart()
			end)
		end
		overlay:ShowStart(onPrimaryTap, onControlsTap)
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
						session.folder.Parent = nil
						shown:Show()
					else
						shown:Hide()
						session.folder.Parent = workspace
					end
					showPlayUi(state == "Playing" and not showingTile)
					overlay:SetSuppressed(showingTile)
					controlsPanel:SetSuppressed(showingTile)
					controls:Reset()
				end,
			},
			{
				name = "Inferno",
				label = function()
					return "Inferno"
				end,
				onClick = function()
					if showingTile and tile then
						showingTile = false
						tile:Hide()
						overlay:SetSuppressed(false)
						controlsPanel:SetSuppressed(false)
					end
					begin(WaveConfig.LastWave + 1) -- past the last wave: the Inferno at once
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
			state = "Finished"
			showPlayUi(false)
			local summary = session.run:Summary()
			local function showResults()
				overlay:ShowResults(summary, WaveConfig.LastWave, {
					OnPlayAgain = startCall,
					OnControls = function()
						overlay:Hide()
						controlsPanel:Show("GOT IT", showResults)
					end,
					OnTitle = returnToTitle,
				})
			end
			showResults()
		end

		local now = os.clock()
		local tuning = session.run:GetTuning()
		local arena = tuning.Arena
		local playing = state == "Playing" and not showingTile
		if showingTile and tile then
			tile:Update(dt)
			camera:LookAt(tile.Focus, arena)
		elseif state == "Start" then
			camera:LookAt(Vector2.new(math.sin(now * 0.25) * 4, 0), arena)
		else
			camera:Update(snapshot.Ship.Position, arena, dt)
		end
		local focus, viewHalf = camera:View()
		if not showingTile then
			sky:Update(focus)
			if state ~= "Paused" then
				session.planet:Update(dt)
			end
		end
		local coneDeg = if snapshot.Ship.IsInOrbit then tuning.Ship.FlareConeDeg else tuning.Ship.PushConeDeg
		session.rings:Update(snapshot.Ship, arena)
		session.ship:Update(snapshot.Ship, dt, playing, coneDeg)
		session.rocks:Update(snapshot.Rocks)
		session.boss:Update(snapshot.Boss, tuning.Inferno)
		session.shield:Update(snapshot.PlanetShield, snapshot.PlanetMaxShield, arena)
		session.threats:Update(snapshot, arena, now)
		session.vfx:Update(snapshot, tuning, dt, playing)
		Outlines.Step(arena.CamTilt)
		if not showingTile then
			radar:Update(snapshot, arena, focus, viewHalf, now)
			chevron:Update(snapshot, arena.PlanetRadius, now)
			fuelArc:Update(snapshot, tuning.Ship, now)
			callouts:Update(snapshot, now)
		end
		hud:Update(snapshot)
		controlsPanel:Update(now)
		local inArena = playing and snapshot.Phase ~= "UpgradePick"
		cards:Update(snapshot, playing, now, tuning.Waves.SurgeHeal)
		banner:SetVisible(inArena) -- the cards take the screen
		callouts:SetVisible(inArena)
		sounds:UpdateEngine(snapshot.Ship, playing, dt)
		sounds:UpdateThreat(snapshot, arena.PlanetRadius, playing, now)
		music:Update(snapshot, state, dt)
	end)
end
