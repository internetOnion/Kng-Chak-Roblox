--!strict
local Districts = require("@shared/Data/Districts")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

describe("Districts data", function()
	it("defines Ember with the Toy Box palette and valid ranges", function()
		local ember = Districts.Ember
		expect(Districts.ById.Ember).toBe(ember)
		expect(Districts.Default).toBe(ember)
		expect(ember.Ocean).toBe(Color3.fromHex("#2fc4ff"))
		expect(ember.Land).toBe(Color3.fromHex("#5ee05e"))
		expect(ember.LandDark).toBe(Color3.fromHex("#3fb34a"))
		expect(ember.Ice).toBe(Color3.fromHex("#ffffff"))
		expect(ember.Sky).toBe(Color3.fromHex("#3d3ad8"))
		expect(ember.RimTransparency > 0 and ember.RimTransparency < 1).toBe(true)
		expect(ember.SpinRate > 0).toBe(true)
		expect(ember.FarFollow > ember.NearFollow).toBe(true)
		expect(ember.NearFollow > 0).toBe(true)
	end)

	it("exposes frozen Primed, Outline and Highlight budget values", function()
		expect(Districts.Outline).toBe(Color3.fromHex("#000000"))
		expect(Districts.Primed).toBe(Color3.fromHex("#ff4fd8"))
		expect(Districts.MaxHighlights).toBe(31)
		local ok = pcall(function()
			(Districts :: any).MaxHighlights = 99
		end)
		expect(ok).toBe(false)
	end)
end)
