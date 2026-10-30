--!strict
--[[
	Overlay: the start, pause and results screens. A tap or click anywhere continues.

	    local overlay = Overlay.new(playerGui)
	    overlay:Show("KNG CHAK", "Tap to start", start, { { Text = "Controls", OnTap = showControls } })
	    overlay:Show("PAUSED", "Tap to resume", resume, {
	        { Text = "Controls", OnTap = showControls, Color = Color3.fromHex("#2f2d80") },
	        { Text = "Restart call", OnTap = restart },
	    })
	    overlay:Hide()

	Optional secondary actions sit as rounded pill buttons in a row under the body text.
]]

local Fonts = require(script.Parent.Fonts)

local MAX_EXTRAS = 2
local DEFAULT_PILL = Color3.fromHex("#ff3b3b")

local Overlay = {}
Overlay.__index = Overlay

export type Extra = {
	Text: string,
	OnTap: () -> (),
	Color: Color3?,
}

export type Overlay = typeof(setmetatable(
	{} :: {
		_gui: ScreenGui,
		_title: TextLabel,
		_body: TextLabel,
		_row: Frame,
		_pills: { TextButton },
		_onTap: (() -> ())?,
		_onExtras: { (() -> ())? },
		_suppressed: boolean,
	},
	Overlay
))

local function makePill(parent: Instance, index: number): TextButton
	local pill = Instance.new("TextButton")
	pill.Name = `Extra{index}`
	pill.LayoutOrder = index
	pill.Size = UDim2.fromOffset(186, 46)
	pill.BackgroundColor3 = DEFAULT_PILL
	pill.FontFace = Fonts.TextBold
	pill.TextSize = 20
	pill.TextColor3 = Color3.fromHex("#ffffff")
	pill.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromHex("#000000")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = pill
	pill.Parent = parent
	return pill
end

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
	title.Position = UDim2.fromScale(0.5, 0.46)
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
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.new(1, -32, 0, 96)
	body.BackgroundTransparency = 1
	body.FontFace = Fonts.Text
	body.TextSize = 25
	body.TextColor3 = Color3.fromHex("#ffffff")
	body.TextWrapped = true
	body.Parent = button

	local row = Instance.new("Frame")
	row.Name = "Extras"
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0.5, 102)
	row.Size = UDim2.new(1, -32, 0, 48)
	row.BackgroundTransparency = 1
	row.Visible = false
	row.Parent = button

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 14)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local pills: { TextButton } = {}
	for i = 1, MAX_EXTRAS do
		table.insert(pills, makePill(row, i))
	end

	local self = setmetatable({
		_gui = gui,
		_title = title,
		_body = body,
		_row = row,
		_pills = pills,
		_onTap = nil :: (() -> ())?,
		_onExtras = {} :: { (() -> ())? },
		_suppressed = false,
	}, Overlay)

	local function take(action: (() -> ())?)
		if action then
			self._onTap = nil
			table.clear(self._onExtras)
			action()
		end
	end
	button.Activated:Connect(function()
		take(self._onTap)
	end)
	for i, pill in pills do
		pill.Activated:Connect(function()
			take(self._onExtras[i])
		end)
	end
	gui.Parent = parent
	return self
end

function Overlay.Show(self: Overlay, title: string, body: string, onTap: () -> (), extras: { Extra }?, color: Color3?)
	self._title.Text = title
	self._title.TextColor3 = color or Color3.fromHex("#ffe066")
	self._body.Text = body
	self._onTap = onTap
	table.clear(self._onExtras)
	local list = extras or {}
	self._row.Visible = #list > 0
	for i, pill in self._pills do
		local item = list[i]
		pill.Visible = item ~= nil
		if item then
			pill.Text = item.Text
			pill.BackgroundColor3 = item.Color or DEFAULT_PILL
			self._onExtras[i] = item.OnTap
		end
	end
	self._gui.Enabled = not self._suppressed
end

function Overlay.Hide(self: Overlay)
	self._onTap = nil
	table.clear(self._onExtras)
	self._gui.Enabled = false
end

-- Keeps the screen out of sight (while the style tile or controls card shows) without forgetting it.
function Overlay.SetSuppressed(self: Overlay, suppressed: boolean)
	self._suppressed = suppressed
	self._gui.Enabled = not suppressed and self._onTap ~= nil
end

return Overlay
