--!strict
--[[
	GhostThumb: the guided first call's hints. No words: see-through thumbs show
	each step's move on the side of the screen where it's done.

	    local ghost = GhostThumb.new(playerGui)
	    ghost:Update(snapshot, now) -- every frame; shows only in a guided call

	- Move: the left thumb drags toward the beacon.
	- Boost: the right thumb taps.
	- PushBreak: the left thumb drags away from the dummy rock (the flame streams
	  back onto it); once it's primed, the left drags at it and the right taps.
	- Slingshot: the left drags toward the planet; in orbit, it flicks out at the dummy.

	It reads only the Run's snapshot. Arena directions map straight onto the
	screen: the camera only pans, with north at the top.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Run = require(ReplicatedStorage.KngChak.Run.Run)

local THUMB = 76
local DRAG = 70 -- pixels a drag hint travels
local PERIOD = 1.4 -- seconds per loop of a hint

local GhostThumb = {}
GhostThumb.__index = GhostThumb

export type GhostThumb = typeof(setmetatable(
	{} :: {
		_gui: ScreenGui,
		_left: Frame,
		_right: Frame,
	},
	GhostThumb
))

local function thumb(parent: Instance, name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(THUMB, THUMB)
	frame.BackgroundColor3 = Color3.fromHex("#ffffff")
	frame.BackgroundTransparency = 0.55
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	local ring = Instance.new("UIStroke")
	ring.Color = Color3.fromHex("#ffffff")
	ring.Thickness = 3
	ring.Transparency = 0.2
	ring.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	frame.Visible = false
	frame.Parent = parent
	return frame
end

function GhostThumb.new(parent: Instance): GhostThumb
	local gui = Instance.new("ScreenGui")
	gui.Name = "GhostThumb"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local self = setmetatable({ _gui = gui, _left = thumb(gui, "Left"), _right = thumb(gui, "Right") }, GhostThumb)
	gui.Parent = parent
	return self
end

-- Arena direction -> screen direction (screen y grows downward).
local function onScreen(direction: Vector2): Vector2
	if direction.Magnitude < 1e-6 then
		return Vector2.zero
	end
	local unit = direction.Unit
	return Vector2.new(unit.X, -unit.Y)
end

-- A thumb dragging along `direction` (screen) from its rest spot, looping; fades in at the start of each loop.
local function drag(frame: Frame, rest: UDim2, direction: Vector2, phase: number)
	local travel = math.min(1, phase / 0.7)
	local eased = 1 - (1 - travel) ^ 2
	frame.Position = rest + UDim2.fromOffset(direction.X * DRAG * eased, direction.Y * DRAG * eased)
	frame.BackgroundTransparency = if phase > 0.85 then 0.85 else 0.55
	frame.Visible = true
end

-- A thumb tapping at its rest spot, looping.
local function tap(frame: Frame, rest: UDim2, phase: number)
	frame.Position = rest
	local scale = frame:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = if phase < 0.25 then 0.8 else 1
	frame.BackgroundTransparency = if phase < 0.25 then 0.35 else 0.6
	frame.Visible = true
end

local LEFT_REST = UDim2.fromScale(0.22, 0.68)
local RIGHT_REST = UDim2.fromScale(0.8, 0.68)

local function dummy(snapshot: Run.Snapshot): any
	local guided = snapshot.Guided :: Run.GuidedSnapshot
	for _, rock in snapshot.Rocks do
		if rock.Id == guided.DummyId then
			return rock
		end
	end
	return nil
end

function GhostThumb.Update(self: GhostThumb, snapshot: Run.Snapshot, now: number)
	local guided = snapshot.Guided
	local left, right = self._left, self._right
	left.Visible = false
	right.Visible = false
	local name = guided and guided.StepName
	if not guided or not name or snapshot.Phase ~= "Playing" then
		return
	end
	local phase = (now % PERIOD) / PERIOD
	local ship = snapshot.Ship
	local rightScale = right:FindFirstChildOfClass("UIScale") :: UIScale
	rightScale.Scale = 1

	if name == "Move" and guided.Beacon then
		drag(left, LEFT_REST, onScreen(guided.Beacon - ship.Position), phase)
		return
	end
	local rock = dummy(snapshot)
	if not rock then
		return
	end
	local toRock = rock.Position - ship.Position
	if name == "Boost" then
		drag(left, LEFT_REST, onScreen(toRock), phase)
		tap(right, RIGHT_REST, phase)
	elseif name == "PushBreak" then
		if rock.IsPrimed then
			drag(left, LEFT_REST, onScreen(toRock), phase)
			tap(right, RIGHT_REST, phase)
		else
			drag(left, LEFT_REST, onScreen(-toRock), phase)
		end
	elseif name == "Slingshot" then
		if ship.IsInOrbit then
			drag(left, LEFT_REST, onScreen(ship.Position), math.min(phase * 2, 1)) -- a quick flick outward
		else
			drag(left, LEFT_REST, onScreen(-ship.Position), phase)
		end
	end
end

function GhostThumb.SetVisible(self: GhostThumb, visible: boolean)
	self._gui.Enabled = visible
end

return GhostThumb
