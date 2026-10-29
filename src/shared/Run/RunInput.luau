--!strict
--[[
	RunInput: the player's flight input for one frame, the one input layer.

	Touch, mouse and any later gamepad scheme turn their raw input into this shape
	and nothing else. The Run takes one each Step.
]]

export type RunInput = {
	Move: Vector2, -- direction to steer toward (unit length), or zero
	MoveStrength: number, -- 0..1, how fast to go that way
	BoostPressed: boolean, -- boost went down this frame
	BoostHeld: boolean,
	Brake: boolean,
}

local RunInput = {}

-- No input: coast.
RunInput.Idle = table.freeze({
	Move = Vector2.zero,
	MoveStrength = 0,
	BoostPressed = false,
	BoostHeld = false,
	Brake = false,
}) :: RunInput

-- Steer along `direction` at `strength` (default 1), with optional boost and brake.
function RunInput.steer(direction: Vector2, strength: number?, boostPressed: boolean?, boostHeld: boolean?): RunInput
	return table.freeze({
		Move = if direction.Magnitude > 1e-6 then direction.Unit else Vector2.zero,
		MoveStrength = strength or 1,
		BoostPressed = boostPressed == true,
		BoostHeld = boostHeld == true,
		Brake = false,
	})
end

return table.freeze(RunInput)
