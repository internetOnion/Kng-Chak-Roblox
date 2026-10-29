--!strict
--[[
	Overlay: the start, pause and results screens. A tap or click anywhere continues.

	    local overlay = Overlay.new(playerGui)
	    overlay:Show("KNG CHAK", "Tap to start", function() ... end)
	    overlay:Show("PAUSED", "Tap to resume", resume, { Text = "Restart", OnTap = restart })
	    overlay:Hide()

	An optional second action is a smaller button under the text.
]]

local Fonts = require(script.Parent.Fonts)

local Overlay = {}
Overlay.__index = Overlay

export type Overlay = typeof(setmetatable(
	{} :: {
		_gui: ScreenGui,
		_title: TextLabel,
		_body: TextLabel,
		_extra: TextButton,
		_onTap: (() -> ())?,
		_onExtra: (() -> ())?,
		_suppressed: boolean,
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
	body.Size = UDim2.new(1, -32, 0, 100)
	body.BackgroundTransparency = 1
	body.FontFace = Fonts.Text
	body.TextSize = 26
	body.TextColor3 = Color3.fromHex("#ffffff")
	body.TextWrapped = true
	body.Parent = button

	local extra = Instance.new("TextButton")
	extra.Name = "Extra"
	extra.AnchorPoint = Vector2.new(0.5, 0)
	extra.Position = UDim2.new(0.5, 0, 0.52, 104)
	extra.Size = UDim2.fromOffset(220, 48)
	extra.BackgroundColor3 = Color3.fromHex("#ff3b3b")
	extra.FontFace = Fonts.TextBold
	extra.TextSize = 22
	extra.TextColor3 = Color3.fromHex("#ffffff")
	extra.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = extra
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = extra
	extra.Parent = button

	local self = setmetatable({
		_gui = gui,
		_title = title,
		_body = body,
		_extra = extra,
		_onTap = nil :: (() -> ())?,
		_onExtra = nil :: (() -> ())?,
		_suppressed = false,
	}, Overlay)
	local function take(action: (() -> ())?)
		if action then
			self._onTap = nil
			self._onExtra = nil
			action()
		end
	end
	button.Activated:Connect(function()
		take(self._onTap)
	end)
	extra.Activated:Connect(function()
		take(self._onExtra)
	end)
	gui.Parent = parent
	return self
end

export type Extra = {
	Text: string,
	OnTap: () -> (),
}

function Overlay.Show(self: Overlay, title: string, body: string, onTap: () -> (), extra: Extra?, color: Color3?)
	self._title.Text = title
	self._title.TextColor3 = color or Color3.fromHex("#ffe066")
	self._body.Text = body
	self._onTap = onTap
	self._onExtra = if extra then extra.OnTap else nil
	self._extra.Text = if extra then extra.Text else ""
	self._extra.Visible = extra ~= nil
	self._gui.Enabled = not self._suppressed
end

function Overlay.Hide(self: Overlay)
	self._onTap = nil
	self._onExtra = nil
	self._gui.Enabled = false
end

-- Keeps the screen out of sight (while the style tile shows) without forgetting it.
function Overlay.SetSuppressed(self: Overlay, suppressed: boolean)
	self._suppressed = suppressed
	self._gui.Enabled = not suppressed and self._onTap ~= nil
end

return Overlay
