--!strict
--[[
	Threat: which rock will hit the planet soonest, and where each one lands.

	Ported from the web prototype's threat order. A rock's ETA is its height above
	the planet's surface over its fall speed; the rock with the smallest ETA is the
	threat (it gets the threat ring and the only off-screen chevron). A rock lands
	where the line from it to the planet's centre meets the surface.

	The Run puts the threat's id in its snapshot (Snapshot.ThreatId); views and
	the radar read that and the helpers here, and never change anything.
]]

local Rock = require("./Rock")

local Threat = {}

local MIN_SPEED = 0.5 -- a hanging or pushed-back rock still counts as on its way

-- A rock this many seconds from hitting is urgent: the hints turn red and pulse.
Threat.UrgentEta = 4

-- Seconds until `rock` reaches the surface of a planet of `planetRadius`, at its fall speed.
function Threat.Eta(rock: Rock.Rock, planetRadius: number): number
	return math.max(0, rock.Position.Magnitude - planetRadius) / math.max(MIN_SPEED, rock.FallSpeed)
end

-- The rock that will hit soonest, or nil when there are none. The Inferno's parts never hit on their own.
function Threat.Soonest(rocks: { Rock.Rock }, planetRadius: number): Rock.Rock?
	local best, bestEta = nil, math.huge
	for _, rock in rocks do
		if rock.Type.IsBossPart then
			continue
		end
		local eta = Threat.Eta(rock, planetRadius)
		if eta < bestEta then
			best, bestEta = rock, eta
		end
	end
	return best
end

-- Where `rock` will land: the point on the planet's surface straight below it.
function Threat.ImpactPoint(rock: Rock.Rock, planetRadius: number): Vector2
	local position = rock.Position
	if position.Magnitude < 1e-6 then
		return Vector2.new(0, planetRadius)
	end
	return position.Unit * planetRadius
end

return table.freeze(Threat)
