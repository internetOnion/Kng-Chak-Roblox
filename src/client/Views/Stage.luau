--!strict
--[[
	Stage: the Toy Box sky, stars and lighting the game is played under.

	    Stage.Light()                                    -- once, when the client starts
	    Stage.Sky(folder, Vector2.zero, Vector2.new(180, 130))   -- a sky behind an area

	The values come from variant A of the art-style prototype, settled in the style
	tile and recorded in docs/art-guide.md: bright daylight from above and slightly
	behind the camera with real shadows, a little bloom so energy glows, and colour
	correction for saturation. Anything else in Lighting (a template's atmosphere
	haze, depth of field, sun rays, bloom) is switched off on this client, so the
	look doesn't depend on the place. The sky is a flat violet backdrop below the play
	plane with white and yellow Neon stars on it (stars are energy, so they glow).
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaSpace = require(ReplicatedStorage.KngChak.Arena.ArenaSpace)

local SKY = Color3.fromHex("#3d3ad8")
local STAR = Color3.fromHex("#ffffff")
local STAR_YELLOW = Color3.fromHex("#ffe066")
local SKY_LIFT = -16 -- studs below the play plane (see the art guide's heights)
local STARS_PER_STUD2 = 0.004

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

-- Builds the sky backdrop and its stars behind `centre` (arena units), `half` units out each way.
function Stage.Sky(parent: Instance, centre: Vector2, half: Vector2): Folder
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
	backdrop.Color = SKY
	backdrop.Size = Vector3.new(half.X * 2, 1, half.Y * 2)
	backdrop.CFrame = CFrame.new(ArenaSpace.ToWorld(centre, SKY_LIFT))
	backdrop.Parent = folder

	-- Scattered once with their own random numbers: the sky is decoration, not part of the Run.
	local random = Random.new(7)
	local count = math.floor(half.X * half.Y * 4 * STARS_PER_STUD2)
	for _ = 1, count do
		local star = Instance.new("Part")
		star.Shape = Enum.PartType.Ball
		star.Anchored = true
		star.CanCollide = false
		star.CanTouch = false
		star.CanQuery = false
		star.CastShadow = false
		star.Material = Enum.Material.Neon
		star.Color = if random:NextNumber() < 0.8 then STAR else STAR_YELLOW
		-- a little bigger than the prototype's 0.3–0.9: the game's camera sits a bit farther away
		star.Size = Vector3.one * random:NextNumber(0.4, 1.1)
		local at = centre + Vector2.new(random:NextNumber(-half.X, half.X), random:NextNumber(-half.Y, half.Y))
		star.CFrame = CFrame.new(ArenaSpace.ToWorld(at, SKY_LIFT + 1))
		star.Parent = folder
	end

	folder.Parent = parent
	return folder
end

return table.freeze(Stage)
