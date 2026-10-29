--!strict
--[[
	Device: sets up the screen for play.

	Landscape only, and none of Roblox's default touch controls, chat, backpack,
	player list or emotes, so nothing covers the arena. Roblox's top bar (the
	menu button) always stays; the HUD keeps clear of it.
]]

local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")

local HIDDEN = {
	Enum.CoreGuiType.Chat,
	Enum.CoreGuiType.Backpack,
	Enum.CoreGuiType.PlayerList,
	Enum.CoreGuiType.EmotesMenu,
	Enum.CoreGuiType.Health,
}

local Device = {}

function Device.Setup(playerGui: PlayerGui)
	StarterGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
	playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
	GuiService.TouchControlsEnabled = false

	-- Core GUI may not be ready the moment the client starts, so retry a few times.
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				for _, kind in HIDDEN do
					StarterGui:SetCoreGuiEnabled(kind, false)
				end
			end)
			if ok then
				return
			end
			task.wait(0.5)
		end
	end)
end

return table.freeze(Device)
