--!strict
-- Drawing phase: panel tabs, palette, brush sizes, undo/clear, story reference.
-- Regular: tools column | canvas | story panel. Compact: tools bar over canvas, story below.
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Canvas = require(UI.Canvas)
local Layout = require(UI.Layout)
local Responsive = require(UI.Responsive)
local StoryInfo = require(UI.StoryInfo)

local Draw = {}

local function buildTools(parent: Instance, canvas: any, horizontal: boolean): Frame
	local size = if horizontal then 34 else 40
	local tools = Make("Frame", {
		BackgroundColor3 = Theme.panel,
		Size = if horizontal then UDim2.new(1, 0, 0, size + 16) else UDim2.new(0, size + 16, 1, 0),
		Make.corner(),
		Make.pad(8),
		Make.list(if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center),
		Parent = parent,
	})
	if horizontal then
		-- let the bar scroll sideways on very narrow phones
		local scroller = Make("ScrollingFrame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 0,
			ScrollingDirection = Enum.ScrollingDirection.X,
			Make.list(Enum.FillDirection.Horizontal, 6),
		})
		local layout = tools:FindFirstChildOfClass("UIListLayout")
		if layout then layout:Destroy() end
		scroller.Parent = tools
		tools = scroller :: any
	end

	local swatches = {}
	for i, color in Theme.palette do
		local sw = Make("TextButton", {
			Text = "", BackgroundColor3 = color, Size = UDim2.fromOffset(size, size), LayoutOrder = i,
			Make.corner(UDim.new(0, 8)),
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
	Make.spacer(6, 50).Parent = tools
	local sizeButtons = {}
	for i, brush in Theme.brushSizes do
		local b = Make("TextButton", {
			Text = "", BackgroundColor3 = Theme.panelAlt, Size = UDim2.fromOffset(size, size), LayoutOrder = 50 + i,
			Make.corner(UDim.new(0, 8)),
			Make("Frame", {
				BackgroundColor3 = Theme.text, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(4 + brush * 0.6, 4 + brush * 0.6), Make.corner(UDim.new(0.5, 0)),
			}),
			Parent = tools,
		})
		b.Activated:Connect(function()
			canvas.width = brush
			for _, s in sizeButtons do s.BackgroundColor3 = Theme.panelAlt end
			b.BackgroundColor3 = Theme.accent2
		end)
		sizeButtons[i] = b
	end
	sizeButtons[2].BackgroundColor3 = Theme.accent2
	Make.spacer(6, 90).Parent = tools
	Make.button("↶", Theme.panelAlt, function() canvas:undo() end, { Size = UDim2.fromOffset(size, size), LayoutOrder = 91, TextColor3 = Theme.text, Parent = tools })
	Make.button("✕", Theme.danger, function() canvas:clear() end, { Size = UDim2.fromOffset(size, size), LayoutOrder = 92, Parent = tools })
	return tools
end

function Draw.show(container: Frame, data: any, ctx: any)
	local compact = Responsive.isCompact()
	local v = Responsive.viewport()
	local main, side = Layout.split(container, {
		mainFraction = 0.64,
		compactMainHeight = math.min(v.X - 32, math.floor(v.Y * 0.62)) + 44 + 50,
	})

	local panelCount: number = data.panels
	local panelData: { any } = {}
	local currentPanel = 1

	local tabs = Make.row(36, 6, { Parent = main })
	local canvasArea: Frame
	local canvas: any

	if compact then
		local toolsHolder = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50), Position = UDim2.fromOffset(0, 42), Parent = main })
		canvasArea = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -96), Position = UDim2.fromOffset(0, 96), Parent = main })
		canvas = Canvas.new(canvasArea, true)
		buildTools(toolsHolder, canvas, true)
	else
		local toolsHolder = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 56, 1, -44), Position = UDim2.fromOffset(0, 44), Parent = main })
		canvasArea = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -64, 1, -44), Position = UDim2.fromOffset(64, 44), Parent = main })
		canvas = Canvas.new(canvasArea, true)
		buildTools(toolsHolder, canvas, false)
	end
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
		local b = Make.pill(("Panel %d"):format(data.startIndex + i - 1), false, function() selectPanel(i) end, {
			Size = UDim2.new(0, if compact then 84 else 100, 1, 0), Parent = tabs,
		})
		tabButtons[i] = b
	end
	selectPanel(1)

	local info = StoryInfo.build(side, {
		premise = data.premise, cast = data.cast, prompt = data.prompt, ownerName = data.ownerName, lines = data.lines,
	})
	info.Size = UDim2.new(1, 0, 0, 0)
	info.AutomaticSize = Enum.AutomaticSize.Y

	return {
		collect = function()
			panelData[currentPanel] = canvas:getStrokes()
			local out = {}
			for i = 1, panelCount do out[i] = panelData[i] or {} end
			return out
		end,
		destroy = function() canvas:destroy() container:ClearAllChildren() end,
	}
end

return Draw
