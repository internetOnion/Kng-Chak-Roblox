--!strict
--[[
	DevBar: a few buttons for playtests, for the developer only.

	It shows in Studio and, in the published experience, only for its owner, so
	the phone playtest can switch the zoom and look at the style tile on a real
	phone. Players never see it.

	    if DevBar.IsAllowed() then
	        DevBar.new(playerGui, {
	            { name = "Zoom", label = function() return `Zoom {zoom}` end, onClick = nextZoom },
	        })
	    end
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Fonts = require(script.Parent.Parent.UI.Fonts)

export type Button = {
	name: string, -- the button's instance name
	label: () -> string, -- read again after every click
	onClick: () -> (),
}

local DevBar = {}

-- True in Studio, and in the published experience for the user who owns it.
function DevBar.IsAllowed(): boolean
	if RunService:IsStudio() then
		return true
	end
	local player = Players.LocalPlayer
	return game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId
end

function DevBar.new(parent: Instance, buttons: { Button })
	local gui = Instance.new("ScreenGui")
	gui.Name = "DevBar"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30 -- above the overlay, so it works on the start and game-over screens too
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -8)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.Size = UDim2.fromOffset(0, 40)
	bar.BackgroundTransparency = 1
	bar.Parent = gui
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, 8)
	list.Parent = bar

	local refreshers: { () -> () } = {}
	local function refresh()
		for _, update in refreshers do
			update()
		end
	end

	for _, spec in buttons do
		local button = Instance.new("TextButton")
		button.Name = spec.name
		button.AutomaticSize = Enum.AutomaticSize.X
		button.Size = UDim2.fromOffset(0, 40)
		button.BackgroundColor3 = Color3.fromHex("#14133d")
		button.BackgroundTransparency = 0.2
		button.TextColor3 = Color3.fromHex("#ffe066")
		button.FontFace = Fonts.TextBold
		button.TextSize = 18
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 14)
		pad.PaddingRight = UDim.new(0, 14)
		pad.Parent = button
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = button
		button.Parent = bar
		table.insert(refreshers, function()
			button.Text = spec.label()
		end)
		button.Activated:Connect(function()
			spec.onClick()
			refresh()
		end)
	end
	refresh()
	gui.Parent = parent
end

return table.freeze(DevBar)
