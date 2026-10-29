--!strict
--[[
	Orbit: the orbit band and the locked orbit track, ported from the web prototype.

	Flying below the top of the band (ArenaConfig.OrbitBandTop above the surface)
	locks the ship onto the orbit track at OrbitAlt, so it can never hit the planet.
	In orbit the ship circles the planet: steering along the orbit speeds it up,
	against it slows it down (past zero it turns round). Aiming outward, at least
	OrbitExitDot away from the planet, leaves the orbit. Flight calls into this
	module; the Run never does.

	Leaving within CaptureTime of locking on launches a free slingshot dive: the
	ship flies out at slingshot speed with the spear out, locked onto the rock
	ahead if there is one. After CaptureTime the ship is captured: aiming out no
	longer leaves, and only a boost (which costs fuel) gets it out.
]]

local Context = require("../Run/Context")
local Rock = require("../Rocks/Rock")
local Ship = require("./Ship")
local Tuning = require("../Run/Tuning")

local Orbit = {}

local function wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- The unit vector out from the planet's centre through `position`, and the orbit's direction of travel there.
local function frame(position: Vector2, dir: number): (Vector2, Vector2)
	local outward = if position.Magnitude > 1e-6 then position.Unit else Vector2.new(0, -1)
	return outward, Vector2.new(-outward.Y, outward.X) * dir
end

-- True when the ship at `position` is inside the band (below its top).
function Orbit.InBand(position: Vector2, tuning: Tuning.Tuning): boolean
	local arena = tuning.Arena
	return position.Magnitude - arena.PlanetRadius < arena.OrbitBandTop
end

-- Locks the ship onto the orbit, keeping the way round it was heading.
function Orbit.Enter(ship: Ship.Ship, ctx: Context.Context)
	local config = ctx.tuning.Ship
	local outward = frame(ship.Position, 1)
	local motion = outward:Cross(ship.Velocity)
	local nose = outward:Cross(ship.Facing)
	ship.OrbitDir = if (if math.abs(motion) > 1 then motion else nose) >= 0 then 1 else -1
	local _, along = frame(ship.Position, ship.OrbitDir)
	ship.OrbitSpeed = math.clamp(math.abs(ship.Velocity:Dot(along)), config.OrbitEntryMin, config.OrbitMaxSpeed)
	ship.Velocity = along * ship.OrbitSpeed
	ship.IsInOrbit = true
	ship.IsCaptured = false
	ship.OrbitTime = 0
	ship.BoostTime = 0
	ship.SlingshotTime = 0
	ship.LockId = nil
	ctx.events.OrbitLocked:Fire()
end

-- Leaves the orbit from where the ship is, heading along `angle` (radians).
function Orbit.Leave(ship: Ship.Ship, ctx: Context.Context, angle: number)
	local config = ctx.tuning.Ship
	ship.IsInOrbit = false
	ship.IsCaptured = false
	ship.OrbitRelock = config.OrbitRelockTime
	ship.ExitTime = config.BoostExitTime
	ship.Heading = angle
	ship.Velocity = Vector2.new(math.cos(angle), math.sin(angle)) * math.max(ship.OrbitSpeed, config.MaxSpeed * 0.8)
	ctx.events.OrbitLeft:Fire()
end

-- Where to leave toward when the player aims `want`: their aim if it points outward, else 45° out and ahead.
function Orbit.ExitAngle(ship: Ship.Ship, want: number?): number
	local outward, along = frame(ship.Position, ship.OrbitDir)
	if want and Vector2.new(math.cos(want), math.sin(want)):Dot(outward) >= 0.2 then
		return want
	end
	local out = outward + along
	return math.atan2(out.Y, out.X)
end

-- True when steering toward `want` aims far enough outward to leave.
function Orbit.AimsOut(ship: Ship.Ship, tuning: Tuning.Tuning, want: number): boolean
	local outward = frame(ship.Position, ship.OrbitDir)
	return Vector2.new(math.cos(want), math.sin(want)):Dot(outward) > tuning.Ship.OrbitExitDot
