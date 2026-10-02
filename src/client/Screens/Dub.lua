--!strict
-- Dub phase: flip through the finished panels and write a line for each.
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Canvas = require(UI.Canvas)
local Layout = require(UI.Layout)
local StoryInfo = require(UI.StoryInfo)
local TextPhases = require(script.Parent.TextPhases)

local Dub = {}

function Dub.show(container: Frame, data: any, ctx: any)
	local project = data.project
	local main, side = Layout.split(container, { mainFraction = 0.5 })

	local tabs = Make.row(36, 6, { Parent = main })
	local canvasArea = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -44), Position = UDim2.fromOffset(0, 44), Parent = main })
	local canvas = Canvas.new(canvasArea, false)

	local castNames = {}
	for _, c in project.cast do table.insert(castNames, c.name) end

	if data.blind then
		local note = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = side })
		Make.label("🙈 BLIND DUB. You don't get the premise or the cast. Name the characters yourself and make it up.", 14, {
			TextColor3 = Theme.accent, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = note,
		})
	else
		local info = StoryInfo.build(side, { premise = project.premise, cast = project.cast, ownerName = project.ownerName })
		info.Size = UDim2.new(1, 0, 0, 0)
		info.AutomaticSize = Enum.AutomaticSize.Y
	end

	local editors = {}
	local tabButtons = {}
	local function selectPanel(i: number)
		canvas:setStrokes(project.panels[i].strokes)
		for j, b in tabButtons do
			b.BackgroundColor3 = if j == i then Theme.accent else Theme.panelAlt
			b.TextColor3 = if j == i then Theme.bg else Theme.text
		end
		for j, e in editors do
			(e.frame :: Frame).BackgroundColor3 = if j == i then Theme.panelAlt else Theme.panel
		end
	end
	for i = 1, #project.panels do
		tabButtons[i] = Make.pill(("Panel %d"):format(i), false, function() selectPanel(i) end, { Size = UDim2.new(0, 84, 1, 0), Parent = tabs })
		editors[i] = TextPhases.lineEditor(side, i, castNames, ctx, 3)
		local hit = Make("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(-14, -14), Parent = editors[i].frame })
		hit.Activated:Connect(function() selectPanel(i) end)
	end
	selectPanel(1)

	return {
		collect = function()
			local out = {}
			for _, e in editors do
				for _, l in e.collect() do table.insert(out, l) end
			end
			return out
		end,
		destroy = function() canvas:destroy() container:ClearAllChildren() end,
	}
end

return Dub
