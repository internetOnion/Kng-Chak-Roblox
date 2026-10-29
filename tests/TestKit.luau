--!strict
--[[
	TestKit: describe / it / expect for the headless test runner.

	    local TestKit = require("@testkit")
	    local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

	    describe("PlanetHealth", function()
	        it("starts full", function()
	            expect(PlanetHealth.new().Hp).toBe(100)
	        end)
	    end)

	A spec file registers its tests when the runner requires it; the runner then
	runs them one by one. A failed expect raises an error, which fails that test only.
]]

export type Test = {
	name: string,
	fn: () -> (),
}

local TestKit = {}

local registered: { Test } = {}
local path: { string } = {}

local function show(value: any): string
	if type(value) == "string" then
		return `"{value}"`
	end
	return tostring(value)
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

function TestKit.describe(name: string, body: () -> ())
	table.insert(path, name)
	body()
	table.remove(path)
end

function TestKit.it(name: string, fn: () -> ())
	local full = table.clone(path)
	table.insert(full, name)
	table.insert(registered, { name = table.concat(full, " > "), fn = fn })
end

-- Hands the registered tests to the runner and starts a fresh list.
function TestKit.collect(): { Test }
	local tests = registered
	registered = {}
	return tests
end

function TestKit.expect(actual: any)
	local matchers = {}

	function matchers.toBe(expected: any)
		if actual ~= expected then
			error(`expected {show(expected)}, got {show(actual)}`, 2)
		end
	end

	function matchers.toEqual(expected: any)
		if not deepEqual(actual, expected) then
			error(`expected a value equal to {show(expected)}, got {show(actual)}`, 2)
		end
	end

	function matchers.toBeCloseTo(expected: number, tolerance: number?)
		local within = tolerance or 1e-6
		if type(actual) ~= "number" or math.abs(actual - expected) > within then
			error(`expected {show(expected)} (within {within}), got {show(actual)}`, 2)
		end
	end

	function matchers.toThrow()
		if type(actual) ~= "function" then
			error("toThrow needs a function", 2)
		end
		if pcall(actual) then
			error("expected the function to throw, but it didn't", 2)
		end
	end

	return matchers
end

return TestKit
