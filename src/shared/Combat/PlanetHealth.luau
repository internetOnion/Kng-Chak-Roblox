--!strict
--[[
	PlanetHealth: the planet's HP and shield, as percentages.

	    local health = PlanetHealth.new()
	    health.Changed:Connect(function(hp, delta) ... end)
	    health.Depleted:Connect(function() ... end)
	    health:TakeDamage(8)

	HP starts full (ArenaConfig.PlanetMaxHp, 100) and stays between 0 and full.
	Heals fill HP to full first; the rest builds the shield, up to MaxShield
	(ArenaConfig.PlanetMaxShield, 25). Damage takes the shield first, then HP.
	Read health.Hp and health.Shield but never set them; use the methods so the events fire.
	Once HP reaches 0 the planet is depleted: damage and heals do nothing until Reset().

	Events:
	    Changed       (hp: number, delta: number)      after every HP change; delta < 0 for damage
	    ShieldChanged (shield: number, delta: number)  after every shield change
	    Depleted      ()                               once, when HP reaches 0
]]

local ArenaConfig = require("../Data/ArenaConfig")
local Signal = require("../Util/Signal")

local PlanetHealth = {}
PlanetHealth.__index = PlanetHealth

export type PlanetHealth = typeof(setmetatable(
	{} :: {
		Hp: number,
		MaxHp: number,
		Shield: number,
		MaxShield: number,
		Changed: Signal.Signal,
		ShieldChanged: Signal.Signal,
		Depleted: Signal.Signal,
	},
	PlanetHealth
))

-- A planet at `startHp` (default: full).
function PlanetHealth.new(maxHp: number?, maxShield: number?, startHp: number?): PlanetHealth
	local max = maxHp or ArenaConfig.PlanetMaxHp
	return setmetatable({
		Hp = math.clamp(startHp or max, 0, max),
		MaxHp = max,
		Shield = 0,
		MaxShield = maxShield or ArenaConfig.PlanetMaxShield,
		Changed = Signal.new(),
		ShieldChanged = Signal.new(),
		Depleted = Signal.new(),
	}, PlanetHealth)
end

function PlanetHealth.IsDepleted(self: PlanetHealth): boolean
	return self.Hp <= 0
end

local function setShield(self: PlanetHealth, shield: number)
	local before = self.Shield
	if shield ~= before then
		self.Shield = shield
		self.ShieldChanged:Fire(shield, shield - before)
	end
end

function PlanetHealth.TakeDamage(self: PlanetHealth, amount: number)
	if amount <= 0 or self:IsDepleted() then
		return
	end
	local soaked = math.min(self.Shield, amount)
	setShield(self, self.Shield - soaked)
	amount -= soaked
	if amount <= 0 then
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
	if amount <= 0 or self:IsDepleted() then
		return
	end
	local fill = math.min(self.MaxHp - self.Hp, amount)
	if fill > 0 then
		local before = self.Hp
		self.Hp = before + fill
		self.Changed:Fire(self.Hp, fill)
	end
	setShield(self, math.min(self.MaxShield, self.Shield + amount - fill))
end

-- Changes the shield cap (an upgrade raised it). A shield above the new cap drops to it.
function PlanetHealth.SetMaxShield(self: PlanetHealth, maxShield: number)
	self.MaxShield = maxShield
	if self.Shield > maxShield then
		setShield(self, maxShield)
	end
end

-- Refill to full, with no shield, for a new run.
function PlanetHealth.Reset(self: PlanetHealth)
	local before = self.Hp
	self.Hp = self.MaxHp
	if self.Hp ~= before then
		self.Changed:Fire(self.Hp, self.Hp - before)
	end
	setShield(self, 0)
end

function PlanetHealth.Destroy(self: PlanetHealth)
	self.Changed:DisconnectAll()
	self.ShieldChanged:DisconnectAll()
	self.Depleted:DisconnectAll()
end

return PlanetHealth
