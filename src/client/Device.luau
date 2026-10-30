--!strict
--[[
	Device: sets up the screen for play.

	Forces horizontal orientation (LandscapeSensor, with an immediate LandscapeLeft
	kick if a phone joins in Portrait) and hides Roblox's default touch controls,
	chat, voice/camera self-view, captures, backpack, player list, emotes and health
	bar so nothing covers the arena. Roblox's top-left menu button stays; the HUD
	keeps clear of it.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local HIDDEN: { Enum.CoreGuiType } = {
	Enum.CoreGuiType.Chat,
	Enum.CoreGuiType.Backpack,
	Enum.CoreGuiType.PlayerList,
	Enum.CoreGuiType.EmotesMenu,
	Enum.CoreGuiType.Health,
	Enum.CoreGuiType.SelfView,
	Enum.CoreGuiType.Captures,
}

local Device = {}
local configured = false

local function forceHorizontal(playerGui: PlayerGui)
	StarterGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
	if playerGui.CurrentScreenOrientation == Enum.ScreenOrientation.Portrait then
		-- Kick iOS/Android out of portrait immediately, then allow either horizontal side.
		playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeLeft
		task.delay(0.15, function()
			playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
		end)
	else
		playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
	end
end

local function mutePlayerVoice(player: Player)
	for _, child in player:GetChildren() do
		if child:IsA("AudioDeviceInput") then
			child.Active = false
			child.Muted = true
		end
	end
	player.ChildAdded:Connect(function(child: Instance)
		if child:IsA("AudioDeviceInput") then
			child.Active = false
			child.Muted = true
		end
	end)
end

function Device.Setup(playerGui: PlayerGui)
	forceHorizontal(playerGui)
	if configured then
		return
	end
	configured = true
	playerGui:GetPropertyChangedSignal("CurrentScreenOrientation"):Connect(function()
		if playerGui.CurrentScreenOrientation == Enum.ScreenOrientation.Portrait then
			forceHorizontal(playerGui)
		end
	end)

	GuiService.TouchControlsEnabled = false

	local localPlayer = Players.LocalPlayer
	if localPlayer then
		mutePlayerVoice(localPlayer)
	end

	-- Core GUI may not be ready the moment the client starts, so retry a few times.
	task.spawn(function()
		for _ = 1, 10 do
			local allReady = true
			for _, kind in HIDDEN do
				local ok = pcall(function()
					StarterGui:SetCoreGuiEnabled(kind, false)
				end)
				if not ok then
					allReady = false
				end
			end
			if allReady then
				return
			end
			task.wait(0.5)
		end
	end)
end

return table.freeze(Device)
