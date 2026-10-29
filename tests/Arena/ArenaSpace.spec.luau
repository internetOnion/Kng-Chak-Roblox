--!strict
local ArenaConfig = require("@shared/Data/ArenaConfig")
local ArenaSpace = require("@shared/Arena/ArenaSpace")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

describe("ArenaSpace", function()
	it("puts arena +x on world +X and arena +y on world -Z, at the plane's height", function()
		local world = ArenaSpace.ToWorld(Vector2.new(3, 5))
		expect(world).toBe(Vector3.new(3, ArenaConfig.PlaneHeight, -5))
	end)

	it("lifts a position off the plane", function()
		expect(ArenaSpace.ToWorld(Vector2.zero, 2).Y).toBe(ArenaConfig.PlaneHeight + 2)
	end)

	it("round-trips arena positions through the world", function()
		local position = Vector2.new(-12.5, 40)
		expect(ArenaSpace.ToArena(ArenaSpace.ToWorld(position, 7))).toBe(position)
	end)

	it("faces a CFrame along an arena direction", function()
		local look = ArenaSpace.CFrameAt(Vector2.zero, Vector2.new(0, 1)).LookVector
		expect(look.X).toBeCloseTo(0)
		expect(look.Z).toBeCloseTo(-1)
	end)
end)
