--!strict
--[[
	Square drawing surface. Strokes are stored normalized (0..1) so the same
	data renders identically at any size, on any client.

	Tools: brush, eraser, rect, circle, fill, select, lasso. `mirror` draws a
	horizontally mirrored twin of every brush stroke/shape. `filled` makes
	shapes solid. Every change calls `onOp(op, payload)` so the owner can
	stream it to the server: add {stroke}, undo, clear, set {strokes}.
]]
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Strokes = require(Shared.Strokes)
local Make = require(script.Parent.Make)
local Theme = require(script.Parent.Theme)

local Canvas = {}
Canvas.__index = Canvas

export type Tool = "brush" | "eraser" | "rect" | "circle" | "fill" | "select" | "lasso"

export type Canvas = typeof(setmetatable({} :: {
	frame: Frame,
	layer: Frame,
	overlay: Frame,
	strokes: { Strokes.Stroke },
	editable: boolean,
	tool: Tool,
	color: Color3,
	width: number,
	mirror: boolean,
	filled: boolean,
	-- in-progress gesture
	dragging: boolean,
	startX: number,
	startY: number,
	lastX: number,
	lastY: number,
	current: Strokes.Stroke?,
	preview: { GuiObject },
	-- selection (indices into strokes)
	selection: { number },
	selectionBox: Frame?,
	connections: { RBXScriptConnection },
	onChange: (() -> ())?,
	onOp: ((string, any) -> ())?,
	onSelectionChanged: ((boolean) -> ())?,
}, Canvas))

local MIN_POINT_DIST = 0.004
local PICK_RADIUS = 0.03

function Canvas.new(parent: Instance, editable: boolean): Canvas
	local self = setmetatable({}, Canvas)
	self.frame = Make("Frame", {
		BackgroundColor3 = Theme.paper,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ClipsDescendants = true,
		Active = true,
		Make.corner(UDim.new(0, 10)),
		Make("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 1, Transparency = 0.6 }),
		Make("UIAspectRatioConstraint", { AspectRatio = 1 }),
		Parent = parent,
	})
	self.layer = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = self.frame })
	self.overlay = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = self.frame })
	self.strokes = {}
	self.editable = editable
	self.tool = "brush"
	self.color = Theme.palette[1]
	self.width = Theme.brushSizes[2]
	self.mirror = false
	self.filled = false
	self.dragging = false
	self.startX, self.startY, self.lastX, self.lastY = 0, 0, 0, 0
	self.current = nil
	self.preview = {}
	self.selection = {}
	self.selectionBox = nil
	self.connections = {}

	table.insert(self.connections, self.frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:render()
	end))
	if editable then self:bindInput() end
	return self
end

----------------------------------------------------------------------------
-- Rendering

function Canvas.pixelsPerUnit(self: Canvas): number
	return self.frame.AbsoluteSize.X
end

function Canvas.backgroundColor(self: Canvas): Color3
	for i = #self.strokes, 1, -1 do
		local s = self.strokes[i]
		if s.t == "bg" then return Strokes.toColor3(s.c) end
	end
	return Theme.paper
end

function Canvas.drawSegment(self: Canvas, into: Frame, color: Color3, width: number, x1: number, y1: number, x2: number, y2: number, z: number?)
	local px = self:pixelsPerUnit()
	local wpx = math.max(1, width * px / 1000)
	local dx, dy = (x2 - x1) * px, (y2 - y1) * px
	local len = math.sqrt(dx * dx + dy * dy)
	local seg = Instance.new("Frame")
	seg.BorderSizePixel = 0
	seg.BackgroundColor3 = color
	seg.AnchorPoint = Vector2.new(0.5, 0.5)
	seg.Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2)
	seg.Size = UDim2.fromOffset(len + wpx, wpx)
	seg.Rotation = math.deg(math.atan2(dy, dx))
	seg.ZIndex = z or 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = seg
	seg.Parent = into
	return seg
end

function Canvas.drawShape(self: Canvas, into: Frame, stroke: Strokes.Stroke, z: number?): Frame
	local minX, minY, maxX, maxY = Strokes.bounds(stroke)
	local px = self:pixelsPerUnit()
	local wpx = math.max(1, stroke.w * px / 1000)
	local color = Strokes.toColor3(stroke.c)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.Position = UDim2.fromScale(minX, minY)
	f.Size = UDim2.fromScale(maxX - minX, maxY - minY)
	f.ZIndex = z or 1
	if stroke.f then
		f.BackgroundColor3 = color
	else
		f.BackgroundTransparency = 1
		local outline = Instance.new("UIStroke")
		outline.Color = color
		outline.Thickness = wpx
		outline.Parent = f
	end
	if stroke.t == "c" then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
	end
	f.Parent = into
	return f
