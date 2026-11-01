--!strict
--[[
	PlanetView: draws and spins the planet at the arena's centre, painted from district data.

	    local planet = PlanetView.new(folder, nil, Districts.Ember)
	    planet:Update(dt) -- every frame: gently spins the globe around its north polar axis

	The model is a clone of ReplicatedStorage.Assets.Planet.Planet, built at radius 10
	around the origin with north along -Z, and scaled to ArenaConfig.PlanetRadius.
	Ocean, Land, LandDark, Ice and Rim parts take their colours from the district's
	palette ("tint, don't rebuild"), so Glacier and Foundry reuse the same asset.
	The glowing Rim part sits outside the globe's Highlight so the black Toy Box
	outline hugs the solid surface and the atmosphere halos cleanly round it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaConfig = require(KngChak.Data.ArenaConfig)
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local Districts = require(KngChak.Data.Districts)

local Outlines = require(script.Parent.Outlines)

local MODEL_RADIUS = 10 -- the radius the asset is built at
-- Matches the north polar ice cap placement in Planet.model.json so spinning keeps north at the top.
local POLAR_AXIS = Vector3.new(0, 5.5397, -7.2).Unit

local PlanetView = {}
PlanetView.__index = PlanetView

export type PlanetView = typeof(setmetatable(
	{} :: {
		_container: Folder,
		_model: Model,
		_rim: BasePart?,
		_rimOffset: Vector3,
		_baseCFrame: CFrame,
		_angle: number,
		_district: Districts.District,
		_outline: Outlines.Handle,
	},
	PlanetView
))

local function paintDistrict(model: Model, rim: BasePart?, district: Districts.District)
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			local name = inst.Name
			if string.sub(name, 1, 5) == "Ocean" then
				inst.Color = district.Ocean
			elseif string.sub(name, 1, 8) == "LandDark" then
				inst.Color = district.LandDark
			elseif string.sub(name, 1, 4) == "Land" then
				inst.Color = district.Land
			elseif string.sub(name, 1, 3) == "Ice" then
				inst.Color = district.Ice
			end
		end
	end
	if rim then
		rim.Color = district.Rim
		rim.Transparency = district.RimTransparency
	end
end

-- A planet at `centre` (default: the arena's centre), painted with `district` (default: Ember).
function PlanetView.new(parent: Instance, centre: Vector2?, district: Districts.District?): PlanetView
	local chosen = district or Districts.Default
	local assets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Planet")
	local prefab = (
		assets:FindFirstChild("kc_planet_ember")
		or assets:FindFirstChild("Planet")
		or assets:FindFirstChildWhichIsA("Model")
	) :: Model

	local container = Instance.new("Folder")
	container.Name = "Planet"

	local model = prefab:Clone()
	model.WorldPivot = CFrame.identity -- assets are built around the origin; Studio may have picked another pivot
	model:ScaleTo(ArenaConfig.PlanetRadius / MODEL_RADIUS)

	local baseCFrame = ArenaSpace.CFrameAt(centre or Vector2.zero)
	model:PivotTo(baseCFrame)

	-- Pull Rim outside the highlighted globe Model so the black outline hugs Ocean and Rim halos outside it.
	local rimPart: BasePart? = nil
	local rimOffset = Vector3.zero
	local foundRim = model:FindFirstChild("Rim")
	if foundRim and foundRim:IsA("BasePart") then
		rimPart = foundRim
		rimOffset = foundRim.Position - baseCFrame.Position
		foundRim.Parent = container
	end

	paintDistrict(model, rimPart, chosen)
	model.Parent = container
	container.Parent = parent

	local outline = Outlines.Register(model, ArenaConfig.PlanetRadius, Outlines.Tier.Hero)
	outline:SetState(true, false, 0, Outlines.Tier.Hero)

	return setmetatable({
		_container = container,
		_model = model,
		_rim = rimPart,
		_rimOffset = rimOffset,
		_baseCFrame = baseCFrame,
		_angle = 0,
		_district = chosen,
		_outline = outline,
	}, PlanetView)
end

function PlanetView.Update(self: PlanetView, dt: number)
	self._angle = (self._angle + self._district.SpinRate * dt) % (2 * math.pi)
	local spin = CFrame.fromAxisAngle(POLAR_AXIS, self._angle)
	self._model:PivotTo(CFrame.new(self._baseCFrame.Position) * spin * self._baseCFrame.Rotation)
	if self._rim then
		self._rim.CFrame = CFrame.new(self._baseCFrame.Position + self._rimOffset)
	end
end

function PlanetView.SetDistrict(self: PlanetView, district: Districts.District)
	if self._district == district then
		return
	end
	self._district = district
	paintDistrict(self._model, self._rim, district)
end

function PlanetView.Destroy(self: PlanetView)
	self._outline:Unregister()
	self._container:Destroy()
end

return PlanetView
