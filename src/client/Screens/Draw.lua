--!strict
-- Drawing phase: N panel tabs, palette, brush sizes, undo/clear.
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Canvas = require(UI.Canvas)
local StoryInfo = require(UI.StoryInfo)

local Draw = {}

function Draw.show(container: Frame, data: any, ctx: any)
	local root = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })

	-- Left: tools column
	local tools = Make("Frame", {
		BackgroundColor3 = Theme.panel,
		Size = UDim2.new(0, 64, 1, 0),
		Make.corner(),
		Make.pad(8),
		Make.list(nil, 6, Enum.HorizontalAlignment.Center),
		Parent = root,
	})
	-- Center: canvas + panel tabs
	local center = Make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.62, -80, 1, 0),
		Position = UDim2.new(0, 72, 0, 0),
		Parent = root,
	})
	-- Right: story info
	local right = Make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.38, -8, 1, 0),
		Position = UDim2.new(0.62, 0, 0, 0),
		Parent = root,
	})

	local panelCount: number = data.panels
	local panelData: { any } = {}
	local currentPanel = 1

	local tabs = Make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 36),
		Make.list(Enum.FillDirection.Horizontal, 6),
		Parent = center,
	})
	local canvasHolder = Make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -44),
		Position = UDim2.new(0, 0, 0, 44),
		Parent = center,
	})
	local canvas = Canvas.new(canvasHolder, true)
	canvas.onChange = function()
		panelData[currentPanel] = canvas:getStrokes()
		ctx.markDirty()
	end

	local tabButtons = {}
	local function selectPanel(i: number)
		panelData[currentPanel] = canvas:getStrokes()
		currentPanel = i
		canvas:setStrokes(panelData[i] or {})
		for j, b in tabButtons do
			b.BackgroundColor3 = if j == i then Theme.accent else Theme.panelAlt
			b.TextColor3 = if j == i then Theme.bg else Theme.text
		end
	end
	for i = 1, panelCount do
		local b = Make.button(("Panel %d"):format(data.startIndex + i - 1), Theme.panelAlt, function() selectPanel(i) end, {
			Size = UDim2.new(0, 100, 1, 0), TextSize = 14, TextColor3 = Theme.text,
		})
		b.Parent = tabs
		tabButtons[i] = b
	end
	selectPanel(1)

	-- Palette
	local swatches = {}
	for i, color in Theme.palette do
		local sw = Make("TextButton", {
			Text = "",
			BackgroundColor3 = color,
			Size = UDim2.fromOffset(40, 24),
			LayoutOrder = i,
			Make.corner(UDim.new(0, 6)),
			Make("UIStroke", { Color = Theme.text, Thickness = if i == 1 then 2 else 0 }),
			Parent = tools,
		})
		sw.Activated:Connect(function()
			canvas.color = color
			for _, s in swatches do (s:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = 0 end
			(sw:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = 2
		end)
		table.insert(swatches, sw)
	end
	-- Brush sizes
	Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 6), LayoutOrder = 50, Parent = tools })
	local sizeButtons = {}
	for i, size in Theme.brushSizes do
		local b = Make("TextButton", {
			Text = "",
			BackgroundColor3 = Theme.panelAlt,
			Size = UDim2.fromOffset(44, 30),
			LayoutOrder = 50 + i,
			Make.corner(UDim.new(0, 6)),
			Make("Frame", {
				BackgroundColor3 = Theme.text,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(4 + size * 0.6, 4 + size * 0.6),
				Make.corner(UDim.new(0.5, 0)),
			}),
			Parent = tools,
		})
		b.Activated:Connect(function()
			canvas.width = size
			for _, s in sizeButtons do s.BackgroundColor3 = Theme.panelAlt end
			b.BackgroundColor3 = Theme.accent2
		end)
		sizeButtons[i] = b
	end
	sizeButtons[2].BackgroundColor3 = Theme.accent2

	Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 6), LayoutOrder = 90, Parent = tools })
	Make.button("↶", Theme.panelAlt, function() canvas:undo() end, { Size = UDim2.fromOffset(44, 34), LayoutOrder = 91, TextColor3 = Theme.text, Parent = tools })
	Make.button("✕", Theme.danger, function() canvas:clear() end, { Size = UDim2.fromOffset(44, 34), LayoutOrder = 92, Parent = tools })

	StoryInfo.build(right, {
		premise = data.premise,
		cast = data.cast,
		prompt = data.prompt,
		ownerName = data.ownerName,
		lines = data.lines,
	})

	return {
		collect = function()
			panelData[currentPanel] = canvas:getStrokes()
			local out = {}
			for i = 1, panelCount do out[i] = panelData[i] or {} end
			return out
		end,
		destroy = function() canvas:destroy() root:Destroy() end,
	}
end

return Draw
