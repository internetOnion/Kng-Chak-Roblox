--!strict
--[[
	TouchInput: phone controls, turned into the Run's input shape.

	- Left half: a floating stick appears where the thumb lands. Dragging steers,
	  and how far sets the speed. Letting go brakes the ship to a stop.
	- Right half: a tap boosts; holding keeps boosting.

	Touches that start on a GUI button (the overlay) are left alone.

	    local touch = TouchInput.new(playerGui)
	    run:Step(touch:Read(), dt)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local KngChak = ReplicatedStorage.KngChak
local Controls = require(KngChak.Input.Controls)
local ControlsConfig = require(KngChak.Data.ControlsConfig)
local RunInput = require(KngChak.Run.RunInput)

local TouchInput = {}
TouchInput.__index = TouchInput

export type TouchInput = typeof(setmetatable(
	{} :: {
		_stick: InputObject?, -- the touch driving the stick
		_origin: Vector2, -- where the stick's thumb landed
		_boosts: { [InputObject]: boolean }, -- touches held on the right half
		_boostPressed: boolean,
		_base: Frame,
		_knob: Frame,
		_connections: { RBXScriptConnection },
	},
	TouchInput
))

local function circle(parent: Instance, name: string, size: number, transparency: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size, size)
	frame.BackgroundColor3 = Color3.fromHex("#ffffff")
	frame.BackgroundTransparency = transparency
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

local function screenPosition(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
end

function TouchInput.new(parent: Instance): TouchInput
	local gui = Instance.new("ScreenGui")
	gui.Name = "TouchStick"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.IgnoreGuiInset = false -- the same coordinates as InputObject.Position
	local base = circle(gui, "Base", ControlsConfig.StickRadius * 2, 0.8)
	local knob = circle(base, "Knob", ControlsConfig.StickRadius * 0.8, 0.35)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	base.Visible = false
	gui.Parent = parent

	local self = setmetatable({
		_stick = nil :: InputObject?,
		_origin = Vector2.zero,
		_boosts = {},
		_boostPressed = false,
		_base = base,
		_knob = knob,
		_connections = {},
	}, TouchInput)

	table.insert(
		self._connections,
		UserInputService.TouchStarted:Connect(function(touch: InputObject, processed: boolean)
			if processed then
				return
			end
			local position = screenPosition(touch)
			local width = workspace.CurrentCamera.ViewportSize.X
			if position.X < width / 2 then
				if not self._stick then
					self._stick = touch
					self._origin = position
					base.Position = UDim2.fromOffset(position.X, position.Y)
					knob.Position = UDim2.fromScale(0.5, 0.5)
					base.Visible = true
				end
			else
				self._boosts[touch] = true
				self._boostPressed = true
			end
		end)
	)
	table.insert(
		self._connections,
		UserInputService.TouchEnded:Connect(function(touch: InputObject)
			if touch == self._stick then
				self._stick = nil
				base.Visible = false
			end
			self._boosts[touch] = nil
		end)
	)
	return self
end

-- Whether a thumb is on the screen driving the game.
function TouchInput.IsActive(self: TouchInput): boolean
	return self._stick ~= nil or next(self._boosts) ~= nil
end

-- This frame's input. Takes the boost press, so call it once per frame.
function TouchInput.Read(self: TouchInput): RunInput.RunInput
	local boostPressed = self._boostPressed
	self._boostPressed = false

	local drag: Vector2? = nil
	local stick = self._stick
	if stick then
		local offset = screenPosition(stick) - self._origin
		drag = offset
		-- the knob follows the thumb, up to the stick's edge
		local radius = ControlsConfig.StickRadius
		local shown = if offset.Magnitude > radius then offset.Unit * radius else offset
		self._knob.Position = UDim2.new(0.5, shown.X, 0.5, shown.Y)
	end

	return Controls.FromStick(drag, {
		boostPressed = boostPressed,
		boostHeld = next(self._boosts) ~= nil,
		brake = false,
	})
end

-- Lets go of every touch, e.g. when a screen covers the game.
function TouchInput.Reset(self: TouchInput)
	self._stick = nil
	table.clear(self._boosts)
	self._boostPressed = false
	self._base.Visible = false
end

function TouchInput.Destroy(self: TouchInput)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	local gui = self._base.Parent
	if gui then
		gui:Destroy()
	end
end

return TouchInput
