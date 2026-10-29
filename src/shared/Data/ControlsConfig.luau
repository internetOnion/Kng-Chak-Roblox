--!strict
--[[
	ControlsConfig: how touch and mouse turn into Move, Boost and Brake (area 5 owns the values).

	Input adapters read these; the Run never does. Values come from the web prototype.
]]

local ControlsConfig = {
	-- Mouse: the cursor's offset from the ship steers
	CursorDeadzone = 2.5, -- cursor this close to the ship (arena units): coast
	CursorFullRange = 12, -- ...this much farther: full speed

	-- Touch: a floating stick under the left thumb
	StickRadius = 70, -- pixels of drag for full speed
	StickDeadzone = 0.2, -- fraction of the radius that does nothing
}

return table.freeze(ControlsConfig)
