--!strict
--[[
	PlayerInput: picks the control scheme the player is using right now.

	Touch when the last input came from a touchscreen, the mouse and keyboard
	otherwise. Both produce the same input shape, so the Run never knows which.

	    local controls = PlayerInput.new(playerGui)
	    run:Step(controls:Read(snapshot.Ship.Position), dt)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local MouseInput = require(script.Parent.MouseInput)
local RunInput = require(ReplicatedStorage.KngChak.Run.RunInput)
local TouchInput = require(script.Parent.TouchInput)

local PlayerInput = {}
PlayerInput.__index = PlayerInput

export type PlayerInput = typeof(setmetatable(
	{} :: {
		_mouse: MouseInput.MouseInput,
		_touch: TouchInput.TouchInput,
	},
	PlayerInput
))

function PlayerInput.new(parent: Instance): PlayerInput
	return setmetatable({
		_mouse = MouseInput.new(),
		_touch = TouchInput.new(parent),
	}, PlayerInput)
end

local function usingTouch(touch: TouchInput.TouchInput): boolean
	return touch:IsActive() or UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

-- This frame's input for a ship at `shipPosition`. Call it once per frame.
function PlayerInput.Read(self: PlayerInput, shipPosition: Vector2): RunInput.RunInput
	-- read both, so neither keeps a stale boost press for later
	local mouse = self._mouse:Read(shipPosition)
	local touch = self._touch:Read()
	return if usingTouch(self._touch) then touch else mouse
end

-- Drops any held touches, e.g. when a screen covers the game.
function PlayerInput.Reset(self: PlayerInput)
	self._touch:Reset()
end

return PlayerInput
