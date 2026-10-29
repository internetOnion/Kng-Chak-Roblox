--!strict
--[[
	Pilot: a scripted player for tests and balance runs. It reads only the Run's
	snapshot and gives only flight input, the way a player would.

	    run:Step(Pilot.Input(run:Snapshot(), run:GetTuning()), dt)

	It plays the core loop, not well but honestly:
	- Plain targets (rocks, the Inferno's plates): stand off a little, fly away from
	  the target so the flame primes it, then turn and boost into it.
	- Targets only a PERFECT breaks (gold, the Inferno's core): drop into orbit,
	  circle until the flare catches the target, then aim out at it to slingshot.
	It picks the rock that will hit the planet soonest, the core once exposed, or
	the nearest plate.
]]

local Run = require("@shared/Run/Run")
local RunInput = require("@shared/Run/RunInput")
local Threat = require("@shared/Rocks/Threat")
local Tuning = require("@shared/Run/Tuning")

local Pilot = {}

type Rock = typeof((({} :: any) :: Run.Snapshot).Rocks[1])

local STANDOFF = 4.5 -- how far from a target it gets before turning its flame on it
local RAM_RANGE = 12 -- boosts into a primed target this close

local function needsPerfect(rock: Rock): boolean
	return rock.Type.BreaksBy == "Perfect"
end

local function target(snapshot: Run.Snapshot, tuning: Tuning.Tuning): Rock?
	local rocks = snapshot.Rocks
	local ship = snapshot.Ship.Position
	-- the soonest threat first, then the Inferno's core, then its nearest plate
	local loose = {}
	local core, plate, plateDistance = nil, nil, math.huge
	for _, rock in rocks do
		if rock.Type.Id == "Core" then
			core = rock
		elseif rock.Type.IsBossPart then
			local distance = (rock.Position - ship).Magnitude
			if distance < plateDistance then
				plate, plateDistance = rock, distance
			end
		else
			table.insert(loose, rock)
		end
	end
	local soonest = Threat.Soonest(loose, tuning.Arena.PlanetRadius)
	if soonest and Threat.Eta(soonest, tuning.Arena.PlanetRadius) < 12 then
		return soonest
	end
	return core or plate or soonest
end

-- Orbit play: circle until the flare has caught `rock`, then aim out at it.
local function slingshot(snapshot: Run.Snapshot, tuning: Tuning.Tuning, rock: Rock): RunInput.RunInput
	local ship = snapshot.Ship
	if not ship.IsInOrbit then
		if ship.IsSlingshotting then
			return RunInput.steer(rock.Position - ship.Position)
		end
		return RunInput.steer(-ship.Position) -- dive for the band
	end
	if rock.IsPrimed then
		return RunInput.steer(rock.Position - ship.Position)
	end
	-- circle toward the spot under the rock
	local outward = ship.Position.Unit
	local along = Vector2.new(-outward.Y, outward.X) * ship.OrbitDir
	local under = rock.Position.Unit * (tuning.Arena.PlanetRadius + tuning.Arena.OrbitAlt)
	local ahead = (under - ship.Position):Dot(along)
	if math.abs(ahead) < 1.5 and ship.OrbitSpeed > 4 then
		return RunInput.steer(-along, 0.6) -- slow down underneath it
	elseif ship.OrbitSpeed < 10 then
		return RunInput.steer(if ahead >= 0 then along else -along, 0.6)
	end
	return RunInput.Idle
end

-- Push then break: stand off, fly away so the flame primes it, then boost into it.
local function pushBreak(snapshot: Run.Snapshot, tuning: Tuning.Tuning, rock: Rock): RunInput.RunInput
	local ship = snapshot.Ship
	local offset = rock.Position - ship.Position
	local distance = offset.Magnitude
	if ship.IsInOrbit then
		-- leave outward, toward it
		return RunInput.steer(ship.Position.Unit + offset.Unit)
	end
	if rock.IsPrimed then
		local boost = distance < RAM_RANGE and ship.Fuel >= tuning.Ship.BoostCost and not ship.IsSpearOut
		return RunInput.steer(offset, 1, boost, ship.IsSpearOut)
	end
	if distance > STANDOFF + 2 then
		-- head for a spot just short of it, on this side
		local spot = rock.Position - offset.Unit * STANDOFF
		local toSpot = spot - ship.Position
		return RunInput.steer(toSpot, math.clamp(toSpot.Magnitude / 10, 0.3, 1))
	end
	return RunInput.steer(-offset, 0.6) -- the flame streams back over it
end

-- This frame's input for the run in `snapshot`.
function Pilot.Input(snapshot: Run.Snapshot, tuning: Tuning.Tuning): RunInput.RunInput
	local rock = target(snapshot, tuning)
	if not rock then
		-- nothing to hit: wait near the planet, out of the way
		local home = tuning.Arena.ShipStart
		local toHome = home - snapshot.Ship.Position
		if snapshot.Ship.IsInOrbit or toHome.Magnitude < 3 then
			return RunInput.Idle
		end
		return RunInput.steer(toHome, math.clamp(toHome.Magnitude / 15, 0.2, 1))
	end
	if needsPerfect(rock) then
		return slingshot(snapshot, tuning, rock)
	end
	return pushBreak(snapshot, tuning, rock)
end

return table.freeze(Pilot)
