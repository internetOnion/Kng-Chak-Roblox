--!strict
--[[
	Flight: moves the ship for one fixed sub-step, ported from the web prototype.

	The nose turns toward where the player steers and the engine only thrusts once
	the nose is within the thrust cone, so the ship flies like a rocket, not a cursor.
	Boost is a short burst at boost speed that costs fuel; holding it keeps it going
	while fuel lasts. The ship slides along the arena edge, so it can't leave the
	arena. Flying into the orbit band locks it onto the orbit (see Ship/Orbit), so
	it can't hit the planet either; there, fuel refills OrbitRegenMult times faster.
	Leaving the orbit can launch a slingshot dive, which flies like a boost at
	slingshot speed and homes on the rock it locked onto.
]]

local Context = require("../Run/Context")
local Orbit = require("./Orbit")
local Rock = require("../Rocks/Rock")
local RunInput = require("../Run/RunInput")
local Ship = require("./Ship")
local Tuning = require("../Run/Tuning")

local Flight = {}

local ORBIT_THROTTLE = 0.6 -- how hard the engine looks to push while circling in orbit

local function wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

local function direction(angle: number): Vector2
	return Vector2.new(math.cos(angle), math.sin(angle))
end

local function withLength(v: Vector2, length: number): Vector2
	local magnitude = v.Magnitude
	return if magnitude > 1e-6 then v * (length / magnitude) else v
end

-- Starts a boost burst if there's fuel for it. Returns whether it started.
local function tryBoost(ship: Ship.Ship, tuning: Tuning.Tuning, want: number?): boolean
	local config = tuning.Ship
	if ship.StunTime > 0 or ship.Fuel < config.BoostCost then
		return false
	end
	ship.Fuel -= config.BoostCost
	ship.BoostTime = config.BoostDuration
	if want then
		ship.Heading = want -- a boost turns the nose sharply, straight away
	end
	return true
end

--[[
	Leaves the orbit toward `want`. Before capture it's free and launches a slingshot
	(unless one was launched too recently). Once captured, only a boost gets out,
	and it costs the boost's fuel. Returns whether the ship left.
]]
local function leaveOrbit(ship: Ship.Ship, ctx: Context.Context, want: number?, viaBoost: boolean): boolean
	local angle = Orbit.ExitAngle(ship, want)
	if not ship.IsCaptured then
		Orbit.Leave(ship, ctx, angle)
		if ship.SlingshotCooldown <= 0 then
			Orbit.Slingshot(ship, ctx)
		end
		return true
	end
	local config = ctx.tuning.Ship
	if not viaBoost or ship.StunTime > 0 or ship.Fuel < config.BoostCost then
		return false
	end
	Orbit.Leave(ship, ctx, angle)
	tryBoost(ship, ctx.tuning, angle)
	return true
end

-- The rock the slingshot is locked onto, if it's still in the arena.
local function lockedRock(ship: Ship.Ship, ctx: Context.Context): Rock.Rock?
	local id = ship.LockId
	if not id then
		return nil
	end
	for _, rock in ctx.rocks do
		if rock.Id == id then
			return rock
		end
	end
	return nil
end

