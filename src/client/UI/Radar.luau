--!strict
--[[
	Radar: the whole arena in the top-right corner.

	    local radar = Radar.new(playerGui)
	    radar:Update(snapshot, run:GetTuning().Arena, camera:View(), os.clock()) -- every frame

	A round map with the arena edge as its rim and the planet and orbit band at its
	centre. Every rock is a dot in its type's colour (pink while primed, red once
	it's about to hit; rocks still outside the edge sit on the rim), the threat
	gets a pulsing ring, the ship is a small arrow along its heading, and a box
	shows what's on screen. North is up, as on screen. It sits top-right below
	the score, inside the safe area, clear of the top bar and the boost thumb's
	usual spot. It only reads the snapshot and the camera's view.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaConfig = require(KngChak.Data.ArenaConfig)
local Run = require(KngChak.Run.Run)
local ThreatView = require(script.Parent.Parent.Views.ThreatView)

local SIZE_SMALL = 104 -- px across on a phone...
local SIZE_LARGE = 140 -- ...and on a bigger screen
local SMALL_BELOW = 500 -- viewport height (px) below which the radar is small
local TOP = 50 -- px below the top of the safe area (under the score)
local RIM = 4 -- px between the arena edge and the radar's border
local BACKGROUND = Color3.fromHex("#14133d")
local BORDER = Color3.fromHex("#ffffff")
local BAND = Color3.fromHex("#6ff3ff")
local PLANET = Color3.fromHex("#2fc4ff")
local SHIP = Color3.fromHex("#ff3b3b")
local VIEW = Color3.fromHex("#ffffff")
local PULSE = 6

local Radar = {}
Radar.__index = Radar

export type Radar = typeof(setmetatable(
	{} :: {
		_gui: ScreenGui,
		_frame: Frame,
		_band: Frame,
		_planet: Frame,
		_view: Frame,
		_ship: Frame,
		_ring: Frame,
		_dots: { [number]: Frame }, -- by rock Id
		_size: number,
	},
	Radar
))

local function circle(parent: Instance, name: string, color: Color3, transparency: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

function Radar.new(parent: Instance): Radar
	local gui = Instance.new("ScreenGui")
	gui.Name = "Radar"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local frame = Instance.new("Frame")
	frame.Name = "Map"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -16, 0, TOP)
	frame.BackgroundColor3 = BACKGROUND
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	local mapCorner = Instance.new("UICorner")
	mapCorner.CornerRadius = UDim.new(0.5, 0)
	mapCorner.Parent = frame
	frame.Parent = gui
	local border = Instance.new("UIStroke")
	border.Color = BORDER
	border.Transparency = 0.5
	border.Thickness = 1.5
	border.Parent = frame

	local band = circle(frame, "Band", BAND, 0.8)
	local planet = circle(frame, "Planet", PLANET, 0)

	local view = Instance.new("Frame")
	view.Name = "View"
	view.AnchorPoint = Vector2.new(0.5, 0.5)
	view.BackgroundTransparency = 1
	local viewStroke = Instance.new("UIStroke")
	viewStroke.Color = VIEW
	viewStroke.Transparency = 0.6
	viewStroke.Thickness = 1
	viewStroke.Parent = view
	view.Parent = frame

	local ring = circle(frame, "Threat", BORDER, 1)
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Thickness = 1.5
	ringStroke.Parent = ring

	-- the ship: a short bar along its heading with a bright nose
	local ship = Instance.new("Frame")
	ship.Name = "Ship"
	ship.AnchorPoint = Vector2.new(0.5, 0.5)
	ship.Size = UDim2.fromOffset(11, 5)
	ship.BackgroundColor3 = SHIP
	ship.BorderSizePixel = 0
	ship.ZIndex = 3
	local shipCorner = Instance.new("UICorner")
	shipCorner.CornerRadius = UDim.new(0.5, 0)
	shipCorner.Parent = ship
	local nose = circle(ship, "Nose", Color3.fromHex("#ffffff"), 0)
	nose.Position = UDim2.fromScale(1, 0.5)
	nose.Size = UDim2.fromOffset(4, 4)
	nose.ZIndex = 3
	ship.Parent = frame

	gui.Parent = parent
	return setmetatable({
		_gui = gui,
		_frame = frame,
		_band = band,
		_planet = planet,
		_view = view,
		_ship = ship,
		_ring = ring,
		_dots = {},
		_size = 0,
	}, Radar)
end

function Radar.Update(
	self: Radar,
	snapshot: Run.Snapshot,
	arena: ArenaConfig.ArenaConfig,
	focus: Vector2,
	viewHalf: Vector2,
	now: number
)
	local camera = workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else 720
	local size = if height < SMALL_BELOW then SIZE_SMALL else SIZE_LARGE
	if size ~= self._size then
		self._size = size
		self._frame.Size = UDim2.fromOffset(size, size)
	end
	local half = size / 2
	local scale = (half - RIM) / arena.ArenaRadius -- px per arena unit

	-- arena position -> px inside the map; things past the edge sit on the rim
	local function at(position: Vector2, cap: number?): UDim2
		local limit = cap or arena.ArenaRadius
		local distance = position.Magnitude
		local p = if distance > limit then position * (limit / distance) else position
		return UDim2.fromOffset(half + p.X * scale, half - p.Y * scale)
	end

	local bandSize = 2 * (arena.PlanetRadius + arena.OrbitBandTop) * scale
	self._band.Position = UDim2.fromOffset(half, half)
	self._band.Size = UDim2.fromOffset(bandSize, bandSize)
	local planetSize = 2 * arena.PlanetRadius * scale
	self._planet.Position = UDim2.fromOffset(half, half)
	self._planet.Size = UDim2.fromOffset(planetSize, planetSize)

	-- the view box, kept inside the map (at a wide zoom the screen is wider than the arena)
	local inner = half - RIM
	local left = math.clamp((focus.X - viewHalf.X) * scale, -inner, inner)
	local right = math.clamp((focus.X + viewHalf.X) * scale, -inner, inner)
	local top = math.clamp((focus.Y + viewHalf.Y) * scale, -inner, inner)
	local bottom = math.clamp((focus.Y - viewHalf.Y) * scale, -inner, inner)
	self._view.Position = UDim2.fromOffset(half + (left + right) / 2, half - (top + bottom) / 2)
	self._view.Size = UDim2.fromOffset(right - left, top - bottom)

	local pulse = 0.5 + 0.5 * math.sin(now * PULSE)
	local seen = {}
	self._ring.Visible = false
	for _, rock in snapshot.Rocks do
		seen[rock.Id] = true
		local dot = self._dots[rock.Id]
		if not dot then
			local made = circle(self._frame, "Rock", BORDER, 0)
			made.ZIndex = 2
			local diameter = math.max(5, rock.Type.Radius * 3.2)
			made.Size = UDim2.fromOffset(diameter, diameter)
			self._dots[rock.Id] = made
			dot = made
		end
		local color = ThreatView.ColorOf(rock, arena.PlanetRadius)
		local position = at(rock.Position)
		dot.Position = position
		dot.BackgroundColor3 = color
		if rock.Id == snapshot.ThreatId then
			local ringSize = 10 + 5 * pulse
			self._ring.Visible = true
			self._ring.Position = position
			self._ring.Size = UDim2.fromOffset(ringSize, ringSize)
			local stroke = self._ring:FindFirstChildOfClass("UIStroke") :: UIStroke
			stroke.Color = color
			stroke.Transparency = 0.5 - 0.5 * pulse
		end
	end
	for id, dot in self._dots do
		if not seen[id] then
			dot:Destroy()
			self._dots[id] = nil
		end
	end

	local ship = snapshot.Ship
	self._ship.Position = at(ship.Position)
	self._ship.Rotation = -math.deg(math.atan2(ship.Facing.Y, ship.Facing.X))
end

function Radar.SetVisible(self: Radar, visible: boolean)
	self._gui.Enabled = visible
end

return Radar
