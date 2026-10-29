--!strict
local Controls = require("@shared/Input/Controls")
local ControlsConfig = require("@shared/Data/ControlsConfig")
local Run = require("@shared/Run/Run")
local TestKit = require("@testkit")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local NONE = { boostPressed = false, boostHeld = false, brake = false }
local TAP = { boostPressed = true, boostHeld = true, brake = false }

describe("Controls", function()
	describe("cursor", function()
		it("coasts with the cursor inside the deadzone", function()
			local input = Controls.FromCursor(Vector2.new(ControlsConfig.CursorDeadzone - 0.1, 0), NONE)
			expect(input.MoveStrength).toBe(0)
		end)

		it("steers toward the cursor, faster the farther it is", function()
			local near = Controls.FromCursor(Vector2.new(0, ControlsConfig.CursorDeadzone + 3), NONE)
			local far = Controls.FromCursor(Vector2.new(0, 100), NONE)
			expect(near.Move).toBe(Vector2.new(0, 1))
			expect(near.MoveStrength).toBeCloseTo(3 / ControlsConfig.CursorFullRange)
			expect(far.MoveStrength).toBe(1)
		end)
	end)

	describe("stick", function()
		it("maps screen up to arena up", function()
			local input = Controls.FromStick(Vector2.new(0, -ControlsConfig.StickRadius), NONE)
			expect(input.Move.X).toBeCloseTo(0)
			expect(input.Move.Y).toBeCloseTo(1)
			expect(input.MoveStrength).toBe(1)
		end)

		it("sets speed from how far it's dragged, past the deadzone", function()
			local radius, deadzone = ControlsConfig.StickRadius, ControlsConfig.StickDeadzone
			expect(Controls.FromStick(Vector2.new(radius * deadzone * 0.5, 0), NONE).MoveStrength).toBe(0)
			local half = Controls.FromStick(Vector2.new(radius * (deadzone + (1 - deadzone) / 2), 0), NONE)
			expect(half.MoveStrength).toBeCloseTo(0.5)
			expect(Controls.FromStick(Vector2.new(radius * 3, 0), NONE).MoveStrength).toBe(1)
		end)

		it("brakes when the thumb lets go, and keeps the boost buttons", function()
			local input = Controls.FromStick(nil, TAP)
			expect(input.Brake).toBe(true)
			expect(input.MoveStrength).toBe(0)
			expect(input.BoostPressed).toBe(true)
		end)

		it("eases the ship to a stop after letting go", function()
			local run = Run.new({ Waves = {}, ShipStart = Vector2.new(-40, -20), ShipHeading = 0 })
			local push = Controls.FromStick(Vector2.new(ControlsConfig.StickRadius, 0), NONE)
			for _ = 1, 120 do
				run:Step(push, 1 / 60)
			end
			expect(run:Snapshot().Ship.Velocity.Magnitude > 10).toBe(true)
			local release = Controls.FromStick(nil, NONE)
			for _ = 1, 180 do
				run:Step(release, 1 / 60)
			end
			expect(run:Snapshot().Ship.Velocity.Magnitude < 0.1).toBe(true)
		end)
	end)
end)