-- Free flight (out of orbit) for dt. Returns whether the engine thrusts.
local function fly(
	ship: Ship.Ship,
	ctx: Context.Context,
	input: RunInput.RunInput,
	want: number?,
	throttle: number,
	braking: boolean,
	dt: number
): boolean
	local tuning = ctx.tuning
	local config = tuning.Ship
	local arena = tuning.Arena

	-- Turn the nose
	local slinging = ship.SlingshotTime > 0
	local rate = config.TurnRate
	if ship.BoostTime > 0 then
		rate = config.BoostTurnRate
	elseif slinging or ship.ExitTime > 0 then
		rate = math.max(rate, config.BoostTurnRate)
	end
	local locked = if slinging then lockedRock(ship, ctx) else nil
	local lockAngle = 0
	if locked then
		local offset = locked.Position - ship.Position
		lockAngle = math.atan2(offset.Y, offset.X)
	end
	if locked and (not want or math.abs(wrapAngle(want - lockAngle)) < math.pi / 3) then
		-- a locked slingshot homes on its rock
		local da = wrapAngle(lockAngle - ship.Heading)
		ship.Heading += math.clamp(da, -rate * dt, rate * dt)
	elseif want then
		ship.LockId = nil -- steering well away cancels the lock
		local da = wrapAngle(want - ship.Heading)
		ship.Heading += math.clamp(da, -rate * dt, rate * dt)
	elseif ship.BoostTime <= 0 and not slinging and ship.Velocity.Magnitude > 2 then
		-- coasting: the nose follows the motion
		local motion = math.atan2(ship.Velocity.Y, ship.Velocity.X)
		ship.Heading += wrapAngle(motion - ship.Heading) * math.min(1, 4 * dt)
	end
	ship.Heading = wrapAngle(ship.Heading)
	local facing = direction(ship.Heading)

	local thrust = want ~= nil
		and throttle > 0.02
		and math.abs(wrapAngle(want - ship.Heading)) < math.rad(config.ThrustConeDeg)
	local cap = config.MaxSpeed * math.max(throttle, 0.15) -- the speed being asked for

	-- Move
	local v = ship.Velocity
	if ship.BoostTime > 0 then
		if input.BoostHeld and ship.BoostTime < 0.05 and ship.Fuel > 0 then
			-- holding boost keeps it going while fuel lasts
			ship.Fuel = math.max(0, ship.Fuel - config.BoostDrain * dt)
			ship.BoostTime = 0.05
		end
		v = facing * config.BoostSpeed
		ship.BoostTime -= dt
		if ship.BoostTime <= 0 then
			ship.BoostTime = 0
			v = withLength(v, config.MaxSpeed * config.BoostCarry)
			ship.ExitTime = config.BoostExitTime
		end
	elseif slinging then
		v = facing * config.SlingshotSpeed
		ship.SlingshotTime -= dt
		if ship.SlingshotTime <= 0 then
			ship.SlingshotTime = 0
			v = withLength(v, config.MaxSpeed * config.BoostCarry)
			ship.ExitTime = config.BoostExitTime
		end
	else
		local speed = v.Magnitude
		if thrust and speed < cap then
			v += facing * math.min(config.ThrustAccel * dt, cap - speed)
		end
		speed = v.Magnitude
		if want and speed > 0.01 then
			-- steering bends momentum toward the nose; coasting keeps it
			local grip = config.Grip
				* (if thrust then 1.6 else 1)
				* (if ship.ExitTime > 0 then config.BoostExitGrip else 1)
			v = v:Lerp(facing * speed, math.min(1, grip * dt))
		end
		if want and speed > 0.5 then
			-- steering against the motion fires retro thrust
			local against = -v:Dot(direction(want)) / speed
			if against > 0 then
				v *= 1 - math.min(1, config.RetroBrake * against * dt)
			end
		end
		speed = v.Magnitude
		if speed > config.MaxSpeed + 0.05 then
			v = withLength(v, math.max(config.MaxSpeed, speed - (speed - config.MaxSpeed) * config.OverspeedDecay * dt))
		else
			local slow
			if braking then
				slow = config.Brake
			elseif want and speed > cap + 0.05 then
				slow = config.ArriveBrake
			else
				slow = config.Drag * (if thrust then 0.2 else 1)
			end
			v *= math.max(0, 1 - slow * dt)
		end
	end

	local position = ship.Position + v * dt

	-- Arena edge: slide along it, no bounce
	local distance = position.Magnitude
	if distance > arena.ArenaRadius then
		local outward = position / distance
		position = outward * arena.ArenaRadius
		local out = v:Dot(outward)
		if out > 0 then
			v -= outward * out
		end
	end

	-- The band locks the ship into orbit. Just after leaving it passes freely, but never below the track.
	if Orbit.InBand(position, tuning) then
		local track = arena.PlanetRadius + arena.OrbitAlt
		distance = position.Magnitude
		if ship.OrbitRelock > 0 and distance < track then
			local outward = if distance > 1e-6 then position / distance else -facing
			position = outward * track
			local inward = v:Dot(outward)
			if inward < 0 then
				v -= outward * inward
			end
		end
		ship.Position = position
		ship.Velocity = v
		if ship.OrbitRelock <= 0 then
			Orbit.Enter(ship, ctx)
		end
		return thrust
	end

	ship.Position = position
	ship.Velocity = v
	return thrust
