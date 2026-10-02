--!strict
--[[
	Drawing phase.
	Regular: tool rail on the left, canvas in the middle, story reference on the right.
	Compact: scrolling tool rows above the canvas, story reference below.
	Every stroke is streamed to the server so nothing is lost if you disconnect.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Canvas = require(UI.Canvas)
local Layout = require(UI.Layout)
local Responsive = require(UI.Responsive)
local StoryInfo = require(UI.StoryInfo)

local Draw = {}

local TOOLS: { { id: string, label: string, hint: string } } = {
	{ id = "brush", label = "✏️", hint = "Brush" },
	{ id = "eraser", label = "🧽", hint = "Eraser" },
	{ id = "rect", label = "▭", hint = "Rectangle" },
	{ id = "circle", label = "◯", hint = "Circle" },
	{ id = "fill", label = "🪣", hint = "Fill: tap a shape to fill it, tap empty paper to colour the background" },
	{ id = "select", label = "✥", hint = "Transform: tap a stroke, drag to move" },
	{ id = "lasso", label = "➰", hint = "Lasso: circle strokes to select them" },
}

local function iconButton(parent: Instance, text: string, size: number, color: Color3, onClick: () -> ()): TextButton
	local b = Make.button(text, color, onClick, {
		Size = UDim2.fromOffset(size, size), TextSize = if #text > 2 then 11 else 18, TextColor3 = Theme.text, Parent = parent,
	})
	return b
end

function Draw.show(container: Frame, data: any, ctx: any)
	local compact = Responsive.isCompact()
	local v = Responsive.viewport()
	local size = if compact then 36 else 40
	local main, side = Layout.split(container, {
		mainFraction = 0.66,
		compactMainHeight = math.min(v.X - 32, math.floor(v.Y * 0.56)) + 44 + 2 * (size + 14),
	})

	local panelCount: number = data.panels
	local panelData: { any } = {}
	local currentPanel = 1
	local canvas: any

	-- Layout skeleton --------------------------------------------------------
	local tabs = Make.row(36, 6, { Parent = main })
	local hint = Make.label("", 12, { TextColor3 = Theme.textDim, Size = UDim2.new(0.5, 0, 0, 36), Position = UDim2.new(0.5, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Center, Parent = main })

	local toolRail: Frame, colorRail: Frame, canvasArea: Frame
	local function rail(horizontal: boolean, props: { [any]: any }): Frame
		local p = {
			BackgroundColor3 = Theme.panel,
			Make.corner(),
			Make.pad(6),
		}
		for k, val in props do p[k] = val end
		local f = Make("Frame", p)
		local scroller = Make("ScrollingFrame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			AutomaticCanvasSize = if horizontal then Enum.AutomaticSize.X else Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 0,
			ScrollingDirection = if horizontal then Enum.ScrollingDirection.X else Enum.ScrollingDirection.Y,
			Make.list(if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center),
			Parent = f,
		})
		return scroller
	end

	if compact then
		local railH = size + 14
		toolRail = rail(true, { Size = UDim2.new(1, 0, 0, railH), Position = UDim2.fromOffset(0, 42), Parent = main })
		colorRail = rail(true, { Size = UDim2.new(1, 0, 0, railH), Position = UDim2.fromOffset(0, 42 + railH + 4), Parent = main })
		canvasArea = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -(50 + 2 * railH)), Position = UDim2.fromOffset(0, 50 + 2 * railH), Parent = main })
	else
		local railW = size + 14
		toolRail = rail(false, { Size = UDim2.new(0, railW, 1, -44), Position = UDim2.fromOffset(0, 44), Parent = main })
		colorRail = rail(false, { Size = UDim2.new(0, railW, 1, -44), Position = UDim2.fromOffset(railW + 6, 44), Parent = main })
		canvasArea = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -(2 * railW + 14), 1, -44), Position = UDim2.fromOffset(2 * railW + 14, 44), Parent = main })
	end
	canvas = Canvas.new(canvasArea, true)

	-- Streaming ---------------------------------------------------------------
	canvas.onOp = function(op: string, payload: any)
		panelData[currentPanel] = canvas:getStrokes()
		local msg: any = { panel = currentPanel, op = op }
		if op == "add" then msg.stroke = payload elseif op == "set" then msg.strokes = payload end
		Net.remote:FireServer(Net.C2S.Stroke, msg)
		ctx.markDirty()
	end

	-- Tools -------------------------------------------------------------------
	local toolButtons: { [string]: TextButton } = {}
	local function paintTools()
		for id, b in toolButtons do
			b.BackgroundColor3 = if canvas.tool == id then Theme.accent else Theme.panelAlt
			b.TextColor3 = if canvas.tool == id then Theme.bg else Theme.text
		end
	end
	for i, t in TOOLS do
		local b = iconButton(toolRail, t.label, size, Theme.panelAlt, function()
			canvas:setTool(t.id :: any)
			hint.Text = t.hint
			paintTools()
		end)
		b.LayoutOrder = i
		toolButtons[t.id] = b
	end
	Make.spacer(4, 20).Parent = toolRail
	local mirrorBtn = iconButton(toolRail, "⇔", size, Theme.panelAlt, function() end)
	mirrorBtn.LayoutOrder = 21
	mirrorBtn.Activated:Connect(function()
		canvas.mirror = not canvas.mirror
		mirrorBtn.BackgroundColor3 = if canvas.mirror then Theme.accent2 else Theme.panelAlt
		hint.Text = if canvas.mirror then "Mirror on: strokes are drawn on both sides" else "Mirror off"
	end)
	local filledBtn = iconButton(toolRail, "◼", size, Theme.panelAlt, function() end)
	filledBtn.LayoutOrder = 22
	filledBtn.Activated:Connect(function()
		canvas.filled = not canvas.filled
		filledBtn.BackgroundColor3 = if canvas.filled then Theme.accent2 else Theme.panelAlt
		filledBtn.Text = if canvas.filled then "◼" else "◻"
		hint.Text = if canvas.filled then "Shapes are filled" else "Shapes are outlined"
	end)
	filledBtn.Text = "◻"
	Make.spacer(4, 30).Parent = toolRail
	iconButton(toolRail, "Undo", size, Theme.panelAlt, function() canvas:undo() end).LayoutOrder = 31
	iconButton(toolRail, "Clear", size, Theme.danger, function() canvas:clear() end).LayoutOrder = 32

	-- Selection actions (visible only with a selection)
	Make.spacer(4, 40).Parent = toolRail
	local selButtons = {}
	local function selAction(order: number, text: string, color: Color3, fn: () -> ())
		local b = iconButton(toolRail, text, size, color, fn)
		b.LayoutOrder = order
		b.Visible = false
		table.insert(selButtons, b)
	end
	selAction(41, "+", Theme.panelAlt, function() canvas:scaleSelection(1.15) end)
	selAction(42, "−", Theme.panelAlt, function() canvas:scaleSelection(1 / 1.15) end)
	selAction(43, "Flip", Theme.panelAlt, function() canvas:flipSelection() end)
	selAction(44, "Copy", Theme.panelAlt, function() canvas:duplicateSelection() end)
	selAction(45, "Del", Theme.danger, function() canvas:deleteSelection() end)
	canvas.onSelectionChanged = function(has: boolean)
		for _, b in selButtons do b.Visible = has end
		if has then hint.Text = "Drag to move. Use + − to resize, Flip, Copy or Del." end
	end
	paintTools()
	hint.Text = "Brush"

	-- Colours and sizes -------------------------------------------------------
	local swatches = {}
	for i, color in Theme.palette do
		local sw = Make("TextButton", {
			Text = "", BackgroundColor3 = color, Size = UDim2.fromOffset(size, size * 0.65), LayoutOrder = i,
			Make.corner(UDim.new(0, 8)),
			Make("UIStroke", { Color = Theme.text, Thickness = if i == 1 then 2 else 0 }),
			Parent = colorRail,
		})
		sw.Activated:Connect(function()
			canvas.color = color
			for _, s in swatches do (s:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = 0 end
			(sw:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = 2
		end)
		table.insert(swatches, sw)
	end
	Make.spacer(4, 50).Parent = colorRail
	local sizeButtons = {}
	for i, brush in Theme.brushSizes do
		local b = Make("TextButton", {
			Text = "", BackgroundColor3 = Theme.panelAlt, Size = UDim2.fromOffset(size, size * 0.75), LayoutOrder = 50 + i,
			Make.corner(UDim.new(0, 8)),
			Make("Frame", {
				BackgroundColor3 = Theme.text, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(4 + brush * 0.6, 4 + brush * 0.6), Make.corner(UDim.new(0.5, 0)),
			}),
			Parent = colorRail,
		})
		b.Activated:Connect(function()
			canvas.width = brush
			for _, s in sizeButtons do s.BackgroundColor3 = Theme.panelAlt end
			b.BackgroundColor3 = Theme.accent2
		end)
		sizeButtons[i] = b
	end
	sizeButtons[2].BackgroundColor3 = Theme.accent2

	-- Panel tabs --------------------------------------------------------------
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
		tabButtons[i] = Make.pill(("Panel %d"):format(data.startIndex + i - 1), false, function() selectPanel(i) end, {
			Size = UDim2.new(0, if compact then 84 else 100, 1, 0), Parent = tabs,
		})
	end
	if panelCount == 1 and data.totalPanels then
		tabButtons[1].Text = ("Panel %d of %d"):format(data.startIndex, data.totalPanels)
		tabButtons[1].Size = UDim2.new(0, 130, 1, 0)
	end
	selectPanel(1)

	-- Story reference ---------------------------------------------------------
	if data.scene then
		local sceneCard = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 6), Parent = side })
		Make.heading("Your scene", 14, { TextColor3 = Theme.accent, Parent = sceneCard })
		Make.label(data.scene, 17, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = sceneCard })
		Make.label("Directed by " .. (data.ownerName or "?"), 12, { TextColor3 = Theme.textDim, Parent = sceneCard })
	end
	local info = StoryInfo.build(side, {
		premise = data.premise, cast = data.cast, roles = data.roles, prompt = data.prompt, ownerName = if data.scene then nil else data.ownerName, lines = data.lines,
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
