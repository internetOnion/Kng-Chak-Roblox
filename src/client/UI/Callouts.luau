--!strict
--[[
	Callouts: glowing world-space popups ("PERFECT!", "COMBO ×5") pinned where the
	action happened, so they never stack on top of the HUD or wave banners.

	    local callouts = Callouts.new(playerGui)
	    callouts:Listen(GameEvents)          -- once; GameEvents follows whichever Run is active
	    callouts:Update(snapshot, os.clock()) -- every frame

	Coalesces same-hit PERFECT + combo milestones into one popup ("PERFECT! · ×10")
	and nudges simultaneous nearby popups vertically in arena space so multi-kills
	form a clean rising ladder instead of overlapping text.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaConfig = require(KngChak.Data.ArenaConfig)
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local Rock = require(KngChak.Rocks.Rock)
local Run = require(KngChak.Run.Run)
local RunEvents = require(KngChak.Run.RunEvents)

local Fonts = require(script.Parent.Fonts)

local POOL_SIZE = 4
local MILESTONE = 5 -- a combo callout every this many
local LIFT = 5 -- studs above the play plane, over rocks and ship
local DRIFT = 3.6 -- arena units a callout floats upward over its life
local LIFE = 0.9 -- seconds from pop-in to gone
local POP_TIME = 0.14
local FADE_START = 0.58
local MIN_SEPARATION = 9 -- arena units: closer active popups step upward
local STACK_STEP = 4.4 -- arena units stepped upward per nearby popup

local PERFECT_COLOR = Color3.fromHex("#ffe066")
local COMBO_COLOR = Color3.fromHex("#ff9a1f")
local GLOW = Color3.fromHex("#000000")

type Slot = {
	anchor: Attachment,
	gui: BillboardGui,
	label: TextLabel,
	stroke: UIStroke,
	scale: UIScale,
	origin: Vector2,
	startedAt: number,
	active: boolean,
}

local Callouts = {}
Callouts.__index = Callouts

export type Callouts = typeof(setmetatable(
	{} :: {
		_slots: { Slot },
		_visible: boolean,
		_combo: number,
		_lastSpot: Vector2,
		_shipSpot: Vector2,
		_gen: number, -- increments on Clear so deferred callbacks from a finished run drop out
	},
	Callouts
))

local function makeSlot(parent: Instance, index: number): Slot
	local anchor = Instance.new("Attachment")
	anchor.Name = `CalloutAnchor{index}`
	anchor.Parent = workspace.Terrain

	local gui = Instance.new("BillboardGui")
	gui.Name = `Callout{index}`
	gui.ResetOnSpawn = false
	gui.Adornee = anchor
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ClipsDescendants = false
	gui.Size = UDim2.fromOffset(240, 48)
	gui.Enabled = false

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = Fonts.Display
	label.TextSize = 26
	label.TextTransparency = 1
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = GLOW
	stroke.Thickness = 3
	stroke.Transparency = 1
	stroke.Parent = label

	local scale = Instance.new("UIScale")
	scale.Parent = label

	gui.Parent = parent
	return {
		anchor = anchor,
		gui = gui,
		label = label,
		stroke = stroke,
		scale = scale,
		origin = Vector2.zero,
		startedAt = 0,
		active = false,
	}
end

local function currentSpot(slot: Slot, now: number): Vector2
	local t = math.clamp((now - slot.startedAt) / LIFE, 0, 1)
	return slot.origin + Vector2.new(0, DRIFT * t)
end

-- Nudges `spot` upward in arena space if another active popup is already right there.
local function destack(self: Callouts, spot: Vector2, now: number): Vector2
	local candidate = spot
	for _ = 1, POOL_SIZE do
		local crowded = false
		for _, slot in self._slots do
			if slot.active and (currentSpot(slot, now) - candidate).Magnitude < MIN_SEPARATION then
				crowded = true
				break
			end
		end
		if not crowded then
			break
		end
		candidate += Vector2.new(0, STACK_STEP)
	end
	local limit = ArenaConfig.ArenaRadius - 4
	if candidate.Magnitude > limit then
		candidate = candidate.Unit * limit
	end
	return candidate
end

local function pickSlot(self: Callouts): Slot
	local oldest = self._slots[1]
	for _, slot in self._slots do
		if not slot.active then
			return slot
		end
		if slot.startedAt < oldest.startedAt then
			oldest = slot
		end
	end
	return oldest
end

function Callouts.new(parent: Instance): Callouts
	local slots = {}
	for i = 1, POOL_SIZE do
		table.insert(slots, makeSlot(parent, i))
	end
	return setmetatable({
		_slots = slots,
		_visible = true,
		_combo = 0,
		_lastSpot = Vector2.zero,
		_shipSpot = Vector2.zero,
		_gen = 0,
	}, Callouts)
end

function Callouts.ShowAt(self: Callouts, text: string, color: Color3, spot: Vector2)
	local now = os.clock()
	local placed = destack(self, spot, now)
	local slot = pickSlot(self)
	slot.origin = placed
	slot.startedAt = now
	slot.active = true
	slot.label.Text = text
	slot.label.TextColor3 = color
	slot.label.TextTransparency = 0
	slot.stroke.Transparency = 0.1
	slot.scale.Scale = 1.35
	slot.anchor.WorldPosition = ArenaSpace.ToWorld(placed, LIFT)
	slot.gui.Enabled = self._visible
end

function Callouts.Listen(self: Callouts, events: RunEvents.RunEvents)
	local pendingPerfect: Vector2? = nil
	local pendingMilestone: number? = nil
	local scheduled = false

	local function flush(gen: number)
		scheduled = false
		local perfSpot = pendingPerfect
		local milestone = pendingMilestone
		pendingPerfect = nil
		pendingMilestone = nil
		if self._gen ~= gen then
			return
		end
		if perfSpot and milestone then
			self:ShowAt(`PERFECT! · ×{milestone}`, PERFECT_COLOR, perfSpot)
		elseif perfSpot then
			self:ShowAt("PERFECT!", PERFECT_COLOR, perfSpot)
		elseif milestone then
			self:ShowAt(`COMBO ×{milestone}`, COMBO_COLOR, self._lastSpot)
		end
	end

	local function schedule()
		if not scheduled then
			scheduled = true
			local gen = self._gen
			task.defer(flush, gen)
		end
	end

	events.RockBroken:Connect(function(rock: Rock.Rock)
		self._lastSpot = rock.Position
	end)

	events.Perfect:Connect(function(rock: Rock.Rock)
		self._lastSpot = rock.Position
		pendingPerfect = rock.Position
		schedule()
	end)

	events.ComboChanged:Connect(function(combo: number)
		local before = self._combo
		self._combo = combo
		if combo > before and math.floor(combo / MILESTONE) > math.floor(before / MILESTONE) then
			pendingMilestone = combo
			schedule()
		end
	end)
end

function Callouts.Update(self: Callouts, snapshot: Run.Snapshot, now: number)
	self._shipSpot = snapshot.Ship.Position
	if self._lastSpot == Vector2.zero then
		self._lastSpot = self._shipSpot
	end
	for _, slot in self._slots do
		if slot.active then
			local age = now - slot.startedAt
			if age >= LIFE then
				slot.active = false
				slot.gui.Enabled = false
			else
				local pop = math.clamp(age / POP_TIME, 0, 1)
				slot.scale.Scale = 1.35 - 0.35 * (1 - (1 - pop) ^ 2)
				local fade = if age <= FADE_START then 0 else math.clamp((age - FADE_START) / (LIFE - FADE_START), 0, 1)
				slot.label.TextTransparency = fade
				slot.stroke.Transparency = 0.1 + 0.9 * fade
				slot.anchor.WorldPosition = ArenaSpace.ToWorld(currentSpot(slot, now), LIFT)
				slot.gui.Enabled = self._visible
			end
		end
	end
end

function Callouts.Clear(self: Callouts)
	self._gen += 1
	self._combo = 0
	self._lastSpot = Vector2.zero
	for _, slot in self._slots do
		slot.active = false
		slot.gui.Enabled = false
	end
end

function Callouts.SetVisible(self: Callouts, visible: boolean)
	self._visible = visible
	for _, slot in self._slots do
		slot.gui.Enabled = visible and slot.active
	end
end

return Callouts
