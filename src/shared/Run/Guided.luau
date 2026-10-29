--!strict
--[[
	Guided: the guided first call, a scripted sequence of steps over a Run.

	A Run in guided mode plays no waves and no boss, and its planet can't be
	damaged. Instead this walks the player through one move per step, and a step
	only advances once the player has done its move (see Data/GuidedConfig):

	1. Move       fly through the beacon
	2. Boost      break the dummy rock with a boosted ram
	3. PushBreak  push the dummy with the flame until it's primed, then break it (the planet heals)
	4. Slingshot  lock onto the orbit, then slingshot out and break the dummy with the dive

	Each of steps 2-4 has one slow dummy rock. If it reaches the planet, or breaks
	the wrong way, a new one appears at the step's spot. Fires GuidedStep as each
	step begins. The Run owns it and calls Step once per sub-step.
]]

local Context = require("./Context")
local GuidedConfig = require("../Data/GuidedConfig")
local Rock = require("../Rocks/Rock")
local RockTypes = require("../Data/RockTypes")
local Ship = require("../Ship/Ship")

export type Guided = {
	Step: number, -- 1..#GuidedConfig.Steps, or past it once done
	Beacon: Vector2?, -- step 1's beacon, while it's up
	DummyId: number?, -- the step's dummy rock, while it's in the arena
	IsDone: boolean,
	_broke: string?, -- how the dummy broke this step (a RockBroken cause)
}

local Guided = {}

-- The breaks that complete each dummy step.
local COMPLETES: { [string]: { string } } = {
	Boost = { "Ram", "PushBreak", "Dive", "Perfect" },
	PushBreak = { "PushBreak", "Perfect" },
	Slingshot = { "Dive", "Perfect" },
}

local function dummySpot(name: string): Vector2?
	if name == "Boost" then
		return GuidedConfig.BoostRockAt
	elseif name == "PushBreak" then
		return GuidedConfig.PushRockAt
	elseif name == "Slingshot" then
		return GuidedConfig.DiveRockAt
	end
	return nil
end

-- The name of step `step` ("Move", "Boost", ...), or nil past the last.
function Guided.StepName(step: number): string?
	return GuidedConfig.Steps[step]
end

local function begin(guide: Guided, ctx: Context.Context, step: number)
	guide.Step = step
	guide.DummyId = nil
	guide._broke = nil
	local name = Guided.StepName(step)
	guide.Beacon = if name == "Move" then GuidedConfig.BeaconAt else nil
	if name then
		ctx.events.GuidedStep:Fire(step, name)
	else
		guide.IsDone = true
	end
end

-- A guided call about to begin step 1. It listens to the Run's events to see how the dummies break.
function Guided.new(ctx: Context.Context): Guided
	local guide: Guided = { Step = 0, Beacon = nil, DummyId = nil, IsDone = false, _broke = nil }
	ctx.events.RockBroken:Connect(function(rock: Rock.Rock, cause: string)
		if rock.Id == guide.DummyId then
			guide._broke = cause
		end
	end)
	return guide
end

-- Steps the guided call. Returns a new dummy rock to add to the arena, if one is due.
function Guided.Step(guide: Guided, ship: Ship.Ship, ctx: Context.Context): Rock.Rock?
	if guide.IsDone then
		return nil
	end
	if guide.Step == 0 then
		begin(guide, ctx, 1)
	end
	local name = Guided.StepName(guide.Step) :: string

	if name == "Move" then
		local beacon = guide.Beacon :: Vector2
		if (ship.Position - beacon).Magnitude <= GuidedConfig.BeaconRadius then
			begin(guide, ctx, guide.Step + 1)
		end
		return nil
	end

	local broke = guide._broke
	if broke then
		guide._broke = nil
		guide.DummyId = nil
		if table.find(COMPLETES[name], broke) then
			begin(guide, ctx, guide.Step + 1)
			return nil
		end
	end

	-- the dummy is gone (it reached the planet or broke the wrong way): bring another
	local alive = false
	for _, rock in ctx.rocks do
		alive = alive or rock.Id == guide.DummyId
	end
	if not alive then
		local spot = dummySpot(name)
		if spot then
			local dummy = ctx.newRock(RockTypes.Rock, spot, GuidedConfig.DummySpeed)
			guide.DummyId = dummy.Id
			return dummy
		end
	end
	return nil
end

return table.freeze(Guided)
