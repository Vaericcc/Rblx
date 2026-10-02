--!strict
-- Dub phase: flip through the finished panels and write a line for each.
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Canvas = require(UI.Canvas)
local StoryInfo = require(UI.StoryInfo)
local TextPhases = require(script.Parent.TextPhases)

local Dub = {}

function Dub.show(container: Frame, data: any, ctx: any)
	local project = data.project
	local root = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })

	local left = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.5, -8, 1, 0), Parent = root })
	local right = Make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.5, -8, 1, 0),
		Position = UDim2.new(0.5, 8, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 6,
		Make.list(nil, 10),
		Parent = root,
	})

	local tabs = Make("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36),
		Make.list(Enum.FillDirection.Horizontal, 6), Parent = left,
	})
	local canvasHolder = Make("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -44), Position = UDim2.new(0, 0, 0, 44), Parent = left,
	})
	local canvas = Canvas.new(canvasHolder, false)

	local castNames = {}
	for _, c in project.cast do table.insert(castNames, c.name) end

	if data.blind then
		local note = Make.card({ Size = UDim2.new(1, 0, 0, 70), Parent = right })
		Make.label("🙈 BLIND DUB: you don't get the premise or the cast. Name the characters yourself and make it up!", 14, {
			TextColor3 = Theme.accent, Size = UDim2.fromScale(1, 1), Parent = note,
		})
	else
		local infoHolder = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = right })
		local info = StoryInfo.build(infoHolder, { premise = project.premise, cast = project.cast, ownerName = project.ownerName })
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
		local b = Make.button(("Panel %d"):format(i), Theme.panelAlt, function() selectPanel(i) end, {
			Size = UDim2.new(0, 90, 1, 0), TextSize = 14, TextColor3 = Theme.text,
		})
		b.Parent = tabs
		tabButtons[i] = b
		editors[i] = TextPhases.lineEditor(right, i, castNames, ctx, 3)
		local f = editors[i].frame :: Frame
		local focusBtn = Make("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(-14, -14), Parent = f })
		focusBtn.Activated:Connect(function() selectPanel(i) end)
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
		destroy = function() canvas:destroy() root:Destroy() end,
	}
end

return Dub
