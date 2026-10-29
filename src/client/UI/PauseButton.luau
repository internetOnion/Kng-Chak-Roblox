--!strict
--[[
	PauseButton: a small round button in the top-left corner, under the HP.

	    local pause = PauseButton.new(playerGui, function() ... end)
	    pause:SetSkip(function() ... end) -- a Skip button beside it (nil hides it)

	Esc or P on a keyboard presses it too, even while the pause screen hides it. It keeps to Roblox's safe area, clear
	of the top bar, and because it's a GUI button, a thumb on it never boosts.
]]

local UserInputService = game:GetService("UserInputService")

local Fonts = require(script.Parent.Fonts)

local SIZE = 44
local KEYS = { Enum.KeyCode.Escape, Enum.KeyCode.P }

local PauseButton = {}
PauseButton.__index = PauseButton

export type PauseButton = typeof(setmetatable(
	{} :: { _gui: ScreenGui, _skip: TextButton, _onSkip: (() -> ())? },
	PauseButton
))

local function pill(name: string, text: string, width: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(width, SIZE)
	button.BackgroundColor3 = Color3.fromHex("#1b1a5c")
	button.BackgroundTransparency = 0.25
	button.FontFace = Fonts.TextBold
	button.TextSize = 22
	button.TextColor3 = Color3.fromHex("#ffffff")
	button.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	return button
end

function PauseButton.new(parent: Instance, onPress: () -> ()): PauseButton
	local gui = Instance.new("ScreenGui")
	gui.Name = "Pause"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local button = pill("Pause", "II", SIZE)
	button.Position = UDim2.fromOffset(16, 56) -- under the HP readout
	button.Activated:Connect(onPress)
	button.Parent = gui

	local skip = pill("Skip", "SKIP ▶", 110)
	skip.Position = UDim2.fromOffset(16 + SIZE + 10, 56)
	skip.Visible = false
	skip.Parent = gui
	local self = setmetatable({ _gui = gui, _skip = skip, _onSkip = nil :: (() -> ())? }, PauseButton)
	skip.Activated:Connect(function()
		local onSkip = self._onSkip
		if onSkip then
			onSkip()
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		-- Esc also opens Roblox's own menu, which marks it processed; pausing then is still right
		if table.find(KEYS, input.KeyCode) and (not processed or input.KeyCode == Enum.KeyCode.Escape) then
			onPress()
		end
	end)
	gui.Parent = parent
	return self
end

function PauseButton.SetSkip(self: PauseButton, onSkip: (() -> ())?)
	self._onSkip = onSkip
	self._skip.Visible = onSkip ~= nil
end

function PauseButton.SetVisible(self: PauseButton, visible: boolean)
	self._gui.Enabled = visible
end

return PauseButton
