--!strict
--[[
	Fonts: the UI's typefaces.

	The brand fonts (Atomic Age for display, Jost for text) aren't among Roblox's
	font families, so the closest built-in ones stand in (see docs/art-guide.md).
]]

local Fonts = {
	-- Display (stands in for Atomic Age): round and chunky, for the toy look
	Display = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular),
	-- Text and numbers (stand in for Jost): geometric sans
	Text = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Medium),
	TextBold = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold),
}

return table.freeze(Fonts)
