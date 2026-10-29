--!strict
--[[
	PlanetHealth: the planet's HP as a percentage (milestone 1, contract 2, area 3).

	    local health = PlanetHealth.new()
	    health.Changed:Connect(function(hp, delta) ... end)
	    health.Depleted:Connect(function() ... end)
	    health:TakeDamage(8)

	HP starts full (ArenaConfig.PlanetMaxHp, 100) and stays between 0 and full.
	Read health.Hp but never set it; use the methods so the events fire.
	Once HP reaches 0 the planet is depleted: damage and heals do nothing until Reset().
	The shield (repairs above 100%) comes in milestone 2.

	Events:
	    Changed  (hp: number, delta: number)  after every change; delta < 0 for damage
	    Depleted ()                           once, when HP reaches 0
]]

local ArenaConfig = require("../Data/ArenaConfig")
local Signal = require("../Util/Signal")

local PlanetHealth = {}
PlanetHealth.__index = PlanetHealth

export type PlanetHealth = typeof(setmetatable(
	{} :: {
		Hp: number,
		MaxHp: number,
		Changed: Signal.Signal,
		Depleted: Signal.Signal,
	},
	PlanetHealth
))

function PlanetHealth.new(maxHp: number?): PlanetHealth
	local max = maxHp or ArenaConfig.PlanetMaxHp
	return setmetatable({
		Hp = max,
		MaxHp = max,
		Changed = Signal.new(),
		Depleted = Signal.new(),
	}, PlanetHealth)
end

function PlanetHealth.IsDepleted(self: PlanetHealth): boolean
	return self.Hp <= 0
end

function PlanetHealth.TakeDamage(self: PlanetHealth, amount: number)
	if amount <= 0 or self:IsDepleted() then
		return
	end
	local before = self.Hp
	self.Hp = math.max(0, before - amount)
	self.Changed:Fire(self.Hp, self.Hp - before)
	if self.Hp <= 0 then
		self.Depleted:Fire()
	end
end

function PlanetHealth.Heal(self: PlanetHealth, amount: number)
	if amount <= 0 or self:IsDepleted() or self.Hp >= self.MaxHp then
		return
	end
	local before = self.Hp
	self.Hp = math.min(self.MaxHp, before + amount)
	self.Changed:Fire(self.Hp, self.Hp - before)
end

-- Refill to full for a new run.
function PlanetHealth.Reset(self: PlanetHealth)
	local before = self.Hp
	self.Hp = self.MaxHp
	if self.Hp ~= before then
		self.Changed:Fire(self.Hp, self.Hp - before)
	end
end

function PlanetHealth.Destroy(self: PlanetHealth)
	self.Changed:DisconnectAll()
	self.Depleted:DisconnectAll()
end

return PlanetHealth
