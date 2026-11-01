--!strict
local Districts = require("@shared/Data/Districts")
local OutlineBudget = require("@shared/Arena/OutlineBudget")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

describe("OutlineBudget", function()
	it("gives every visible model a Highlight up to Roblox's 31 limit", function()
		local list: { OutlineBudget.Candidate } = {}
		for i = 1, Districts.MaxHighlights do
			table.insert(list, { Key = i, Visible = true, Tier = 3, Distance = i * 2 })
		end
		local chosen = OutlineBudget.Select(list)
		local highlights = 0
		for i = 1, Districts.MaxHighlights do
			expect(chosen[i]).toBe(true)
			highlights += 1
		end
		expect(highlights).toBe(31)
	end)

	it(
		"switches overflow models past 31 to the fallback, keeping heroes, primed and nearest rocks on Highlights",
		function()
			local list: { OutlineBudget.Candidate } = {
				{ Key = 1, Visible = true, Tier = 1, Distance = 24 }, -- Ship
				{ Key = 2, Visible = true, Tier = 1, Distance = 0 }, -- Planet
			}
			-- 33 unprimed rocks from near (12) to far (44), plus 2 primed rocks far out (60)
			for i = 1, 33 do
				table.insert(list, { Key = 10 + i, Visible = true, Tier = 3, Distance = 11 + i })
			end
			table.insert(list, { Key = 100, Visible = true, Tier = 2, Distance = 60 })
			table.insert(list, { Key = 101, Visible = true, Tier = 2, Distance = 62 })

			local chosen = OutlineBudget.Select(list)
			local highlightCount, fallbackCount = 0, 0
			for _, flag in chosen do
				if flag then
					highlightCount += 1
				else
					fallbackCount += 1
				end
			end

			expect(highlightCount).toBe(31)
			expect(fallbackCount).toBe(6)
			-- Heroes and primed rocks always keep their Highlight
			expect(chosen[1]).toBe(true)
			expect(chosen[2]).toBe(true)
			expect(chosen[100]).toBe(true)
			expect(chosen[101]).toBe(true)
			-- Nearest 27 unprimed rocks (Keys 11..37) get Highlights; farthest 6 (Keys 38..43) use fallback
			expect(chosen[37]).toBe(true)
			expect(chosen[38]).toBe(false)
			expect(chosen[43]).toBe(false)
		end
	)

	it("ignores hidden models so off-screen scenes never spend Highlight slots", function()
		local list: { OutlineBudget.Candidate } = {}
		for i = 1, 20 do
			table.insert(list, { Key = i, Visible = false, Tier = 1, Distance = 0 })
		end
		for i = 21, 51 do
			table.insert(list, { Key = i, Visible = true, Tier = 3, Distance = i })
		end
		local chosen = OutlineBudget.Select(list)
		expect(chosen[1]).toBe(nil)
		for i = 21, 51 do
			expect(chosen[i]).toBe(true)
		end
	end)
end)
