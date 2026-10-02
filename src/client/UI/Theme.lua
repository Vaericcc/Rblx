--!strict
return {
	-- match screens (dark)
	bg = Color3.fromRGB(24, 24, 32),
	panel = Color3.fromRGB(36, 36, 48),
	panelAlt = Color3.fromRGB(50, 50, 66),
	accent = Color3.fromRGB(255, 196, 61),
	accent2 = Color3.fromRGB(94, 200, 255),
	danger = Color3.fromRGB(255, 92, 92),
	good = Color3.fromRGB(96, 220, 140),
	text = Color3.fromRGB(245, 245, 250),
	textDim = Color3.fromRGB(170, 170, 190),
	paper = Color3.fromRGB(252, 250, 240),

	-- menu system (ink and paper, Persona / Dishonored energy)
	ink = Color3.fromRGB(18, 16, 20),
	inkSoft = Color3.fromRGB(44, 40, 48),
	cream = Color3.fromRGB(240, 234, 220),
	creamDark = Color3.fromRGB(214, 206, 188),
	pop = Color3.fromRGB(255, 70, 110),

	-- fonts
	fontDisplay = Enum.Font.Bangers, -- headings, buttons, vertical titles
	font = Enum.Font.GothamBold, -- small bold labels
	fontBody = Enum.Font.GothamMedium, -- body copy
	fontHand = Enum.Font.PatrickHand, -- showcase speech bubbles
	radius = UDim.new(0, 12),

	-- drawing palette
	palette = {
		Color3.fromRGB(20, 20, 20),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(120, 120, 120),
		Color3.fromRGB(230, 60, 60),
		Color3.fromRGB(255, 150, 50),
		Color3.fromRGB(255, 220, 60),
		Color3.fromRGB(80, 200, 90),
		Color3.fromRGB(60, 150, 255),
		Color3.fromRGB(150, 90, 230),
		Color3.fromRGB(255, 130, 200),
		Color3.fromRGB(140, 90, 50),
		Color3.fromRGB(255, 210, 170),
	},
	brushSizes = { 3, 8, 16, 30 },
}