end

-- The rock a slingshot launched along `heading` locks onto: the nearest one ahead, favouring straight ahead.
local function lockTarget(ship: Ship.Ship, ctx: Context.Context, heading: number): Rock.Rock?
	local config = ctx.tuning.Ship
	local facing = Vector2.new(math.cos(heading), math.sin(heading))
	local cosCone = math.cos(math.rad(config.LockConeDeg))
	local best, bestScore = nil, math.huge
	for _, rock in ctx.rocks do
		local offset = rock.Position - ship.Position
		local distance = offset.Magnitude
		if distance >= 0.5 and distance <= config.LockRange then
			local ahead = offset:Dot(facing) / distance
			local score = distance * (2 - ahead)
			if ahead >= cosCone and score < bestScore then
				best, bestScore = rock, score
			end
		end
	end
	return best
end

-- Launches a slingshot dive along the ship's heading, locking onto the rock ahead if there is one.
function Orbit.Slingshot(ship: Ship.Ship, ctx: Context.Context)
	local config = ctx.tuning.Ship
	ship.SlingshotCooldown = config.SlingshotCooldown
	local target = lockTarget(ship, ctx, ship.Heading)
	if target then
		local offset = target.Position - ship.Position
		ship.Heading = math.atan2(offset.Y, offset.X)
		ship.LockId = target.Id
		-- stop just past the locked rock rather than flinging across the arena
		ship.SlingshotTime = math.clamp(offset.Magnitude / config.SlingshotSpeed + 0.12, 0.15, config.SlingshotDuration)
	else
		ship.LockId = nil
		ship.SlingshotTime = config.SlingshotNoTarget
	end
	ship.IsSlingshotting = true
	ship.Velocity = Vector2.new(math.cos(ship.Heading), math.sin(ship.Heading)) * config.SlingshotSpeed
	ctx.events.Slingshot:Fire(if target then Rock.Snapshot(target) else nil)
end

-- Moves the ship along the orbit for dt, steered toward `want` (radians) if set.
function Orbit.Step(ship: Ship.Ship, ctx: Context.Context, want: number?, dt: number)
	local tuning = ctx.tuning
	local config = tuning.Ship
	local arena = tuning.Arena
	local radius = ship.Position.Magnitude
	if want then
		local _, along = frame(ship.Position, ship.OrbitDir)
		ship.OrbitSpeed += Vector2.new(math.cos(want), math.sin(want)):Dot(along) * config.OrbitAccel * dt
	end
	if ship.OrbitSpeed < 0 then
		ship.OrbitDir = -ship.OrbitDir
		ship.OrbitSpeed = -ship.OrbitSpeed
	end
	ship.OrbitSpeed = math.min(ship.OrbitSpeed, config.OrbitMaxSpeed)

	local track = arena.PlanetRadius + arena.OrbitAlt
	local settled = radius + (track - radius) * math.min(1, config.OrbitSnap * dt)
	local angle = math.atan2(ship.Position.Y, ship.Position.X) + ship.OrbitDir * ship.OrbitSpeed / settled * dt
	ship.Position = Vector2.new(math.cos(angle), math.sin(angle)) * settled

	local _, along = frame(ship.Position, ship.OrbitDir)
	ship.Velocity = along * ship.OrbitSpeed
	local heading = math.atan2(along.Y, along.X)
	ship.Heading = wrapAngle(ship.Heading + wrapAngle(heading - ship.Heading) * math.min(1, 10 * dt))
	ship.OrbitTime += dt
	if not ship.IsCaptured and ship.OrbitTime >= config.CaptureTime then
		ship.IsCaptured = true
		ctx.events.OrbitCaptured:Fire()
	end
end

return table.freeze(Orbit)
