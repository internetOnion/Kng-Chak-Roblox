--!strict
--[[
	MouseInput: PC test controls, turned into the Run's input shape.

	The cursor's offset from the ship steers: its direction is where to go, and its
	distance sets the speed (ControlsConfig's cursor deadzone and full range).
	Left click or Space boosts; holding keeps boosting. Right click or Shift brakes.

	    local mouse = MouseInput.new()
	    run:Step(mouse:Read(snapshot.Ship.Position), dt)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local KngChak = ReplicatedStorage.KngChak
local ArenaConfig = require(KngChak.Data.ArenaConfig)
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local ControlsConfig = require(KngChak.Data.ControlsConfig)
local RunInput = require(KngChak.Run.RunInput)

local MouseInput = {}
MouseInput.__index = MouseInput

export type MouseInput = typeof(setmetatable(
	{} :: {
		_boostPressed: boolean,
		_connection: RBXScriptConnection,
	},
	MouseInput
))

local function isBoost(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.Space
end

function MouseInput.new(): MouseInput
	local self
	self = setmetatable({
		_boostPressed = false,
		_connection = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and isBoost(input) then
				self._boostPressed = true
			end
		end),
	}, MouseInput)
	return self
end

-- Where the cursor points on the play plane, as an arena position.
local function cursorOnPlane(): Vector2?
	local camera = workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	if math.abs(ray.Direction.Y) < 1e-6 then
		return nil
	end
	local t = (ArenaConfig.PlaneHeight - ray.Origin.Y) / ray.Direction.Y
	return ArenaSpace.ToArena(ray.Origin + ray.Direction * t)
end

-- This frame's input for a ship at `shipPosition`. Takes the boost press, so call it once per frame.
function MouseInput.Read(self: MouseInput, shipPosition: Vector2): RunInput.RunInput
	local boostPressed = self._boostPressed
	self._boostPressed = false

	local move, strength = Vector2.zero, 0
	local aim = cursorOnPlane()
	if aim then
		local offset = aim - shipPosition
		local distance = offset.Magnitude
		if distance > ControlsConfig.CursorDeadzone then
			move = offset / distance
			strength = math.clamp((distance - ControlsConfig.CursorDeadzone) / ControlsConfig.CursorFullRange, 0, 1)
		end
	end

	return table.freeze({
		Move = move,
		MoveStrength = strength,
		BoostPressed = boostPressed,
		BoostHeld = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
			or UserInputService:IsKeyDown(Enum.KeyCode.Space),
		Brake = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) or UserInputService:IsKeyDown(
			Enum.KeyCode.LeftShift
		) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift),
	})
end

function MouseInput.Destroy(self: MouseInput)
	self._connection:Disconnect()
end

return MouseInput
