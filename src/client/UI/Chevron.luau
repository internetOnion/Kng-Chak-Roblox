--!strict
--[[
	Chevron: one arrow on the screen's edge pointing at the threat when it's off screen.

	    local chevron = Chevron.new(playerGui)
	    chevron:Update(snapshot, arena.PlanetRadius, os.clock()) -- every frame, after the camera moves

	The threat is the rock the Run says will hit soonest (Snapshot.ThreatId). Only
	it gets a chevron, so there's never more than one. The chevron sits just inside
	the edge, along the line from the screen's centre to the rock, pulses with the
	threat ring and takes the rock's hint colour. It hides while the rock is on screen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local Run = require(KngChak.Run.Run)
local ThreatView = require(script.Parent.Parent.Views.ThreatView)

local INSET = 34 -- px from the screen's edge (clear of rounded corners and notches)
local MARGIN = 12 -- px a rock can be past the edge and still count as on screen
local SIZE = 28
local PULSE = 6

local Chevron = {}
Chevron.__index = Chevron

export type Chevron = typeof(setmetatable(
	{} :: {
		_gui: ScreenGui,
		_arrow: Frame,
		_bars: { Frame },
	},
	Chevron
))

function Chevron.new(parent: Instance): Chevron
	local gui = Instance.new("ScreenGui")
	gui.Name = "Chevron"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- positions are viewport pixels, as the camera gives them
	gui.ScreenInsets = Enum.ScreenInsets.None

	local arrow = Instance.new("Frame")
	arrow.Name = "Arrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Size = UDim2.fromOffset(SIZE, SIZE)
	arrow.BackgroundTransparency = 1
	arrow.Visible = false
	arrow.Parent = gui

	-- two bars meeting at a tip make a ">" pointing right; the arrow's rotation turns it toward the rock
	local bars = {}
	local tip = Vector2.new(SIZE * 0.85, SIZE * 0.5)
	local length = SIZE * 0.7
	for _, side in { -1, 1 } do
		local angle = math.rad(side * 40) -- bars rotate about their centres
		local centre = tip - Vector2.new(math.cos(angle), math.sin(angle)) * (length / 2)
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromOffset(centre.X, centre.Y)
		bar.Size = UDim2.fromOffset(length, 7)
		bar.Rotation = side * 40
		bar.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = bar
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.5
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Parent = bar
		bar.Parent = arrow
		table.insert(bars, bar)
	end

	gui.Parent = parent
	return setmetatable({ _gui = gui, _arrow = arrow, _bars = bars }, Chevron)
end

function Chevron.Update(self: Chevron, snapshot: Run.Snapshot, planetRadius: number, now: number)
	local threat = nil
	for _, rock in snapshot.Rocks do
		if rock.Id == snapshot.ThreatId then
			threat = rock
		end
	end
	local camera = workspace.CurrentCamera
	if not threat or not camera then
		self._arrow.Visible = false
		return
	end
	local size = camera.ViewportSize
	local point = camera:WorldToViewportPoint(ArenaSpace.ToWorld(threat.Position, 2))
	local x, y = point.X, point.Y
	if point.Z > 0 and x > -MARGIN and x < size.X + MARGIN and y > -MARGIN and y < size.Y + MARGIN then
		self._arrow.Visible = false
		return
	end

	local centre = size / 2
	local offset = Vector2.new(x, y) - centre
	if point.Z <= 0 then
		offset = -offset -- behind the camera: the projection flips
	end
	local reach = Vector2.new(math.max(1, centre.X - INSET), math.max(1, centre.Y - INSET))
	local k = math.min(reach.X / math.max(1e-6, math.abs(offset.X)), reach.Y / math.max(1e-6, math.abs(offset.Y)))
	local at = centre + offset * k

	local pulse = 0.5 + 0.5 * math.sin(now * PULSE)
	local color = ThreatView.ColorOf(threat, planetRadius)
	self._arrow.Position = UDim2.fromOffset(at.X, at.Y)
	self._arrow.Rotation = math.deg(math.atan2(offset.Y, offset.X))
	self._arrow.Visible = true
	for _, bar in self._bars do
		bar.BackgroundColor3 = color
		bar.BackgroundTransparency = 0.3 * (1 - pulse)
	end
end

function Chevron.SetVisible(self: Chevron, visible: boolean)
	self._gui.Enabled = visible
end

return Chevron
