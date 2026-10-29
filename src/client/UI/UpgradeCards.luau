--!strict
--[[
	UpgradeCards: the cards offered after a wave. Tap one to pick it.

	    local cards = UpgradeCards.new(playerGui, function(index) run:PickUpgrade(index) end)
	    cards:Update(run:Snapshot(), true) -- every frame: shows while Phase is "UpgradePick" and `active`

	Each card shows the upgrade's family colour, name, effect and how many of its
	stacks are taken. The words come from Data/Upgrades. The cards only read the
	snapshot; the pick goes through the callback, which the game turns into the
	Run's PickUpgrade command.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local KngChak = ReplicatedStorage.KngChak
local Run = require(KngChak.Run.Run)
local Upgrades = require(KngChak.Data.Upgrades)

local Fonts = require(script.Parent.Fonts)

local FAMILY_COLORS: { [string]: Color3 } = {
	Flame = Color3.fromHex("#ff4a1c"),
	Spear = Color3.fromHex("#f4f6ff"),
	Orbit = Color3.fromHex("#6ff3ff"),
	Any = Color3.fromHex("#ffd400"),
}
local CARD = Color3.fromHex("#1b1a5c")
local TEXT = Color3.fromHex("#ffffff")
local CARD_SIZE = Vector2.new(190, 230)
local GAP = 18

local UpgradeCards = {}
UpgradeCards.__index = UpgradeCards

type Card = {
	button: TextButton,
	stripe: Frame,
	family: TextLabel,
	name: TextLabel,
	effect: TextLabel,
	stacks: TextLabel,
	scale: UIScale,
}

export type UpgradeCards = typeof(setmetatable(
	{} :: {
		_gui: ScreenGui,
		_cards: { Card },
		_shown: string?, -- the offer on screen, as one string, so a new offer redraws
		_onPick: (index: number) -> (),
	},
	UpgradeCards
))

local function label(parent: Instance, name: string, font: Font, size: number, y: number, height: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.Position = UDim2.fromOffset(12, y)
	text.Size = UDim2.new(1, -24, 0, height)
	text.BackgroundTransparency = 1
	text.FontFace = font
	text.TextSize = size
	text.TextColor3 = TEXT
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Parent = parent
	return text
end

local function card(parent: Instance, index: number, onPick: (number) -> ()): Card
	local button = Instance.new("TextButton")
	button.Name = `Card{index}`
	button.Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y)
	button.BackgroundColor3 = CARD
	button.AutoButtonColor = true
	button.Text = ""
	button.LayoutOrder = index
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.fromHex("#000000")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	local scale = Instance.new("UIScale")
	scale.Parent = button

	local stripe = Instance.new("Frame")
	stripe.Name = "Stripe"
	stripe.Size = UDim2.new(1, 0, 0, 14)
	stripe.BorderSizePixel = 0
	stripe.Parent = button
	local stripeCorner = Instance.new("UICorner")
	stripeCorner.CornerRadius = UDim.new(0, 18)
	stripeCorner.Parent = stripe

	local self: Card = {
		button = button,
		stripe = stripe,
		family = label(button, "Family", Fonts.TextBold, 16, 24, 20),
		name = label(button, "Name", Fonts.Display, 30, 46, 70),
		effect = label(button, "Effect", Fonts.Text, 20, 118, 80),
		stacks = label(button, "Stacks", Fonts.TextBold, 16, CARD_SIZE.Y - 30, 20),
		scale = scale,
	}
	button.Activated:Connect(function()
		onPick(index)
	end)
	button.Parent = parent
	return self
end

function UpgradeCards.new(parent: Instance, onPick: (index: number) -> ()): UpgradeCards
	local gui = Instance.new("ScreenGui")
	gui.Name = "UpgradeCards"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.ScreenInsets = Enum.ScreenInsets.None -- the dim covers the whole screen; the cards sit mid-screen
	gui.Enabled = false

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromHex("#1b1a5c")
	dim.BackgroundTransparency = 0.5
	dim.BorderSizePixel = 0
	dim.Parent = gui

	local heading = Instance.new("TextLabel")
	heading.Name = "Heading"
	heading.AnchorPoint = Vector2.new(0.5, 1)
	heading.Position = UDim2.new(0.5, 0, 0.5, -CARD_SIZE.Y / 2 - 12)
	heading.Size = UDim2.new(1, 0, 0, 44)
	heading.BackgroundTransparency = 1
	heading.FontFace = Fonts.Display
	heading.TextSize = 36
	heading.TextColor3 = Color3.fromHex("#ffe066")
	heading.TextStrokeTransparency = 0.3
	heading.Text = "PICK AN UPGRADE"
	heading.Parent = gui

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.5)
	row.Size = UDim2.fromOffset(CARD_SIZE.X * 3 + GAP * 2, CARD_SIZE.Y)
	row.BackgroundTransparency = 1
	row.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	-- shrink the row on small screens so three cards always fit
	local fit = Instance.new("UIScale")
	fit.Parent = row

	local self = setmetatable({ _gui = gui, _cards = {}, _shown = nil :: string?, _onPick = onPick }, UpgradeCards)
	for index = 1, Upgrades.OfferSize do
		table.insert(
			self._cards,
			card(row, index, function(i)
				if self._gui.Enabled then
					self._onPick(i)
				end
			end)
		)
	end
	local function refit()
		local size = gui.AbsoluteSize
		local wide = (CARD_SIZE.X * 3 + GAP * 2 + 32) / math.max(1, size.X)
		local tall = (CARD_SIZE.Y + 140) / math.max(1, size.Y)
		fit.Scale = math.min(1, 1 / math.max(wide, tall))
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	refit()
	gui.Parent = parent
	return self
end

function UpgradeCards.Update(self: UpgradeCards, snapshot: Run.Snapshot, active: boolean)
	local offer = if active and snapshot.Phase == "UpgradePick" then snapshot.Offer else nil
	if not offer then
		self._shown = nil
		self._gui.Enabled = false
		return
	end
	local key = table.concat(offer, ",")
	if self._shown == key then
		return
	end
	self._shown = key
	for index, drawn in self._cards do
		local id = offer[index]
		drawn.button.Visible = id ~= nil
		if id then
			local upgrade = Upgrades.ById[id]
			local color = FAMILY_COLORS[upgrade.Family]
			drawn.stripe.BackgroundColor3 = color
			drawn.family.Text = string.upper(upgrade.Family)
			drawn.family.TextColor3 = color
			drawn.name.Text = upgrade.Name
			drawn.effect.Text = upgrade.Text
			local taken = snapshot.Upgrades[id] or 0
			drawn.stacks.Text = if upgrade.MaxStacks == 1 then "Once" else `{taken + 1} of {upgrade.MaxStacks}`
			drawn.scale.Scale = 0.6
			TweenService:Create(
				drawn.scale,
				TweenInfo.new(0.22 + 0.06 * index, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1 }
			):Play()
		end
	end
	self._gui.Enabled = true
end

return UpgradeCards
