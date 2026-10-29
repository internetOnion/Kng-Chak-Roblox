--!strict
--[[
	Overlay: the start and game-over screens. A tap or click anywhere continues.

	    local overlay = Overlay.new(playerGui)
	    overlay:Show("KNG CHAK", "Tap to start", function() ... end)
	    overlay:Hide()
]]

local Fonts = require(script.Parent.Fonts)

local Overlay = {}
Overlay.__index = Overlay

export type Overlay = typeof(setmetatable(
	{} :: {
		_gui: ScreenGui,
		_title: TextLabel,
		_body: TextLabel,
		_onTap: (() -> ())?,
	},
	Overlay
))

function Overlay.new(parent: Instance): Overlay
	local gui = Instance.new("ScreenGui")
	gui.Name = "Overlay"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.ScreenInsets = Enum.ScreenInsets.None -- the dimmed backdrop covers the whole screen; the text sits mid-screen
	gui.Enabled = false

	-- The whole screen is the button, so a thumb anywhere continues.
	local button = Instance.new("TextButton")
	button.Name = "Continue"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundColor3 = Color3.fromHex("#1b1a5c")
	button.BackgroundTransparency = 0.35
	button.Text = ""
	button.AutoButtonColor = false
	button.Parent = gui

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 1)
	title.Position = UDim2.fromScale(0.5, 0.48)
	title.Size = UDim2.new(1, -32, 0, 64)
	title.BackgroundTransparency = 1
	title.FontFace = Fonts.Display
	title.TextSize = 48
	title.TextColor3 = Color3.fromHex("#ffe066")
	title.TextStrokeTransparency = 0.3
	title.Parent = button

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.Position = UDim2.fromScale(0.5, 0.52)
	body.Size = UDim2.new(1, -32, 0, 90)
	body.BackgroundTransparency = 1
	body.FontFace = Fonts.Text
	body.TextSize = 26
	body.TextColor3 = Color3.fromHex("#ffffff")
	body.TextWrapped = true
	body.Parent = button

	local self = setmetatable({ _gui = gui, _title = title, _body = body, _onTap = nil }, Overlay)
	button.Activated:Connect(function()
		local onTap = self._onTap
		if onTap then
			self._onTap = nil
			onTap()
		end
	end)
	gui.Parent = parent
	return self
end

function Overlay.Show(self: Overlay, title: string, body: string, onTap: () -> ())
	self._title.Text = title
	self._body.Text = body
	self._onTap = onTap
	self._gui.Enabled = true
end

function Overlay.Hide(self: Overlay)
	self._onTap = nil
	self._gui.Enabled = false
end

return Overlay
