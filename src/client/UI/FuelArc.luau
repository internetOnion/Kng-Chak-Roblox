--!strict
--[[
	FuelArc: the fuel gauge, a segmented arc of dots under the ship.

	    local fuel = FuelArc.new(playerGui)
	    fuel:Listen(GameEvents)                                -- once, for refund flashes
	    fuel:Update(snapshot, run:GetTuning().Ship, os.clock()) -- every frame, after the camera moves

	It follows the ship on screen and fills left to right along the bottom of a
	circle round it, one segment per boost (BoostCost of fuel). Lit dots are
	orange, cyan in orbit (where fuel refills fastest) and red when there isn't
	enough for a boost. A fuel refund flashes it gold. It fades out when the tank
	has been full a while and comes back as soon as fuel matters. It only reads
	the snapshot and game events.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local Run = require(KngChak.Run.Run)
local RunEvents = require(KngChak.Run.RunEvents)
local ShipConfig = require(KngChak.Data.ShipConfig)

local SPAN = math.rad(150) -- the arc's width
local RADIUS_MIN = 26 -- px from the ship's centre, at least...
local RADIUS_STUDS = 4.2 -- ...or this many studs, whichever is bigger on screen
local DOT = 5 -- px
local DOT_FUEL = 4 -- fuel each dot stands for (roughly)
local SEGMENT_GAP = math.rad(5)
local LIT = Color3.fromHex("#ff8a3d")
local ORBIT = Color3.fromHex("#4fd8e8")
local LOW = Color3.fromHex("#ff4d5e")
local FLASH = Color3.fromHex("#ffd166")
local UNLIT = Color3.fromHex("#7d8aa6")
local FLASH_TIME = 0.5
local IDLE_FADE_AFTER = 1.5 -- seconds full and idle before it fades
local FADED = 0.85 -- transparency when faded

type Dot = {
	frame: Frame,
	angle: number, -- radians from straight down, + to the right
	level: number, -- fuel at which this dot lights
}

local FuelArc = {}
FuelArc.__index = FuelArc

export type FuelArc = typeof(setmetatable(
	{} :: {
		_gui: ScreenGui,
		_dots: { Dot },
		_layout: string, -- the fuel max and boost cost the dots were laid out for
		_flashUntil: number,
		_idleSince: number?,
		_fade: number, -- 0 shown .. 1 faded
		_last: number?,
	},
	FuelArc
))

function FuelArc.new(parent: Instance): FuelArc
	local gui = Instance.new("ScreenGui")
	gui.Name = "FuelArc"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- positions are viewport pixels, as the camera gives them
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.Parent = parent
	return setmetatable({
		_gui = gui,
		_dots = {},
		_layout = "",
		_flashUntil = 0,
		_idleSince = nil :: number?,
		_fade = 0,
		_last = nil :: number?,
	}, FuelArc)
end

-- Lays the dots out: one segment per boost, with a gap between segments.
local function layout(self: FuelArc, fuelMax: number, cost: number)
	for _, dot in self._dots do
		dot.frame:Destroy()
	end
	table.clear(self._dots)
	local segments = {}
	local start = 0
	while start < fuelMax - 0.01 do
		table.insert(segments, { start, math.min(fuelMax, start + cost) })
		start += cost
	end
	for _, segment in segments do
		local from, to = segment[1], segment[2]
		local a0 = -SPAN / 2 + SPAN * from / fuelMax + SEGMENT_GAP / 2
		local a1 = -SPAN / 2 + SPAN * to / fuelMax - SEGMENT_GAP / 2
		local count = math.max(2, math.round((to - from) / DOT_FUEL))
		for i = 1, count do
			local u = (i - 0.5) / count
			local frame = Instance.new("Frame")
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Size = UDim2.fromOffset(DOT, DOT)
			frame.BorderSizePixel = 0
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = frame
			frame.Parent = self._gui
			table.insert(self._dots, { frame = frame, angle = a0 + (a1 - a0) * u, level = from + (to - from) * u })
		end
	end
end

function FuelArc.Update(self: FuelArc, snapshot: Run.Snapshot, ship: ShipConfig.ShipConfig, now: number)
	local fuelMax, cost = ship.FuelMax, math.max(1, ship.BoostCost)
	local key = `{fuelMax}/{cost}`
	if key ~= self._layout then
		self._layout = key
		layout(self, fuelMax, cost)
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local state = snapshot.Ship
	local centre = camera:WorldToViewportPoint(ArenaSpace.ToWorld(state.Position, 3))
	local side = camera:WorldToViewportPoint(ArenaSpace.ToWorld(state.Position + Vector2.new(1, 0), 3))
	local perStud = math.abs(side.X - centre.X)
	local radius = math.max(RADIUS_MIN, RADIUS_STUDS * perStud)

	-- fade out when full and idle for a while; back at once when fuel matters
	local dt = if self._last then now - (self._last :: number) else 0
	self._last = now
	local flashing = now < self._flashUntil
	local idle = state.Fuel >= fuelMax - 0.01 and not state.IsInOrbit and not state.IsBoosting and not flashing
	if idle then
		self._idleSince = self._idleSince or now
	else
		self._idleSince = nil
	end
	local fadeTo = if self._idleSince and now - (self._idleSince :: number) > IDLE_FADE_AFTER then 1 else 0
	local rate = if fadeTo > self._fade then 3 else 10
	self._fade += (fadeTo - self._fade) * (1 - math.exp(-rate * dt))

	local low = state.Fuel < cost
	local lit = if flashing then FLASH elseif low then LOW elseif state.IsInOrbit then ORBIT else LIT
	local base = FADED * self._fade
	for _, dot in self._dots do
		local on = state.Fuel > dot.level
		local x = centre.X + math.sin(dot.angle) * radius
		local y = centre.Y + math.cos(dot.angle) * radius -- screen y grows downward: the arc hangs below
		dot.frame.Position = UDim2.fromOffset(x, y)
		dot.frame.BackgroundColor3 = if on then lit else UNLIT
		dot.frame.BackgroundTransparency = if on then base else 0.5 + 0.5 * base
		dot.frame.Size = if flashing and on then UDim2.fromOffset(DOT + 2, DOT + 2) else UDim2.fromOffset(DOT, DOT)
	end
end

-- Flashes the arc whenever whatever `events` forwards (GameEvents, or one Run's hub) refunds fuel.
function FuelArc.Listen(self: FuelArc, events: RunEvents.RunEvents)
	events.FuelRefunded:Connect(function()
		self._flashUntil = os.clock() + FLASH_TIME
	end)
end

function FuelArc.SetVisible(self: FuelArc, visible: boolean)
	self._gui.Enabled = visible
end

return FuelArc
