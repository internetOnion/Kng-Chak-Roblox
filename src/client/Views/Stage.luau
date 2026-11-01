--!strict
--[[
	Stage: the Toy Box sky, two-layer parallax stars and lighting the game is played under.

	    Stage.Light()                                                 -- once, when the client starts
	    local sky = Stage.Sky(workspace, Vector2.zero, SKY_HALF)      -- builds backdrop + 2 star layers
	    sky:Update(cameraFocus)                                       -- every frame: shifts star layers for depth

	The lighting values come from variant A of the art-style prototype, settled in the
	style tile and recorded in docs/art-guide.md: bright daylight from above and slightly
	behind the camera with real shadows, mild bloom so energy glows, and colour correction
	for saturation. Anything else in Lighting (a template's atmosphere haze, depth of
	field, sun rays, bloom) is switched off on this client.

	The sky colours come from Data/Districts. Two star layers (far and near) plus soft
	district nebula patches follow the camera at different rates so panning across the
	arena gives clear Toy Box depth.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local ArenaSpace = require(KngChak.Arena.ArenaSpace)
local Districts = require(KngChak.Data.Districts)

local SKY_LIFT = -16 -- studs below the play plane (see the art guide's heights)
local FAR_LIFT = SKY_LIFT + 0.7
local NEAR_LIFT = SKY_LIFT + 2.2
local FAR_STARS_PER_STUD2 = 0.0026
local NEAR_STARS_PER_STUD2 = 0.0018
local NEBULA_BLOBS = 7

local LIGHTING = {
	ClockTime = 13.5,
	GeographicLatitude = 20,
	Brightness = 2.6,
	Ambient = Color3.fromHex("#8c86c8"),
	OutdoorAmbient = Color3.fromHex("#b8b2ff"),
	GlobalShadows = true,
}
local BLOOM = { Intensity = 0.35, Size = 18, Threshold = 1.4 }
local GRADE = { Saturation = 0.25, Contrast = 0.12, Brightness = 0.04 }

local SkyView = {}
SkyView.__index = SkyView

export type SkyView = typeof(setmetatable(
	{} :: {
		Folder: Folder,
		_centre: Vector2,
		_district: Districts.District,
		_backdrop: BasePart,
		_farModel: Model,
		_nearModel: Model,
		_nebulaParts: { BasePart },
		_primaryStars: { BasePart },
		_accentStars: { BasePart },
	},
	SkyView
))

local Stage = {}

local function effect(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = Lighting
	return created
end

-- Sets the Toy Box lighting. Only this client's copy of Lighting changes.
function Stage.Light()
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") then
			child.Density = 0
			child.Haze = 0
			child.Glare = 0
		elseif child:IsA("PostEffect") and child.Name ~= "ToyBoxBloom" and child.Name ~= "ToyBoxGrade" then
			child.Enabled = false
		end
	end
	for key, value in LIGHTING do
		(Lighting :: any)[key] = value
	end
	local bloom = effect("BloomEffect", "ToyBoxBloom") :: any
	for key, value in BLOOM do
		bloom[key] = value
	end
	local grade = effect("ColorCorrectionEffect", "ToyBoxGrade") :: any
	for key, value in GRADE do
		grade[key] = value
	end
end

local function makeStarLayer(
	parent: Instance,
	name: string,
	centre: Vector2,
	half: Vector2,
	lift: number,
	density: number,
	minSize: number,
	maxSize: number,
	transparency: number,
	seed: number,
	district: Districts.District,
	primaryOut: { BasePart },
	accentOut: { BasePart }
): Model
	local layer = Instance.new("Model")
	layer.Name = name
	local anchor = ArenaSpace.ToWorld(centre, lift)

	local random = Random.new(seed)
	local count = math.floor(half.X * half.Y * 4 * density)
	for _ = 1, count do
		local star = Instance.new("Part")
		star.Name = "Star"
		star.Shape = Enum.PartType.Ball
		star.Anchored = true
		star.CanCollide = false
		star.CanTouch = false
		star.CanQuery = false
		star.CastShadow = false
		star.Material = Enum.Material.Neon
		star.Transparency = transparency
		local isPrimary = random:NextNumber() < 0.8
		star.Color = if isPrimary then district.StarPrimary else district.StarAccent
		star.Size = Vector3.one * random:NextNumber(minSize, maxSize)
		local at = centre + Vector2.new(random:NextNumber(-half.X, half.X), random:NextNumber(-half.Y, half.Y))
		star.CFrame = CFrame.new(ArenaSpace.ToWorld(at, lift))
		star.Parent = layer
		if isPrimary then
			table.insert(primaryOut, star)
		else
			table.insert(accentOut, star)
		end
	end

	layer.WorldPivot = CFrame.new(anchor)
	layer.Parent = parent
	return layer
end

-- Builds the sky backdrop, soft nebula patches and two parallax star layers behind `centre`.
function Stage.Sky(parent: Instance, centre: Vector2, half: Vector2, district: Districts.District?): SkyView
	local chosen = district or Districts.Default
	local folder = Instance.new("Folder")
	folder.Name = "Sky"

	local backdrop = Instance.new("Part")
	backdrop.Name = "Backdrop"
	backdrop.Anchored = true
	backdrop.CanCollide = false
	backdrop.CanTouch = false
	backdrop.CanQuery = false
	backdrop.CastShadow = false
	backdrop.Material = Enum.Material.SmoothPlastic
	backdrop.Color = chosen.Sky
	backdrop.Size = Vector3.new(half.X * 2.5, 1, half.Y * 2.5)
	backdrop.CFrame = CFrame.new(ArenaSpace.ToWorld(centre, SKY_LIFT))
	backdrop.Parent = folder

	local primaryStars: { BasePart } = {}
	local accentStars: { BasePart } = {}
	local nebulaParts: { BasePart } = {}

	local farModel = makeStarLayer(
		folder,
		"FarStars",
		centre,
		half,
		FAR_LIFT,
		FAR_STARS_PER_STUD2,
		0.35,
		0.72,
		0.2,
		7,
		chosen,
		primaryStars,
		accentStars
	)

	-- Soft Toy Box nebula clouds in the far layer, tinted from district data
	local nebulaRng = Random.new(19)
	for i = 1, NEBULA_BLOBS do
		local cloud = Instance.new("Part")
		cloud.Name = `Nebula{i}`
		cloud.Anchored = true
		cloud.CanCollide = false
		cloud.CanTouch = false
		cloud.CanQuery = false
		cloud.CastShadow = false
		cloud.Material = Enum.Material.SmoothPlastic
		cloud.Color = chosen.Nebula
		cloud.Transparency = 0.72 + nebulaRng:NextNumber(0, 0.12)
		local rx = nebulaRng:NextNumber(22, 46)
		local rz = rx * nebulaRng:NextNumber(0.65, 1.15)
		cloud.Size = Vector3.new(rx, 0.4, rz)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = cloud
		local at = centre
			+ Vector2.new(
				nebulaRng:NextNumber(-half.X * 0.75, half.X * 0.75),
				nebulaRng:NextNumber(-half.Y * 0.75, half.Y * 0.75)
			)
		cloud.CFrame = CFrame.new(ArenaSpace.ToWorld(at, SKY_LIFT + 0.35))
			* CFrame.Angles(0, math.rad(nebulaRng:NextNumber(0, 180)), 0)
		cloud.Parent = farModel
		table.insert(nebulaParts, cloud)
	end

	local nearModel = makeStarLayer(
		folder,
		"NearStars",
		centre,
		half,
		NEAR_LIFT,
		NEAR_STARS_PER_STUD2,
		0.62,
		1.2,
		0,
		23,
		chosen,
		primaryStars,
		accentStars
	)

	folder.Parent = parent
	return setmetatable({
		Folder = folder,
		_centre = centre,
		_district = chosen,
		_backdrop = backdrop :: BasePart,
		_farModel = farModel,
		_nearModel = nearModel,
		_nebulaParts = nebulaParts,
		_primaryStars = primaryStars,
		_accentStars = accentStars,
	}, SkyView)
end

-- Shifts both star layers relative to the camera's arena focus for multi-plane depth.
function SkyView.Update(self: SkyView, cameraFocus: Vector2)
	local offset = cameraFocus - self._centre
	local farAt = self._centre + offset * self._district.FarFollow
	local nearAt = self._centre + offset * self._district.NearFollow
	self._backdrop.CFrame = CFrame.new(ArenaSpace.ToWorld(self._centre + offset * 0.85, SKY_LIFT))
	self._farModel:PivotTo(CFrame.new(ArenaSpace.ToWorld(farAt, FAR_LIFT)))
	self._nearModel:PivotTo(CFrame.new(ArenaSpace.ToWorld(nearAt, NEAR_LIFT)))
end

-- Re-tints the backdrop, nebula and star layers from another district's palette.
function SkyView.SetDistrict(self: SkyView, district: Districts.District)
	if self._district == district then
		return
	end
	self._district = district
	self._backdrop.Color = district.Sky
	for _, cloud in self._nebulaParts do
		cloud.Color = district.Nebula
	end
	for _, star in self._primaryStars do
		star.Color = district.StarPrimary
	end
	for _, star in self._accentStars do
		star.Color = district.StarAccent
	end
end

function SkyView.Destroy(self: SkyView)
	self.Folder:Destroy()
end

return table.freeze(Stage)
