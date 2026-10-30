--!strict
--[[
	PauseButton: a small round button in the top-left corner, under the HP.

	    local pause = PauseButton.new(playerGui, function() ... end)

	Esc or P on a keyboard presses it too, even while the pause screen hides it. It
	keeps to Roblox's safe area, clear of the top bar, and because it's a GUI button,
	a thumb on it never boosts.
]]

local UserInputService = game:GetService("UserInputService")

local SIZE = 44
local KEYS = { Enum.KeyCode.Escape, Enum.KeyCode.P }

local PauseButton = {}
PauseButton.__index = PauseButton

export type PauseButton = typeof(setmetatable({} :: { _gui: ScreenGui }, PauseButton))

local function bar(parent: Instance, xOffset: number)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, xOffset, 0.5, 0)
	frame.Size = UDim2.fromOffset(5, 16)
	frame.BackgroundColor3 = Color3.fromHex("#ffffff")
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	frame.Parent = parent
end

function PauseButton.new(parent: Instance, onPress: () -> ()): PauseButton
	local gui = Instance.new("ScreenGui")
	gui.Name = "Pause"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local button = Instance.new("TextButton")
	button.Name = "Pause"
	button.Position = UDim2.fromOffset(16, 48) -- under the HP readout
	button.Size = UDim2.fromOffset(SIZE, SIZE)
	button.BackgroundColor3 = Color3.fromHex("#1b1a5c")
	button.BackgroundTransparency = 0.2
	button.Text = ""
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromHex("#000000")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	bar(button, -5)
	bar(button, 5)
	button.Activated:Connect(onPress)
	button.Parent = gui

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		-- Esc also opens Roblox's own menu, which marks it processed; pausing then is still right
		if table.find(KEYS, input.KeyCode) and (not processed or input.KeyCode == Enum.KeyCode.Escape) then
			onPress()
		end
	end)
	gui.Parent = parent
	return setmetatable({ _gui = gui }, PauseButton)
end

function PauseButton.SetVisible(self: PauseButton, visible: boolean)
	self._gui.Enabled = visible
end

return PauseButton