end

-- Steps the ship by dt. `boostPressed` is true on the one sub-step that takes a new boost press.
function Flight.Step(ship: Ship.Ship, ctx: Context.Context, input: RunInput.RunInput, boostPressed: boolean, dt: number)
	local tuning = ctx.tuning
	local config = tuning.Ship
	local stunned = ship.StunTime > 0

	local want: number? = nil
	local throttle = 0
	if not stunned and input.MoveStrength > 0 and input.Move.Magnitude > 1e-6 then
		want = math.atan2(input.Move.Y, input.Move.X)
		throttle = math.clamp(input.MoveStrength, 0, 1)
	end
	local braking = not stunned and input.Brake

	if boostPressed then
		if ship.IsInOrbit then
			leaveOrbit(ship, ctx, want, true)
		else
			tryBoost(ship, tuning, want)
		end
	end
	if ship.IsInOrbit and want and Orbit.AimsOut(ship, tuning, want) then
		leaveOrbit(ship, ctx, want, false)
	end

	local thrust
	if ship.IsInOrbit then
		Orbit.Step(ship, ctx, want, dt)
		thrust = true
		throttle = ORBIT_THROTTLE
	else
		thrust = fly(ship, ctx, input, want, throttle, braking, dt)
	end
	ship.Facing = direction(ship.Heading)

	-- Fuel refills whenever the ship isn't boosting, faster in orbit
	if ship.BoostTime <= 0 then
		local regen = config.FuelRegen * (if ship.IsInOrbit then config.OrbitRegenMult else 1)
		ship.Fuel = math.min(config.FuelMax, ship.Fuel + regen * dt)
	end

	ship.ExitTime = math.max(0, ship.ExitTime - dt)
	ship.StunTime = math.max(0, ship.StunTime - dt)
	ship.InvulnerableTime = math.max(0, ship.InvulnerableTime - dt)
	ship.OrbitRelock = math.max(0, ship.OrbitRelock - dt)
	ship.SlingshotCooldown = math.max(0, ship.SlingshotCooldown - dt)

	ship.IsThrusting = thrust
	ship.Throttle = if thrust then throttle else 0
	ship.IsBoosting = ship.BoostTime > 0
	ship.IsSlingshotting = ship.SlingshotTime > 0
	ship.IsSpearOut = ship.IsBoosting or ship.IsSlingshotting
	ship.IsStunned = ship.StunTime > 0
	if not ship.IsSlingshotting then
		ship.LockId = nil
	end

	-- The flame is the push zone: throttle sets its reach and a boost flares it. In
	-- orbit it swings round to fan outward, away from the planet (the orbit flare).
	local reach = 0
	if ship.IsStunned then
		reach = 0
	elseif ship.IsInOrbit then
		reach = config.FlareRange
	elseif ship.IsSpearOut then
		reach = config.PushBoostRange
	elseif thrust then
		reach = config.PushRangeMin + (config.PushRange - config.PushRangeMin) * ship.Throttle
	end
	ship.FlameReach += (reach - ship.FlameReach) * math.min(1, 14 * dt)
	if ship.FlameReach < 0.05 then
		ship.FlameReach = 0
	end
	local streamTo = if ship.IsInOrbit then ship.Position else -ship.Facing
	local stream = math.atan2(ship.FlameDirection.Y, ship.FlameDirection.X)
	stream += wrapAngle(math.atan2(streamTo.Y, streamTo.X) - stream) * math.min(1, 12 * dt)
	ship.FlameDirection = direction(stream)
end

return table.freeze(Flight)
