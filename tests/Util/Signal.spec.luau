--!strict
local Signal = require("@shared/Util/Signal")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

describe("Signal", function()
	it("calls handlers in the order they connected, with the fired arguments", function()
		local signal = Signal.new()
		local calls = {}
		signal:Connect(function(a, b)
			table.insert(calls, `first {a} {b}`)
		end)
		signal:Connect(function(a, b)
			table.insert(calls, `second {a} {b}`)
		end)
		signal:Fire(1, "x")
		expect(calls).toEqual({ "first 1 x", "second 1 x" })
	end)

	it("stops calling a handler after Disconnect", function()
		local signal = Signal.new()
		local count = 0
		local connection = signal:Connect(function()
			count += 1
		end)
		signal:Fire()
		connection:Disconnect()
		signal:Fire()
		expect(count).toBe(1)
		expect(connection.Connected).toBe(false)
	end)

	it("calls a Once handler only the first time", function()
		local signal = Signal.new()
		local count = 0
		signal:Once(function()
			count += 1
		end)
		signal:Fire()
		signal:Fire()
		expect(count).toBe(1)
	end)

	it("lets a handler disconnect another during the same Fire, without skipping anyone", function()
		local signal = Signal.new()
		local calls = {}
		local second
		signal:Connect(function()
			table.insert(calls, "first")
			second:Disconnect()
		end)
		second = signal:Connect(function()
			table.insert(calls, "second")
		end)
		signal:Connect(function()
			table.insert(calls, "third")
		end)
		signal:Fire()
		expect(calls).toEqual({ "first", "third" })
	end)

	it("disconnects everything on DisconnectAll", function()
		local signal = Signal.new()
		local count = 0
		local a = signal:Connect(function()
			count += 1
		end)
		signal:Connect(function()
			count += 1
		end)
		signal:DisconnectAll()
		signal:Fire()
		expect(count).toBe(0)
		expect(a.Connected).toBe(false)
	end)
end)
