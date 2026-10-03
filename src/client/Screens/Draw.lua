--!strict
--[[
	Drawing phase, laid out like a compact art app.
	Regular:  [tool rail] [canvas] [context panel: colour / size / opacity, then story]
	Compact:  tool row above the canvas, context panel below.
	Colour controls only show for colour tools. Transform shows a floating
	strip under the selection. Every edit streams to the server.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Config = require(Shared.Config)
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Canvas = require(UI.Canvas)
local ColorPicker = require(UI.ColorPicker)
local Layout = require(UI.Layout)
local Responsive = require(UI.Responsive)
local StoryInfo = require(UI.StoryInfo)

local Draw = {}

local TOOLS = {
	{ id = "brush", hint = "Brush" },
	{ id = "airbrush", hint = "Airbrush: soft, wide, build it up" },
	{ id = "eraser", hint = "Eraser" },
	{ id = "rect", hint = "Rectangle: drag corner to corner" },
	{ id = "circle", hint = "Circle: drag corner to corner" },
	{ id = "fill", hint = "Fill: tap a shape, or tap paper for the background" },
	{ id = "lasso", hint = "Lasso: circle strokes to select them" },
	{ id = "transform", hint = "Transform: tap a stroke. Drag to move, handles stretch, knob rotates." },
}
local COLOR_TOOLS = { brush = true, airbrush = true, rect = true, circle = true, fill = true }
local SIZE_TOOLS = { brush = true, airbrush = true, eraser = true, rect = true, circle = true }

local TRANSFORM = {
	{ id = "flip_h", fn = function(c) c:flipSelection(false) end },
	{ id = "flip_v", fn = function(c) c:flipSelection(true) end },
	{ id = "rotate_left", fn = function(c) c:rotateSelection(-math.pi / 2) end },
	{ id = "rotate_right", fn = function(c) c:rotateSelection(math.pi / 2) end },
	{ id = "warp", fn = function(c) c:beginWarpMode() end },
	{ id = "duplicate", fn = function(c) c:duplicateSelection() end },
	{ id = "delete", fn = function(c) c:deleteSelection() end },
}

local function slider(parent: Instance, label: string, value: number, onChange: (number) -> ()): (Frame, (string) -> ())
	local UserInputService = game:GetService("UserInputService")
	local row = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = parent })
	local lbl = Make.label(label, 11, { TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 14), Parent = row })
	local track = Make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.bg, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 20), Make.corner(UDim.new(0.5, 0)), Parent = row })
	local fill = Make("Frame", { BackgroundColor3 = Theme.accent2, Size = UDim2.new(value, 0, 1, 0), Make.corner(UDim.new(0.5, 0)), Parent = track })
	Make("Frame", { BackgroundColor3 = Theme.text, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(16, 16), ZIndex = 2, Make.corner(UDim.new(0.5, 0)), Make("UIStroke", { Color = Theme.bg, Thickness = 2 }), Parent = fill })
	local dragging = false
	local function setX(x: number)
		local a = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		fill.Size = UDim2.new(a, 0, 1, 0)
		onChange(a)
	end
	local function press(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	track.InputBegan:Connect(function(input) if press(input) then dragging = true setX(input.Position.X) end end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then setX(input.Position.X) end
	end)
	UserInputService.InputEnded:Connect(function(input) if press(input) then dragging = false end end)
	return row, function(text: string) lbl.Text = text end
end

function Draw.show(container: Frame, data: any, ctx: any)
	local compact = Responsive.isCompact()
	local stacked = Responsive.isStacked()
	local v = Responsive.viewport()
	local size = if compact then 40 else 44
	local railThick = size + 14
	local main, side = Layout.split(container, {
		mainFraction = 0.62,
		compactMainHeight = math.min(v.X - 32, math.floor(v.Y * 0.58)) + 44 + railThick + 4,
	})

	local panelCount: number = data.panels
	local panelData: { any } = {}
	local currentPanel = 1

	-- Top strip: panel tabs + hint
	local tabs = Make.row(36, 6, { Parent = main })
	local hint = Make.label("", 12, { TextColor3 = Theme.textDim, Size = UDim2.new(0.6, 0, 0, 36), Position = UDim2.new(0.4, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Center, Parent = main })

	-- Tool rail + canvas
	local toolHolder = Make("Frame", {
		BackgroundColor3 = Theme.panel, Make.corner(), Make.pad(6),
		Size = if stacked then UDim2.new(1, 0, 0, railThick) else UDim2.new(0, railThick, 1, -44),
		Position = UDim2.fromOffset(0, if stacked then 42 else 44),
		Parent = main,
	})
	local toolRail = Make("ScrollingFrame", {
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
		AutomaticCanvasSize = if stacked then Enum.AutomaticSize.X else Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(), ScrollBarThickness = 0,
		ScrollingDirection = if stacked then Enum.ScrollingDirection.X else Enum.ScrollingDirection.Y,
		Make.list(if stacked then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center),
		Parent = toolHolder,
	})
	local canvasArea = Make("Frame", {
		BackgroundTransparency = 1,
		Size = if stacked then UDim2.new(1, 0, 1, -(48 + railThick)) else UDim2.new(1, -(railThick + 10), 1, -44),
		Position = if stacked then UDim2.fromOffset(0, 48 + railThick) else UDim2.fromOffset(railThick + 10, 44),
		Parent = main,
	})
	local canvas = Canvas.new(canvasArea, true)

	canvas.onOp = function(op: string, payload: any)
		panelData[currentPanel] = canvas:getStrokes()
		local msg: any = { panel = currentPanel, op = op }
		if op == "add" then msg.stroke = payload elseif op == "set" then msg.strokes = payload end
		Net.remote:FireServer(Net.C2S.Stroke, msg)
		ctx.markDirty()
	end

	-- Context panel (right / below) --------------------------------------------
	local context = Make("Frame", { BackgroundColor3 = Theme.panel, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.corner(), Make.pad(10), Make.list(nil, 8), Parent = side })

	-- Preview dot + sliders
	local previewRow = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 1, Parent = context })
	local previewBg = Make("Frame", { BackgroundColor3 = Theme.paper, Size = UDim2.fromOffset(56, 56), Make.corner(UDim.new(0, 8)), Parent = previewRow })
	local previewDot = Make("Frame", { BackgroundColor3 = canvas.color, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(12, 12), Make.corner(UDim.new(0.5, 0)), Parent = previewBg })
	local toolName = Make.heading("Brush", 16, { Size = UDim2.new(1, -66, 0, 20), Position = UDim2.fromOffset(66, 4), Parent = previewRow })
	local toolDesc = Make.label("", 11, { TextColor3 = Theme.textDim, Size = UDim2.new(1, -66, 0, 30), Position = UDim2.fromOffset(66, 24), Parent = previewRow })

	local function refreshPreview()
		local px = math.clamp(canvas.width * 0.45, 3, 50)
		previewDot.Size = UDim2.fromOffset(px, px)
		previewDot.BackgroundColor3 = if canvas.tool == "eraser" then Theme.paper else canvas.color
		previewDot.BackgroundTransparency = if canvas.tool == "airbrush" then 1 - canvas.opacity * 0.6 else 1 - canvas.opacity
		local stroke = previewDot:FindFirstChildOfClass("UIStroke")
		if canvas.tool == "eraser" then
			if not stroke then Make("UIStroke", { Color = Theme.textDim, Thickness = 1, Parent = previewDot }) end
		elseif stroke then stroke:Destroy() end
	end

	-- Declared before the sliders so their callbacks can see them (a local isn't in
	-- scope inside the statement that declares it).
	local setSizeLabel: (string) -> () = function() end
	local setOpacityLabel: (string) -> () = function() end
	local sizeRow
	sizeRow, setSizeLabel = slider(context, "Size", math.sqrt((canvas.width - Config.MIN_BRUSH) / (Config.MAX_BRUSH - Config.MIN_BRUSH)), function(a)
		-- ease so small sizes get more travel
		canvas.width = Config.MIN_BRUSH + (Config.MAX_BRUSH - Config.MIN_BRUSH) * a * a
		setSizeLabel(("Size  %d"):format(math.floor(canvas.width + 0.5)))
		refreshPreview()
	end)
	sizeRow.LayoutOrder = 2
	setSizeLabel(("Size  %d"):format(canvas.width))
	local opacityRow
	opacityRow, setOpacityLabel = slider(context, "Opacity  100%", 1, function(a)
		canvas.opacity = math.clamp(a, 0.05, 1)
		setOpacityLabel(("Opacity  %d%%"):format(math.floor(canvas.opacity * 100 + 0.5)))
		refreshPreview()
	end)
	opacityRow.LayoutOrder = 3

	-- Colour section
	local colorSection = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4, Make.list(nil, 6), Parent = context })
	local swatchGrid = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = colorSection })
	Make("UIGridLayout", { CellSize = UDim2.fromOffset(30, 24), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = swatchGrid })
	local picker: ColorPicker.ColorPicker? = nil
	local swatches = {}
	local function paintSwatches()
		for _, sw in swatches do
			(sw:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = if sw.BackgroundColor3 == canvas.color then 2 else 0
		end
	end
	local function setColor(color: Color3, fromPicker: boolean?)
		canvas.color = color
		paintSwatches()
		refreshPreview()
		if picker and not fromPicker then picker:set(color) end
	end
	for i, color in Theme.palette do
		local sw = Make("TextButton", { Text = "", BackgroundColor3 = color, LayoutOrder = i, Make.corner(UDim.new(0, 6)), Make("UIStroke", { Color = Theme.text, Thickness = if i == 1 then 2 else 0 }), Parent = swatchGrid })
		sw.Activated:Connect(function() setColor(color) end)
		table.insert(swatches, sw)
	end
	-- Recent colours
	local recentRow = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 2, Make.list(Enum.FillDirection.Horizontal, 6), Parent = colorSection })
	local recent: { Color3 } = {}
	local function pushRecent(color: Color3)
		for i, c in recent do if c == color then table.remove(recent, i) break end end
		table.insert(recent, 1, color)
		while #recent > 8 do table.remove(recent) end
		for _, c in recentRow:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		for i, c in recent do
			local b = Make("TextButton", { Text = "", BackgroundColor3 = c, Size = UDim2.fromOffset(24, 24), LayoutOrder = i, Make.corner(UDim.new(0.5, 0)), Parent = recentRow })
			b.Activated:Connect(function() setColor(c) end)
		end
	end
	local wheelToggle = Make.button("Colour wheel", Theme.panelAlt, function() end, { Size = UDim2.new(1, 0, 0, 30), TextSize = 12, TextColor3 = Theme.text, LayoutOrder = 3, Parent = colorSection })
	local pickerHolder = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4, Visible = false, Parent = colorSection })
	wheelToggle.Activated:Connect(function()
		pickerHolder.Visible = not pickerHolder.Visible
		wheelToggle.Text = if pickerHolder.Visible then "Hide wheel" else "Colour wheel"
		if pickerHolder.Visible and not picker then
			picker = ColorPicker.new(pickerHolder, canvas.color, function(c) setColor(c, true) end)
		end
	end)
	-- Remember colours actually used
	local lastEmitColor: Color3? = nil
	local baseOnOp = canvas.onOp
	canvas.onOp = function(op: string, payload: any)
		if op == "add" and canvas.tool ~= "eraser" and canvas.color ~= lastEmitColor then
			lastEmitColor = canvas.color
			pushRecent(canvas.color)
		end
		if baseOnOp then baseOnOp(op, payload) end
	end

	-- Mirror + filled toggles, undo/clear
	local toggles = Make.row(size - 6, 6, { LayoutOrder = 5, Parent = context })
	local mirrorBtn = Make.iconButton("mirror", size - 6, Theme.panelAlt, function() end, { Size = UDim2.new(0.5, -3, 1, 0), Parent = toggles })
	mirrorBtn.Activated:Connect(function()
		canvas.mirror = not canvas.mirror
		mirrorBtn.BackgroundColor3 = if canvas.mirror then Theme.accent2 else Theme.panelAlt
	end)
	local filledBtn = Make.iconButton("shape_outline", size - 6, Theme.panelAlt, function() end, { Size = UDim2.new(0.5, -3, 1, 0), Parent = toggles })
	filledBtn.Activated:Connect(function()
		canvas.filled = not canvas.filled
		filledBtn.BackgroundColor3 = if canvas.filled then Theme.accent2 else Theme.panelAlt
		filledBtn.Text = if canvas.filled then "Solid" else "Line"
	end)
	local edits = Make.row(size - 6, 6, { LayoutOrder = 6, Parent = context })
	Make.iconButton("undo", size - 6, Theme.panelAlt, function() canvas:undo() end, { Size = UDim2.new(0.5, -3, 1, 0), Parent = edits })
	Make.iconButton("clear", size - 6, Theme.danger, function() canvas:clear() end, { Size = UDim2.new(0.5, -3, 1, 0), Parent = edits })

	-- Floating transform strip (lives inside the canvas, under the selection box)
	local strip = Make("Frame", {
		BackgroundColor3 = Theme.bg, BackgroundTransparency = 0.1, Visible = false, ZIndex = 9,
		Size = UDim2.fromOffset(#TRANSFORM * (size - 4) + 16, size + 4), AnchorPoint = Vector2.new(0.5, 0),
		Make.corner(UDim.new(0, 10)), Make.pad(6), Make.list(Enum.FillDirection.Horizontal, 4),
		Make("UIStroke", { Color = Theme.accent2, Thickness = 1 }),
		Parent = canvas.frame,
	})
	for i, def in TRANSFORM do
		local b = Make.iconButton(def.id, size - 8, Theme.panelAlt, function() def.fn(canvas) end, { LayoutOrder = i, ZIndex = 10, Parent = strip })
		if def.id == "delete" then b.TextColor3 = Theme.danger end
	end
	canvas.onSelectionChanged = function(has: boolean, box: Frame?)
		strip.Visible = has
		if has and box then
			-- below the box if there's room, else above
			local canvasH = canvas.frame.AbsoluteSize.Y
			local boxBottom = box.AbsolutePosition.Y + box.AbsoluteSize.Y - canvas.frame.AbsolutePosition.Y
			local boxTop = box.AbsolutePosition.Y - canvas.frame.AbsolutePosition.Y
			local cx = box.AbsolutePosition.X + box.AbsoluteSize.X / 2 - canvas.frame.AbsolutePosition.X
			cx = math.clamp(cx, strip.AbsoluteSize.X / 2 + 4, canvas.frame.AbsoluteSize.X - strip.AbsoluteSize.X / 2 - 4)
			if boxBottom + strip.AbsoluteSize.Y + 12 < canvasH then
				strip.Position = UDim2.fromOffset(cx, boxBottom + 10)
			else
				strip.Position = UDim2.fromOffset(cx, math.max(4, boxTop - strip.AbsoluteSize.Y - 34))
			end
		end
	end

	-- Tools ------------------------------------------------------------------
	local toolButtons: { [string]: TextButton } = {}
	local function selectTool(id: string, hintText: string)
		canvas:setTool(id :: any)
		for tid, b in toolButtons do
			b.BackgroundColor3 = if tid == id then Theme.accent else Theme.panelAlt
			b.TextColor3 = if tid == id then Theme.bg else Theme.text
			local img = b:FindFirstChildOfClass("ImageLabel")
			if img then img.ImageColor3 = b.TextColor3 end
		end
		hint.Text = hintText
		toolName.Text = hintText:match("^[^:]+") or id
		toolDesc.Text = hintText:match("^[^:]+:%s*(.+)$") or ""
		colorSection.Visible = COLOR_TOOLS[id] == true
		sizeRow.Visible = SIZE_TOOLS[id] == true
		opacityRow.Visible = SIZE_TOOLS[id] == true and id ~= "eraser"
		toggles.Visible = id ~= "transform" and id ~= "lasso" and id ~= "fill"
		filledBtn.Visible = id == "rect" or id == "circle"
		refreshPreview()
	end
	for i, t in TOOLS do
		toolButtons[t.id] = Make.iconButton(t.id, size, Theme.panelAlt, function() selectTool(t.id, t.hint) end, { LayoutOrder = i, Parent = toolRail })
	end
	selectTool("brush", TOOLS[1].hint)

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
		destroy = function()
			if picker then picker:destroy() end
			canvas:destroy()
			container:ClearAllChildren()
		end,
	}
end

return Draw
