--!strict
--[[
	Server entry point. The game runs on the client (see StarterPlayerScripts.Client),
	so the server stays thin. Later milestones add save data (M5) here.

	Voice chat is disabled in VoiceChatService; we also strip any AudioDeviceInput
	instances created for players so voice is never active in a session.
]]

local Players = game:GetService("Players")

local function stripVoice(player: Player)
	for _, child in player:GetChildren() do
		if child:IsA("AudioDeviceInput") then
			child.Active = false
			child.Muted = true
			child:Destroy()
		end
	end
	player.ChildAdded:Connect(function(child: Instance)
		if child:IsA("AudioDeviceInput") then
			child.Active = false
			child.Muted = true
			child:Destroy()
		end
	end)
end

Players.PlayerAdded:Connect(stripVoice)
for _, player in Players:GetPlayers() do
	stripVoice(player)
end