end

function Canvas.renderStroke(self: Canvas, stroke: Strokes.Stroke, into: Frame, z: number?)
	if stroke.t == "bg" then return end
	if stroke.t == "r" or stroke.t == "c" then
		self:drawShape(into, stroke, z)
		return
	end
	local color = Strokes.toColor3(stroke.c)
	local p = stroke.p
	if #p == 2 then
		self:drawSegment(into, color, stroke.w, p[1], p[2], p[1], p[2], z)
		return
	end
	for i = 1, #p - 3, 2 do
		self:drawSegment(into, color, stroke.w, p[i], p[i + 1], p[i + 2], p[i + 3], z)
	end
end

function Canvas.render(self: Canvas)
	self.layer:ClearAllChildren()
	self.frame.BackgroundColor3 = self:backgroundColor()
	for _, stroke in self.strokes do
		self:renderStroke(stroke, self.layer)
	end
	self:renderSelection()
end

function Canvas.renderSelection(self: Canvas)
	if self.selectionBox then self.selectionBox:Destroy() self.selectionBox = nil end
	if #self.selection == 0 then return end
	local minX, minY, maxX, maxY = 1, 1, 0, 0
	for _, idx in self.selection do
		local s = self.strokes[idx]
		if s then
			local a, b, c, d = Strokes.bounds(s)
			minX, minY, maxX, maxY = math.min(minX, a), math.min(minY, b), math.max(maxX, c), math.max(maxY, d)
		end
	end
	if maxX < minX then return end
	self.selectionBox = Make("Frame", {
		BackgroundColor3 = Theme.accent2,
		BackgroundTransparency = 0.9,
		Position = UDim2.new(minX, -6, minY, -6),
		Size = UDim2.new(maxX - minX, 12, maxY - minY, 12),
		ZIndex = 6,
		Make("UIStroke", { Color = Theme.accent2, Thickness = 2, LineJoinMode = Enum.LineJoinMode.Round }),
		Parent = self.overlay,
	})
end

----------------------------------------------------------------------------
-- Data

function Canvas.setStrokes(self: Canvas, strokes: { Strokes.Stroke }?)
	self.strokes = strokes or {}
	self:setSelection({})
	self:render()
end

function Canvas.getStrokes(self: Canvas): { Strokes.Stroke }
	return self.strokes
end

function Canvas.applyOp(self: Canvas, op: string, payload: any)
	if op == "add" and payload then
		table.insert(self.strokes, payload)
		self:renderStroke(payload, self.layer)
		self.frame.BackgroundColor3 = self:backgroundColor()
	elseif op == "undo" then
		table.remove(self.strokes)
		self:render()
	elseif op == "clear" then
		self.strokes = {}
		self:render()
	elseif op == "set" and payload then
		self.strokes = payload
		self:render()
	end
end

function Canvas.changed(self: Canvas)
	if self.onChange then self.onChange() end
end

function Canvas.emit(self: Canvas, op: string, payload: any?)
	if self.onOp then self.onOp(op, payload) end
	self:changed()
end

function Canvas.commit(self: Canvas, stroke: Strokes.Stroke)
	if #self.strokes >= Config.MAX_STROKES_PER_PANEL then return end
	table.insert(self.strokes, stroke)
	self:renderStroke(stroke, self.layer)
	self:emit("add", stroke)
end

function Canvas.undo(self: Canvas)
	if #self.strokes > 0 then
		table.remove(self.strokes)
		self:setSelection({})
		self:render()
		self:emit("undo")
	end
end

function Canvas.clear(self: Canvas)
	self.strokes = {}
	self:setSelection({})
	self:render()
	self:emit("clear")
end

-- Whole-canvas rewrite (after fill/transform).
function Canvas.rewrite(self: Canvas)
	self:render()
	self:emit("set", self.strokes)
end

----------------------------------------------------------------------------
-- Selection / transform

