--!strict
--[[
	Game: the game flow on this client, and the Run it plays.

	Flow: Start (tap to start) -> Playing -> Over (planet lost: tap to play again)
	-> Playing with a fresh Run, as often as you like, without stopping play mode.

	Each Run comes with its own views in a fresh Arena folder; a restart throws
	both away. Each frame the input adapter turns the player's controls into the
	Run's input, the Run steps, then the views and HUD read its snapshot.
	GameEvents follows the current Run, so anything listening there hears it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local KngChak = ReplicatedStorage.KngChak
local GameEvents = require(KngChak.GameEvents)
local Run = require(KngChak.Run.Run)

local CameraView = require(script.Parent.Views.CameraView)
local Hud = require(script.Parent.UI.Hud)
local MouseInput = require(script.Parent.Input.MouseInput)
local Overlay = require(script.Parent.UI.Overlay)
local PlanetView = require(script.Parent.Views.PlanetView)
local RingsView = require(script.Parent.Views.RingsView)
local RockView = require(script.Parent.Views.RockView)
local ShipView = require(script.Parent.Views.ShipView)

type Session = {
	run: Run.Run,
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

	local run = Run.new({ Seed = Random.new():NextInteger(1, 2 ^ 31 - 2) })
	GameEvents.Follow(run.Events)

	PlanetView.new(folder)
	return {
		run = run,
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
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local hud = Hud.new(playerGui)
	local overlay = Overlay.new(playerGui)
	local mouse = MouseInput.new()
	local camera = CameraView.new()

	local session = newSession()
	local snapshot = session.run:Snapshot()
	local state: State = "Start"

	local function play()
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

	hud:SetVisible(false)
	overlay:Show("KNG CHAK", "Defend the planet.\nTap to start", play)

	RunService.RenderStepped:Connect(function(dt: number)
		if state == "Playing" then
			session.run:Step(mouse:Read(snapshot.Ship.Position), dt)
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
