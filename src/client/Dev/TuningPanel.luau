--!strict
--[[
	TuningPanel (Studio only): change tuning values during a playtest, like the
	prototype's T menu. Press T to show or hide it.

	Every number in the tuning data (ship, combo, arena, waves) gets a box. A change goes
	straight to the running Run through its tuning overrides, and later Runs in the
	same playtest start with them too. Nothing is written back to the data modules,
	so stopping play throws every change away. Changed values show in yellow;
	Reset clears them all. Runs played with changes don't replay exactly.

	The game creates it only in Studio:

	    TuningPanel.new(playerGui, function(overrides) run:SetTuning(overrides) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Tuning = require(ReplicatedStorage.KngChak.Run.Tuning)

local TOGGLE_KEY = Enum.KeyCode.T
local ROW_HEIGHT = 24
local CHANGED = Color3.fromHex("#ffe066")
local NORMAL = Color3.fromHex("#ffffff")
local SECTION_ORDER = { "Ship", "Combo", "Arena", "Waves" }

local TuningPanel = {}

export type Overrides = Tuning.Overrides

local function text(parent: Instance, value: string, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = value
	label.Parent = parent
	return label
end

-- Builds the panel. `apply` gets the full set of overrides after every change.
function TuningPanel.new(parent: Instance, apply: (Overrides) -> ())
	local overrides: Overrides = {}

	local gui = Instance.new("ScreenGui")
	gui.Name = "TuningPanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Enabled = false

	local frame = Instance.new("ScrollingFrame")
	frame.AnchorPoint = Vector2.new(1, 1) -- bottom right, clear of the HUD along the top
	frame.Position = UDim2.new(1, -8, 1, -8)
	frame.Size = UDim2.new(0, 320, 0.8, 0)
	frame.BackgroundColor3 = Color3.fromHex("#14133d")
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.ScrollBarThickness = 6
	frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	frame.CanvasSize = UDim2.new()
	frame.Parent = gui

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 2)
	list.Parent = frame
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.Parent = frame

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local boxes: { { box: TextBox, section: string, key: string, default: number } } = {}

	local function refresh()
		for _, entry in boxes do
			local section = overrides[entry.section]
			local value = section and section[entry.key]
			entry.box.Text = tostring(if value ~= nil then value else entry.default)
			entry.box.TextColor3 = if value ~= nil then CHANGED else NORMAL
		end
	end

	local function set(sectionName: string, key: string, default: number, value: number?)
		local section: { [string]: any } = overrides[sectionName] or {}
		section[key] = if value == nil or value == default then nil else value
		if next(section) then
			overrides[sectionName] = section
		else
			overrides[sectionName] = nil
		end
		refresh()
		apply(table.clone(overrides))
	end

	local header = text(frame, "TUNING (T to hide)", 16, CHANGED)
	header.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	header.LayoutOrder = nextOrder()

	local reset = Instance.new("TextButton")
	reset.Size = UDim2.fromOffset(90, ROW_HEIGHT)
	reset.Text = "Reset all"
	reset.Font = Enum.Font.Code
	reset.TextSize = 14
	reset.LayoutOrder = nextOrder()
	reset.Parent = frame
	reset.Activated:Connect(function()
		table.clear(overrides)
		refresh()
		apply({})
	end)

	for _, sectionName in SECTION_ORDER do
		local data = Tuning.Sections[sectionName]
		local title = text(frame, sectionName, 15, CHANGED)
		title.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		title.LayoutOrder = nextOrder()

		local keys = {}
		for key, value in data do
			if type(value) == "number" then
				table.insert(keys, key)
			end
		end
		table.sort(keys)

		for _, key in keys do
			local default = data[key] :: number
			local row = Instance.new("Frame")
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
			row.LayoutOrder = nextOrder()
			row.Parent = frame

			local name = text(row, key, 13, NORMAL)
			name.Size = UDim2.fromScale(0.62, 1)

			local box = Instance.new("TextBox")
			box.AnchorPoint = Vector2.new(1, 0)
			box.Position = UDim2.fromScale(1, 0)
			box.Size = UDim2.new(0.36, 0, 1, -2)
			box.BackgroundColor3 = Color3.fromHex("#2a2970")
			box.BorderSizePixel = 0
			box.Font = Enum.Font.Code
			box.TextSize = 13
			box.ClearTextOnFocus = false
			box.Parent = row
			box.FocusLost:Connect(function()
				local value = tonumber(box.Text)
				if value then
					set(sectionName, key, default, value)
				else
					refresh()
				end
			end)
			table.insert(boxes, { box = box, section = sectionName, key = key, default = default })
		end
	end
	refresh()

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == TOGGLE_KEY then
			gui.Enabled = not gui.Enabled
		end
	end)
	gui.Parent = parent
end

return table.freeze(TuningPanel)