function Canvas.setSelection(self: Canvas, indices: { number })
	self.selection = indices
	self:renderSelection()
	if self.onSelectionChanged then self.onSelectionChanged(#indices > 0) end
end

function Canvas.hasSelection(self: Canvas): boolean
	return #self.selection > 0
end

function Canvas.selectionCenter(self: Canvas): (number, number)
	local minX, minY, maxX, maxY = 1, 1, 0, 0
	for _, idx in self.selection do
		local s = self.strokes[idx]
		if s then
			local a, b, c, d = Strokes.bounds(s)
			minX, minY, maxX, maxY = math.min(minX, a), math.min(minY, b), math.max(maxX, c), math.max(maxY, d)
		end
	end
	return (minX + maxX) / 2, (minY + maxY) / 2
end

function Canvas.scaleSelection(self: Canvas, k: number)
	if #self.selection == 0 then return end
	local cx, cy = self:selectionCenter()
	for _, idx in self.selection do
		local s = self.strokes[idx]
		if s then Strokes.scaleAbout(s, cx, cy, k) end
	end
	self:rewrite()
end

function Canvas.flipSelection(self: Canvas)
	if #self.selection == 0 then return end
	local cx = self:selectionCenter()
	for _, idx in self.selection do
		local s = self.strokes[idx]
		if s then
			for i = 1, #s.p - 1, 2 do
				s.p[i] = math.clamp(2 * cx - s.p[i], 0, 1)
			end
		end
	end
	self:rewrite()
end

function Canvas.deleteSelection(self: Canvas)
	if #self.selection == 0 then return end
	local remove: { [number]: boolean } = {}
	for _, idx in self.selection do remove[idx] = true end
	local kept = {}
	for i, s in self.strokes do
		if not remove[i] then table.insert(kept, s) end
	end
	self.strokes = kept
	self:setSelection({})
	self:rewrite()
end

function Canvas.duplicateSelection(self: Canvas)
	if #self.selection == 0 then return end
	local newSel = {}
	for _, idx in self.selection do
		local s = self.strokes[idx]
		if s and #self.strokes < Config.MAX_STROKES_PER_PANEL then
			local copy = { t = s.t, c = table.clone(s.c), w = s.w, f = s.f, p = table.clone(s.p) }
			Strokes.translate(copy, 0.03, 0.03)
			table.insert(self.strokes, copy)
			table.insert(newSel, #self.strokes)
		end
	end
	self:setSelection(newSel)
	self:rewrite()
end

function Canvas.pick(self: Canvas, x: number, y: number): number?
	local best, bestD = nil, PICK_RADIUS
	for i = #self.strokes, 1, -1 do
		local s = self.strokes[i]
		local d = Strokes.distanceTo(s, x, y)
		if s.t == "p" then d = math.max(0, d - s.w / 2000) end
		if d < bestD then best, bestD = i, d end
	end
	return best
end

function Canvas.selectionContains(self: Canvas, x: number, y: number): boolean
	if #self.selection == 0 then return false end
	local minX, minY, maxX, maxY = 1, 1, 0, 0
	for _, idx in self.selection do
		local s = self.strokes[idx]
		if s then
			local a, b, c, d = Strokes.bounds(s)
			minX, minY, maxX, maxY = math.min(minX, a), math.min(minY, b), math.max(maxX, c), math.max(maxY, d)
		end
	end
	return x >= minX - 0.02 and x <= maxX + 0.02 and y >= minY - 0.02 and y <= maxY + 0.02
end

----------------------------------------------------------------------------
-- Fill

function Canvas.fillAt(self: Canvas, x: number, y: number)
	local idx = self:pick(x, y)
	local color = Strokes.fromColor3(self.color)
	if idx then
		local s = self.strokes[idx]
		if s.t == "r" or s.t == "c" then
			s.f = true
		end
		s.c = color
	else
		-- Background: replace any previous background fill.
		local kept = {}
		for _, s in self.strokes do
			if s.t ~= "bg" then table.insert(kept, s) end
		end
		table.insert(kept, 1, { t = "bg", c = color, w = Config.MIN_BRUSH, p = {} })
		self.strokes = kept
	end
	self:rewrite()
end

----------------------------------------------------------------------------
-- Input

function Canvas.toLocal(self: Canvas, pos: Vector2): (number, number)
	local abs = self.frame.AbsolutePosition
	local size = self.frame.AbsoluteSize
	return math.clamp((pos.X - abs.X) / size.X, 0, 1), math.clamp((pos.Y - abs.Y) / size.Y, 0, 1)
end

function Canvas.clearPreview(self: Canvas)
	for _, f in self.preview do f:Destroy() end
	self.preview = {}
end

function Canvas.strokeColor(self: Canvas): Color3
	return if self.tool == "eraser" then self:backgroundColor() else self.color
end

function Canvas.beginGesture(self: Canvas, pos: Vector2)
	local x, y = self:toLocal(pos)
	self.dragging = true
	self.startX, self.startY, self.lastX, self.lastY = x, y, x, y
	self:clearPreview()
	local tool = self.tool
	if tool == "brush" or tool == "eraser" then
		if #self.strokes >= Config.MAX_STROKES_PER_PANEL then self.dragging = false return end
		self.current = { t = "p", c = Strokes.fromColor3(self:strokeColor()), w = self.width, p = { x, y } }
		table.insert(self.preview, self:drawSegment(self.layer, self:strokeColor(), self.width, x, y, x, y))
	elseif tool == "lasso" then
		self.current = { t = "p", c = Strokes.fromColor3(Theme.accent2), w = 3, p = { x, y } }
	elseif tool == "select" then
		if not self:selectionContains(x, y) then
			local idx = self:pick(x, y)
			self:setSelection(if idx then { idx } else {})
		end
	elseif tool == "fill" then
		self.dragging = false
		self:fillAt(x, y)
	end
end

function Canvas.moveGesture(self: Canvas, pos: Vector2)
	if not self.dragging then return end
	local x, y = self:toLocal(pos)
	local tool = self.tool
	if tool == "brush" or tool == "eraser" or tool == "lasso" then
		local cur = self.current
		if not cur or #cur.p >= Config.MAX_POINTS_PER_STROKE * 2 then return end
		local lx, ly = cur.p[#cur.p - 1], cur.p[#cur.p]
		if (x - lx) ^ 2 + (y - ly) ^ 2 < MIN_POINT_DIST ^ 2 then return end
		table.insert(cur.p, x)
		table.insert(cur.p, y)
		local color = if tool == "lasso" then Theme.accent2 else self:strokeColor()
		table.insert(self.preview, self:drawSegment(if tool == "lasso" then self.overlay else self.layer, color, cur.w, lx, ly, x, y, if tool == "lasso" then 7 else nil))
	elseif tool == "rect" or tool == "circle" then
		self:clearPreview()
		local shape = { t = if tool == "rect" then "r" else "c", c = Strokes.fromColor3(self.color), w = self.width, f = self.filled, p = { self.startX, self.startY, x, y } }
		table.insert(self.preview, self:drawShape(self.overlay, shape, 7))
	elseif tool == "select" and #self.selection > 0 then
		local dx, dy = x - self.lastX, y - self.lastY
		for _, idx in self.selection do
			local s = self.strokes[idx]
			if s then Strokes.translate(s, dx, dy) end
		end
		self:render()
	end
	self.lastX, self.lastY = x, y
end

function Canvas.endGesture(self: Canvas)
	if not self.dragging then return end
	self.dragging = false
	local tool = self.tool
	local x, y = self.lastX, self.lastY
	if tool == "brush" or tool == "eraser" then
		local cur = self.current
		self:clearPreview()
		if cur then
			self:commit(cur)
			if self.mirror and tool ~= "eraser" then self:commit(Strokes.mirrorX(cur)) end
		end
	elseif tool == "rect" or tool == "circle" then
		self:clearPreview()
		if math.abs(x - self.startX) > 0.01 and math.abs(y - self.startY) > 0.01 then
			local shape = { t = if tool == "rect" then "r" else "c", c = Strokes.fromColor3(self.color), w = self.width, f = self.filled, p = { self.startX, self.startY, x, y } }
			self:commit(shape)
			if self.mirror then self:commit(Strokes.mirrorX(shape)) end
		end
	elseif tool == "lasso" then
		self:clearPreview()
		local cur = self.current
		if cur and #cur.p >= 6 then
			local sel = {}
			for i, s in self.strokes do
				if Strokes.insideLasso(s, cur.p) then table.insert(sel, i) end
			end
			self:setSelection(sel)
		end
	elseif tool == "select" and #self.selection > 0 then
		if math.abs(x - self.startX) > 0.002 or math.abs(y - self.startY) > 0.002 then
			self:rewrite()
		end
	end
	self.current = nil
end

local function isDrawInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

function Canvas.bindInput(self: Canvas)
	table.insert(self.connections, self.frame.InputBegan:Connect(function(input)
		if isDrawInput(input) then self:beginGesture(Vector2.new(input.Position.X, input.Position.Y)) end
	end))
	table.insert(self.connections, UserInputService.InputChanged:Connect(function(input)
		if not self.dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			self:moveGesture(Vector2.new(input.Position.X, input.Position.Y))
		end
	end))
	table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
		if isDrawInput(input) then self:endGesture() end
	end))
end

function Canvas.setTool(self: Canvas, tool: Tool)
	self.tool = tool
	if tool ~= "select" and tool ~= "lasso" then
		self:setSelection({})
	end
end

function Canvas.destroy(self: Canvas)
	for _, c in self.connections do c:Disconnect() end
	self.frame:Destroy()
end

return Canvas
