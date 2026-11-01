--!strict
--[[
	MusicButton: a small round music toggle beside PauseButton in the top-left corner.

	    local musicBtn = MusicButton.new(playerGui, function() ... end)
	    musicBtn:SetMuted(true)

	Pressing M on a keyboard toggles it too, even while the overlay hides the HUD
	button. Built from crisp geometric shapes (no unicode glyphs) and keeps to
	Roblox's safe area so a thumb on it never steers or boosts.
]]

local UserInputService = game:GetService("UserInputService")

local SIZE = 44
local KEY = Enum.KeyCode.M
local ACTIVE_BG = Color3.fromHex("#1b1a5c")
local MUTED_BG = Color3.fromHex("#12113a")
local NOTE_ON = Color3.fromHex("#ffffff")
local NOTE_OFF = Color3.fromHex("#8e8cc4")
local SLASH = Color3.fromHex("#ff4d5e")
local OUTLINE = Color3.fromHex("#000000")

local MusicButton = {}
MusicButton.__index = MusicButton

export type MusicButton = typeof(setmetatable(
	{} :: {
		_gui: ScreenGui,
		_button: TextButton,
		_noteParts: { Frame },
		_slash: Frame,
	},
	MusicButton
))

local function shape(
	parent: Instance,
	name: string,
	anchor: Vector2,
	pos: UDim2,
	size: UDim2,
	radius: UDim,
	rotation: number?
): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = anchor
	frame.Position = pos
	frame.Size = size
	frame.Rotation = rotation or 0
	frame.BackgroundColor3 = NOTE_ON
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

function MusicButton.new(parent: Instance, onPress: () -> ()): MusicButton
	local gui = Instance.new("ScreenGui")
	gui.Name = "Music"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local button = Instance.new("TextButton")
	button.Name = "Music"
	button.Position = UDim2.fromOffset(68, 48) -- beside PauseButton, under the HP readout
	button.Size = UDim2.fromOffset(SIZE, SIZE)
	button.BackgroundColor3 = ACTIVE_BG
	button.BackgroundTransparency = 0.2
	button.Text = ""
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = OUTLINE
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	local pill = UDim.new(0.5, 0)
	local noteParts: { Frame } = {
		shape(button, "HeadLeft", Vector2.new(0.5, 0.5), UDim2.fromOffset(16, 28), UDim2.fromOffset(8, 6), pill, -18),
		shape(button, "HeadRight", Vector2.new(0.5, 0.5), UDim2.fromOffset(27, 26), UDim2.fromOffset(8, 6), pill, -18),
		shape(button, "StemLeft", Vector2.new(0.5, 1), UDim2.fromOffset(19, 28), UDim2.fromOffset(3, 14), pill),
		shape(button, "StemRight", Vector2.new(0.5, 1), UDim2.fromOffset(30, 26), UDim2.fromOffset(3, 14), pill),
		shape(
			button,
			"Beam",
			Vector2.new(0.5, 0.5),
			UDim2.fromOffset(24, 14),
			UDim2.fromOffset(14, 4),
			UDim.new(0, 2),
			-9
		),
	}

	local slash =
		shape(button, "Slash", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(26, 4), pill, -45)
	slash.BackgroundColor3 = SLASH
	slash.ZIndex = 2
	slash.Visible = false
	local slashStroke = Instance.new("UIStroke")
	slashStroke.Thickness = 1.5
	slashStroke.Color = OUTLINE
	slashStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	slashStroke.Parent = slash

	button.Activated:Connect(onPress)
	button.Parent = gui

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == KEY then
			onPress()
		end
	end)

	gui.Parent = parent
	return setmetatable({
		_gui = gui,
		_button = button,
		_noteParts = noteParts,
		_slash = slash,
	}, MusicButton)
end

function MusicButton.SetMuted(self: MusicButton, muted: boolean)
	self._button.BackgroundColor3 = if muted then MUTED_BG else ACTIVE_BG
	self._button.BackgroundTransparency = if muted then 0.25 else 0.2
	local color = if muted then NOTE_OFF else NOTE_ON
	local transparency = if muted then 0.35 else 0
	for _, part in self._noteParts do
		part.BackgroundColor3 = color
		part.BackgroundTransparency = transparency
	end
	self._slash.Visible = muted
end

function MusicButton.SetVisible(self: MusicButton, visible: boolean)
	self._gui.Enabled = visible
end

return MusicButton
