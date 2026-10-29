--!strict
--[[
	ContractsDemo (Studio only): a sandbox for the week-1 contracts.

	Spawns one rock of each type in a row, smallest to largest, with a top-down
	camera on them. Then it primes the plain rock, breaks the shard, hits the
	planet with the iron rock and bumps the ship, so the EventLogger prints each event.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local GameEvents = require(KngChak.GameEvents)
local PlanetHealth = require(KngChak.Combat.PlanetHealth)
local Rock = require(KngChak.Rocks.Rock)
local RockTypes = require(KngChak.Data.RockTypes)
local ShipController = require(KngChak.Ship.ShipController)

local ROW_Y = 30 -- arena y of the row of rocks
local GAP = 3 -- arena units between rocks
local CAMERA_HEIGHT = 40

local ORDER = { "Shard", "Comet", "Rock", "Gold", "Iron", "Cluster" }

return function()
	local folder = Instance.new("Folder")
	folder.Name = "ContractsDemo"
	folder.Parent = workspace

	local width = GAP * (#ORDER - 1)
	for _, id in ORDER do
		width += RockTypes[id].Radius * 2
	end

	local rocks: { [string]: Rock.Rock } = {}
	local x = -width / 2
	for _, id in ORDER do
		local rockType = RockTypes[id]
		x += rockType.Radius
		rocks[id] = Rock.new(rockType, Vector2.new(x, ROW_Y), folder)
		x += rockType.Radius + GAP
	end

	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local target = ArenaSpace.ToWorld(Vector2.new(0, ROW_Y))
	camera.CFrame = CFrame.lookAt(target + Vector3.yAxis * CAMERA_HEIGHT, target, -Vector3.zAxis)

	local health = PlanetHealth.new()
	health.Changed:Connect(function(hp: number, delta: number)
		print(`[ContractsDemo] planet HP {hp}% ({delta})`)
	end)

	local ship = ShipController.new()
	ship.Bumped:Connect(function(rock: Rock.Rock, knock: Vector2)
		print(`[ContractsDemo] ship bumped by {rock.Type.Id}, knock {knock}`)
	end)

	task.wait(2)
	GameEvents.WaveStarted:Fire(1)

	task.wait(1)
	rocks.Rock:Prime()
	ship:Bump(rocks.Rock, Vector2.new(0, -14))

	task.wait(1)
	rocks.Shard:Break("Ram")

	task.wait(1)
	local iron = rocks.Iron
	GameEvents.PlanetHit:Fire(iron, iron.Type.DamagePercent)
	health:TakeDamage(iron.Type.DamagePercent)
	iron:Destroy()
end
