--!strict
--[[
	Outlines: Toy Box outlines across every 3D model, respecting Roblox's 31-Highlight cap.

	    local handle = Outlines.Register(model, radius, Outlines.Tier.Hero)
	    handle:SetState(true, isPrimed, distanceFromPlanet)
	    ...
	    Outlines.Step(arena.CamTilt) -- once per frame, after views move their models

	Roblox renders at most 31 Highlight instances at once across the client. Outlines
	counts every visible registered model through shared/Arena/OutlineBudget: the
	first 31 (heroes -> primed rocks -> rocks nearest the planet) use their Highlight,
	and any past 31 fall back to a slightly larger silhouette copy drawn behind the
	shape along the camera's line of sight (black normally, pink while primed).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KngChak = ReplicatedStorage.KngChak
local Districts = require(KngChak.Data.Districts)
local OutlineBudget = require(KngChak.Arena.OutlineBudget)

local DEFAULT_TILT_DEG = 18

export type ShellPair = {
	source: BasePart,
	shell: BasePart,
}

export type Handle = {
	SetState: (self: Handle, visible: boolean, primed: boolean, distance: number, tier: number?) -> (),
	Unregister: (self: Handle) -> (),
}

type Entry = {
	key: number,
	model: Model,
	highlight: Highlight,
	radius: number,
	tier: number,
	visible: boolean,
	primed: boolean,
	distance: number,
	sources: { BasePart },
	fallback: Folder?,
	pairs: { ShellPair },
	appliedHighlight: boolean?,
	appliedPrimed: boolean?,
}

local Outlines = {
	Tier = table.freeze({
		Hero = 1,
		PrimedRock = 2,
		Rock = 3,
		Decor = 4,
	}),
}

local nextKey = 1
local entries: { [number]: Entry } = {}
local limitOverride: number? = nil

local function ensureHighlight(model: Model): Highlight
	local existing = model:FindFirstChild("Outline")
	if existing and existing:IsA("Highlight") then
		return existing
	end
	local anyHighlight = model:FindFirstChildOfClass("Highlight")
	if anyHighlight then
		return anyHighlight
	end
	local created = Instance.new("Highlight")
	created.Name = "Outline"
	created.OutlineColor = Districts.Outline
	created.OutlineTransparency = 0
	created.FillColor = Districts.Primed
	created.FillTransparency = 1
	created.DepthMode = Enum.HighlightDepthMode.Occluded
	created.Parent = model
	return created
end

local function collectSources(model: Model): { BasePart }
	local list: { BasePart } = {}
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") and desc.Material ~= Enum.Material.Neon and not desc:GetAttribute("NoOutline") then
			table.insert(list, desc)
		end
	end
	return list
end

local function buildFallback(entry: Entry): Folder
	local folder = Instance.new("Folder")
	folder.Name = `{entry.model.Name}_OutlineFallback`
	local pad = math.clamp(0.18 + entry.radius * 0.05, 0.2, 0.36)
	local pairs: { ShellPair } = {}

	for _, src in entry.sources do
		local shell = src:Clone()
		shell.Name = "Shell"
		shell:ClearAllChildren()
		for _, child in src:GetChildren() do
			if child:IsA("DataModelMesh") then
				child:Clone().Parent = shell
			end
		end
		shell.Anchored = true
		shell.CanCollide = false
		shell.CanTouch = false
		shell.CanQuery = false
		shell.CastShadow = false
		shell.Size = src.Size + Vector3.one * pad
		shell.Parent = folder
		table.insert(pairs, { source = src, shell = shell })
	end

	entry.fallback = folder
	entry.pairs = pairs
	return folder
end

function Outlines.Register(model: Model, radius: number, tier: number?): Handle
	local key = nextKey
	nextKey += 1

	local highlight = ensureHighlight(model)
	local entry: Entry = {
		key = key,
		model = model,
		highlight = highlight,
		radius = math.max(0.5, radius),
		tier = tier or Outlines.Tier.Rock,
		visible = true,
		primed = false,
		distance = 0,
		sources = collectSources(model),
		fallback = nil,
		pairs = {},
		appliedHighlight = nil,
		appliedPrimed = nil,
	}
	entries[key] = entry

	local handle: Handle = {
		SetState = function(_self: Handle, visible: boolean, primed: boolean, distance: number, newTier: number?)
			entry.visible = visible
			entry.primed = primed
			entry.distance = distance
			if newTier then
				entry.tier = newTier
			end
		end,
		Unregister = function(_self: Handle)
			entries[key] = nil
			if entry.fallback then
				entry.fallback:Destroy()
				entry.fallback = nil
			end
		end,
	}
	return handle
end

-- Studio/test helper: temporarily lowers or resets the 31-Highlight budget to inspect fallback hulls.
function Outlines.SetLimitOverride(limit: number?)
	limitOverride = limit
end

function Outlines.GetLimitOverride(): number?
	return limitOverride
end

function Outlines.Step(camTiltDeg: number?)
	local candidates: { OutlineBudget.Candidate } = {}
	for key, entry in entries do
		if not entry.model.Parent and not entry.fallback then
			-- Keep dormant detached models (e.g. hidden StyleTile) registered but invisible.
			table.insert(candidates, {
				Key = key,
				Visible = false,
				Tier = entry.tier,
				Distance = entry.distance,
			})
		else
			local inWorld = entry.visible and entry.model:IsDescendantOf(workspace)
			table.insert(candidates, {
				Key = key,
				Visible = inWorld,
				Tier = entry.tier,
				Distance = entry.distance,
			})
		end
	end

	local chosen = OutlineBudget.Select(candidates, limitOverride)
	local tilt = math.rad(camTiltDeg or DEFAULT_TILT_DEG)
	-- Directly along the camera's look ray (away from camera), so the silhouette is centred on screen.
	local awayFromCamera = Vector3.new(0, -math.cos(tilt), -math.sin(tilt))

	for key, entry in entries do
		local selection = chosen[key]
		if selection == nil then
			if entry.appliedHighlight ~= false then
				entry.highlight.Enabled = false
				entry.appliedHighlight = false
			end
			if entry.fallback and entry.fallback.Parent ~= nil then
				entry.fallback.Parent = nil
			end
		elseif selection == true then
			if entry.fallback and entry.fallback.Parent ~= nil then
				entry.fallback.Parent = nil
			end
			if entry.appliedHighlight ~= true or entry.appliedPrimed ~= entry.primed then
				entry.appliedHighlight = true
				entry.appliedPrimed = entry.primed
				local color = if entry.primed then Districts.Primed else Districts.Outline
				entry.highlight.Enabled = true
				entry.highlight.OutlineColor = color
				entry.highlight.FillColor = Districts.Primed
				entry.highlight.FillTransparency = if entry.primed then Districts.PrimedFill else 1
			end
		else
			if entry.appliedHighlight ~= false then
				entry.highlight.Enabled = false
				entry.appliedHighlight = false
			end
			local folder = entry.fallback or buildFallback(entry)
			local parent = entry.model.Parent
			if folder.Parent ~= parent then
				folder.Parent = parent
			end
			local color = if entry.primed then Districts.Primed else Districts.Outline
			-- Pure black Neon is unlit with zero sun glare and below the 1.4 bloom threshold;
			-- SmoothPlastic keeps primed pink saturated without blowing out bloom.
			local material = if entry.primed then Enum.Material.SmoothPlastic else Enum.Material.Neon
			local offset = awayFromCamera * (entry.radius * 0.65 + 0.25)
			for _, pair in entry.pairs do
				local src = pair.source
				local shell = pair.shell
				local hidden = src.Transparency >= 0.99
				shell.Transparency = if hidden then 1 else 0
				if not hidden then
					shell.Color = color
					shell.Material = material
					shell.CFrame = src.CFrame + offset
				end
			end
			entry.appliedPrimed = entry.primed
		end
	end
end

return table.freeze(Outlines)
