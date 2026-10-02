--!strict
--[[
	Drawing phase.
	Regular: tool rail | colour rail | canvas | story reference.
	Compact: tool row and colour row above the canvas; story reference below.
	Tap a stroke to select it (no separate tool); the transform menu appears
	under the tool rail while something is selected. Every edit streams to the server.
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

local TOOLS = {
	{ id = "brush", hint = "Brush. Tap any stroke to select it." },
	{ id = "eraser", hint = "Eraser" },
	{ id = "rect", hint = "Rectangle: drag corner to corner" },
	{ id = "circle", hint = "Circle: drag corner to corner" },
	{ id = "fill", hint = "Fill: tap a shape to fill it, tap paper to colour the background" },
	{ id = "lasso", hint = "Lasso: circle strokes to select several" },
}

local TRANSFORM = {
	{ id = "flip_h", fn = function(c) c:flipSelection(false) end },
	{ id = "flip_v", fn = function(c) c:flipSelection(true) end },
	{ id = "rotate_left", fn = function(c) c:rotateSelection(-math.pi / 2) end },
	{ id = "rotate_right", fn = function(c) c:rotateSelection(math.pi / 2) end },
	{ id = "warp", fn = function(c) c:beginWarpMode() end },
	{ id = "duplicate", fn = function(c) c:duplicateSelection() end },
	{ id = "delete", fn = function(c) c:deleteSelection() end },
}

local function rail(parent: Instance, horizontal: boolean, props: { [any]: any }): ScrollingFrame
	local p = { BackgroundColor3 = Theme.panel, Make.corner(), Make.pad(6) }
	for k, v in props do p[k] = v end
	local f = Make("Frame", p)
	return Make("ScrollingFrame", {
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
		AutomaticCanvasSize = if horizontal then Enum.AutomaticSize.X else Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(), ScrollBarThickness = 0,
		ScrollingDirection = if horizontal then Enum.ScrollingDirection.X else Enum.ScrollingDirection.Y,
		Make.list(if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center),
		Parent = f,
	})
end

function Draw.show(container: Frame, data: any, ctx: any)
	local compact = Responsive.isCompact()
	local v = Responsive.viewport()
	local size = if compact then 40 else 44
	local railThick = size + 14
	local main, side = Layout.split(container, {
		mainFraction = 0.68,
		compactMainHeight = math.min(v.X - 32, math.floor(v.Y * 0.56)) + 44 + 2 * (railThick + 4),
	})

	local panelCount: number = data.panels
	local panelData: { any } = {}
	local currentPanel = 1

	local tabs = Make.row(36, 6, { Parent = main })
	local hint = Make.label("", 12, { TextColor3 = Theme.textDim, Size = UDim2.new(0.55, 0, 0, 36), Position = UDim2.new(0.45, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Center, Parent = main })

	local toolRail: ScrollingFrame, colorRail: ScrollingFrame, canvasArea: Frame
	if compact then
		toolRail = rail(main, true, { Size = UDim2.new(1, 0, 0, railThick), Position = UDim2.fromOffset(0, 42), Parent = main })
		colorRail = rail(main, true, { Size = UDim2.new(1, 0, 0, railThick), Position = UDim2.fromOffset(0, 42 + railThick + 4), Parent = main })
		canvasArea = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -(50 + 2 * railThick)), Position = UDim2.fromOffset(0, 50 + 2 * railThick), Parent = main })
	else
		toolRail = rail(main, false, { Size = UDim2.new(0, railThick, 1, -44), Position = UDim2.fromOffset(0, 44), Parent = main })
		colorRail = rail(main, false, { Size = UDim2.new(0, railThick, 1, -44), Position = UDim2.fromOffset(railThick + 6, 44), Parent = main })
		canvasArea = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -(2 * railThick + 14), 1, -44), Position = UDim2.fromOffset(2 * railThick + 14, 44), Parent = main })
	end
	local canvas = Canvas.new(canvasArea, true)

	canvas.onOp = function(op: string, payload: any)
		panelData[currentPanel] = canvas:getStrokes()
		local msg: any = { panel = currentPanel, op = op }
		if op == "add" then msg.stroke = payload elseif op == "set" then msg.strokes = payload end
		Net.remote:FireServer(Net.C2S.Stroke, msg)
		ctx.markDirty()
	end

	-- Tools ----------------------------------------------------------------
	local toolButtons: { [string]: TextButton } = {}
	local function paintTools()
		for id, b in toolButtons do
			b.BackgroundColor3 = if canvas.tool == id then Theme.accent else Theme.panelAlt
			b.TextColor3 = if canvas.tool == id then Theme.bg else Theme.text
			local img = b:FindFirstChildOfClass("ImageLabel")
			if img then img.ImageColor3 = b.TextColor3 end
		end
	end
	for i, t in TOOLS do
		local b = Make.iconButton(t.id, size, Theme.panelAlt, function()
			canvas:setTool(t.id :: any)
			hint.Text = t.hint
			paintTools()
		end, { LayoutOrder = i, Parent = toolRail })
		toolButtons[t.id] = b
	end
	Make.spacer(4, 20).Parent = toolRail
	local mirrorBtn = Make.iconButton("mirror", size, Theme.panelAlt, function() end, { LayoutOrder = 21, Parent = toolRail })
	mirrorBtn.Activated:Connect(function()
		canvas.mirror = not canvas.mirror
		mirrorBtn.BackgroundColor3 = if canvas.mirror then Theme.accent2 else Theme.panelAlt
		hint.Text = if canvas.mirror then "Mirror on: strokes are drawn on both sides" else "Mirror off"
	end)
	local filledBtn = Make.iconButton("shape_outline", size, Theme.panelAlt, function() end, { LayoutOrder = 22, Parent = toolRail })
	filledBtn.Activated:Connect(function()
		canvas.filled = not canvas.filled
		filledBtn.BackgroundColor3 = if canvas.filled then Theme.accent2 else Theme.panelAlt
		filledBtn.Text = if canvas.filled then "Solid" else "Line"
		hint.Text = if canvas.filled then "Shapes are filled" else "Shapes are outlined"
	end)
	Make.spacer(4, 30).Parent = toolRail
	Make.iconButton("undo", size, Theme.panelAlt, function() canvas:undo() end, { LayoutOrder = 31, Parent = toolRail })
	Make.iconButton("clear", size, Theme.danger, function() canvas:clear() end, { LayoutOrder = 32, Parent = toolRail })

	-- Transform submenu (visible only with a selection)
	local divider = Make.spacer(6, 40)
	divider.Parent = toolRail
	local tfButtons = {}
	for i, def in TRANSFORM do
		local b = Make.iconButton(def.id, size, Theme.panel, function() def.fn(canvas) end, { LayoutOrder = 40 + i, Visible = false, TextColor3 = Theme.accent2, Parent = toolRail })
		if def.id == "delete" then b.TextColor3 = Theme.danger end
		table.insert(tfButtons, b)
	end
	canvas.onSelectionChanged = function(has: boolean)
		for _, b in tfButtons do b.Visible = has end
		if has then hint.Text = "Drag inside the box to move. Handles stretch; corners keep proportion; the top knob rotates." end
	end
	paintTools()
	hint.Text = TOOLS[1].hint

	-- Colours and sizes ------------------------------------------------------
	local swatches = {}
	for i, color in Theme.palette do
		local sw = Make("TextButton", {
			Text = "", BackgroundColor3 = color, Size = UDim2.fromOffset(size, math.floor(size * 0.6)), LayoutOrder = i,
			Make.corner(UDim.new(0, 8)), Make("UIStroke", { Color = Theme.text, Thickness = if i == 1 then 2 else 0 }), Parent = colorRail,
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
		local dot = 6 + i * 6
		local b = Make("TextButton", {
			Text = "", BackgroundColor3 = Theme.panelAlt, Size = UDim2.fromOffset(size, math.floor(size * 0.8)), LayoutOrder = 50 + i,
			Make.corner(UDim.new(0, 8)),
			Make("Frame", { BackgroundColor3 = Theme.text, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(dot, dot), Make.corner(UDim.new(0.5, 0)) }),
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

	-- Panel tabs ------------------------------------------------------------
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
		tabButtons[i] = Make.pill(("Panel %d"):format(data.startIndex + i - 1), false, function() selectPanel(i) end, { Size = UDim2.new(0, 100, 1, 0), Parent = tabs })
	end
	if panelCount == 1 then
		tabButtons[1].Text = if data.totalPanels then ("Panel %d of %d"):format(data.startIndex, data.totalPanels) else "Your panel"
		tabButtons[1].Size = UDim2.new(0, 140, 1, 0)
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
		premise = data.premise, cast = data.cast, roles = data.roles, prompt = data.prompt,
		ownerName = if data.scene then nil else data.ownerName, lines = data.lines,
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
