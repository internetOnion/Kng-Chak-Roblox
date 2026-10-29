--!strict
--[[
	Controls: turns each control scheme's raw input into the Run's one input shape.

	The client's adapters (mouse, touch) gather raw input from Roblox and call
	these; the maths lives here so it can be tested.

	- Cursor (PC): the cursor's offset from the ship steers. Its distance past
	  CursorDeadzone sets the speed, full at CursorFullRange farther.
	- Stick (phone): a floating stick under the left thumb. How far it's dragged,
	  past StickDeadzone of StickRadius, sets the speed. Letting go brakes, so the
	  ship eases to a stop without an extra button.
]]

local ControlsConfig = require("../Data/ControlsConfig")
local RunInput = require("../Run/RunInput")

local Controls = {}

export type Buttons = {
	boostPressed: boolean, -- boost went down since the last frame
	boostHeld: boolean,
	brake: boolean,
}

local function build(move: Vector2, strength: number, buttons: Buttons): RunInput.RunInput
	return table.freeze({
		Move = move,
		MoveStrength = strength,
		BoostPressed = buttons.boostPressed,
		BoostHeld = buttons.boostHeld,
		Brake = buttons.brake,
	})
end

-- From the cursor's offset from the ship, in arena units (nil when the cursor isn't on the plane).
function Controls.FromCursor(offset: Vector2?, buttons: Buttons): RunInput.RunInput
	if offset then
		local distance = offset.Magnitude
		if distance > ControlsConfig.CursorDeadzone then
			local strength = (distance - ControlsConfig.CursorDeadzone) / ControlsConfig.CursorFullRange
			return build(offset / distance, math.clamp(strength, 0, 1), buttons)
		end
	end
	return build(Vector2.zero, 0, buttons)
end

-- From the stick's drag in screen pixels (+y down the screen), or nil when no thumb is on it.
function Controls.FromStick(drag: Vector2?, buttons: Buttons): RunInput.RunInput
	if not drag then
		local released = table.clone(buttons)
		released.brake = true
		return build(Vector2.zero, 0, released)
	end
	local amount = drag.Magnitude / ControlsConfig.StickRadius
	local deadzone = ControlsConfig.StickDeadzone
	if amount <= deadzone then
		return build(Vector2.zero, 0, buttons)
	end
	local strength = math.clamp((amount - deadzone) / (1 - deadzone), 0, 1)
	local direction = Vector2.new(drag.X, -drag.Y).Unit -- screen up is arena up
	return build(direction, strength, buttons)
end

return table.freeze(Controls)
