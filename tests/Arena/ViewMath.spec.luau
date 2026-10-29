--!strict
local ArenaConfig = require("@shared/Data/ArenaConfig")
local TestKit = require("@testkit")
local ViewMath = require("@shared/Arena/ViewMath")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local ASPECT = 16 / 9
local VIEW = ViewMath.ViewHalf(ArenaConfig, ASPECT)

-- Fraction of the planet's width on screen along one axis, for a camera centred at `centre`.
local function planetShown(centre: number, half: number): number
	local radius = ArenaConfig.PlanetRadius
	local left, right = math.max(-radius, centre - half), math.min(radius, centre + half)
	return math.max(0, right - left) / (2 * radius)
end

describe("ViewMath", function()
	it("shows CamView units from the centre to the nearer screen edge", function()
		expect(VIEW.Y).toBe(ArenaConfig.CamView)
		expect(VIEW.X).toBeCloseTo(ArenaConfig.CamView * ASPECT, 1e-3)
		expect(ViewMath.ViewHalf(ArenaConfig, 0.5).X).toBe(ArenaConfig.CamView)
	end)

	it("stays on the planet while the ship is close to it", function()
		local focus = ViewMath.CameraFocus(ArenaConfig, Vector2.new(0, ArenaConfig.CamNear - 1), VIEW)
		expect(focus).toBe(Vector2.zero)
	end)

	it("centres on the ship once it's far out", function()
		local ship = Vector2.new(ArenaConfig.CamFar + 2, 3)
		expect(ViewMath.CameraFocus(ArenaConfig, ship, VIEW)).toBe(ship)
	end)

	it("eases between the planet and the ship in between", function()
		local middle = (ArenaConfig.CamNear + ArenaConfig.CamFar) / 2
		local focus = ViewMath.CameraFocus(ArenaConfig, Vector2.new(middle, 0), VIEW)
		expect(focus.X).toBeCloseTo(middle / 2)
	end)

	it("keeps at least CamPlanetShow of the planet on screen everywhere in the arena", function()
		-- a small zoom makes the leash matter
		local arena = table.clone(ArenaConfig) :: any
		arena.CamView = 30
		local view = ViewMath.ViewHalf(arena, ASPECT)
		for angle = 0, 359, 15 do
			local ship = Vector2.new(math.cos(math.rad(angle)), math.sin(math.rad(angle))) * arena.ArenaRadius
			local focus = ViewMath.CameraFocus(arena, ship, view)
			local onX = planetShown(focus.X, view.X)
			local onY = planetShown(focus.Y, view.Y)
			expect(math.min(onX, onY) >= arena.CamPlanetShow - 1e-6).toBe(true)
		end
	end)

	it("hides the edge until the ship is within EdgeShowDist of it, then fades it in", function()
		local radius, show = ArenaConfig.ArenaRadius, ArenaConfig.EdgeShowDist
		expect(ViewMath.EdgeVisibility(ArenaConfig, Vector2.new(0, radius - show - 1))).toBe(0)
		expect(ViewMath.EdgeVisibility(ArenaConfig, Vector2.new(0, radius - show / 2))).toBeCloseTo(0.5)
		expect(ViewMath.EdgeVisibility(ArenaConfig, Vector2.new(radius, 0))).toBe(1)
	end)
end)
