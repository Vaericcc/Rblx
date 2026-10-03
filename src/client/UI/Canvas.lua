--!strict
--[[
	Square drawing surface. Strokes are normalized (0..1) so the same data
	renders identically everywhere.

	Tools: brush, airbrush, eraser, rect, circle, fill, lasso, transform.
	Drawing tools paint immediately on press. In Transform, hovering a stroke
	highlights it and a tap selects it; the box has eight stretch handles and
	a rotate knob, drag inside to move. Lasso selects several strokes and
	hands them to Transform. Every change calls onOp(op, payload).
]]
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Strokes = require(Shared.Strokes)
local Make = require(script.Parent.Make)
local Theme = require(script.Parent.Theme)

local Canvas = {}
Canvas.__index = Canvas

export type Tool = "brush" | "airbrush" | "eraser" | "rect" | "circle" | "fill" | "lasso" | "transform"
type Gesture = "none" | "pending" | "draw" | "shape" | "lasso" | "move" | "stretch" | "rotate" | "warp"

export type Canvas = typeof(setmetatable({} :: {
	frame: Frame,
	layer: Frame,
	overlay: Frame,
	strokes: { Strokes.Stroke },
	editable: boolean,
	tool: Tool,
	color: Color3,
	width: number,
	opacity: number,
	mirror: boolean,
	filled: boolean,
	gesture: Gesture,
	startX: number, startY: number, lastX: number, lastY: number,
	current: Strokes.Stroke?,
	preview: { GuiObject },
	selection: { number },
	selBox: { number }?, -- minX,minY,maxX,maxY at gesture start
	snapshot: { Strokes.Stroke }?, -- copies of selected strokes at gesture start
	handle: string?, -- which handle is being dragged
	warpQuad: { number }?,
	hoverIdx: number?,
	hoverFrame: Frame?,
	boxFrame: Frame?,
	handles: { [string]: TextButton },
	connections: { RBXScriptConnection },
	onChange: (() -> ())?,
	onOp: ((string, any) -> ())?,
	onSelectionChanged: ((boolean, Frame?) -> ())?,
}, Canvas))

local MIN_POINT_DIST = 0.004
local TAP_DIST = 0.006 -- below this a press is a tap, not a drag
local PICK_RADIUS = 0.03
local HANDLE_PX = 18
local HANDLES = { "tl", "t", "tr", "r", "br", "b", "bl", "l" }

----------------------------------------------------------------------------

function Canvas.new(parent: Instance, editable: boolean): Canvas
	local self = setmetatable({}, Canvas)
	self.frame = Make("Frame", {
		BackgroundColor3 = Theme.paper, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		ClipsDescendants = true, Active = true,
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
	self.opacity = 1
	self.mirror = false
	self.filled = false
	self.gesture = "none"
	self.startX, self.startY, self.lastX, self.lastY = 0, 0, 0, 0
	self.current = nil
	self.preview = {}
	self.selection = {}
	self.selBox = nil
	self.snapshot = nil
	self.handle = nil
	self.warpQuad = nil
	self.hoverIdx = nil
	self.hoverFrame = nil
	self.boxFrame = nil
	self.handles = {}
	self.connections = {}
	table.insert(self.connections, self.frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:render() end))
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

function Canvas.drawSegment(self: Canvas, into: Frame, color: Color3, width: number, x1: number, y1: number, x2: number, y2: number, z: number?, alpha: number?)
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
	seg.BackgroundTransparency = 1 - (alpha or 1)
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
		f.BackgroundTransparency = 1 - (stroke.a or 1)
	else
		f.BackgroundTransparency = 1
		local outline = Instance.new("UIStroke")
		outline.Color = color
		outline.Thickness = wpx
		outline.Transparency = 1 - (stroke.a or 1)
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

function Canvas.renderStroke(self: Canvas, stroke: Strokes.Stroke, into: Frame, z: number?, colorOverride: Color3?, widthBoost: number?)
	if stroke.t == "bg" then return end
	if stroke.t == "r" or stroke.t == "c" then
		local f = self:drawShape(into, stroke, z)
		if colorOverride then
			f.BackgroundTransparency = 1
			local o = f:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", f)
			o.Color = colorOverride
			o.Thickness = math.max(2, (stroke.w * self:pixelsPerUnit() / 1000) + (widthBoost or 0))
		end
		return
	end
	local color = colorOverride or Strokes.toColor3(stroke.c)
	local w = stroke.w + (if widthBoost then widthBoost * 1000 / math.max(self:pixelsPerUnit(), 1) else 0)
	local alpha = if colorOverride then 1 else (stroke.a or 1)
	local p = stroke.p
	-- Airbrush: three concentric passes, wide and faint to narrow and solid.
	local passes = if stroke.s and not colorOverride then { { 1, 0.25 }, { 0.6, 0.45 }, { 0.3, 0.8 } } else { { 1, 1 } }
	for _, pass in passes do
		local pw, pa = w * pass[1], alpha * pass[2]
		if #p == 2 then
			self:drawSegment(into, color, pw, p[1], p[2], p[1], p[2], z, pa)
		else
			for i = 1, #p - 3, 2 do
				self:drawSegment(into, color, pw, p[i], p[i + 1], p[i + 2], p[i + 3], z, pa)
			end
		end
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

function Canvas.selectionBounds(self: Canvas): (number, number, number, number)
	local minX, minY, maxX, maxY = 1, 1, 0, 0
	for _, idx in self.selection do
		local s = self.strokes[idx]
		if s then
			local a, b, c, d = Strokes.bounds(s)
			minX, minY, maxX, maxY = math.min(minX, a), math.min(minY, b), math.max(maxX, c), math.max(maxY, d)
		end
	end
	return minX, minY, maxX, maxY
end

function Canvas.renderSelection(self: Canvas)
	if self.boxFrame then self.boxFrame:Destroy() self.boxFrame = nil end
	self.handles = {}
	if #self.selection == 0 then return end
	local minX, minY, maxX, maxY = self:selectionBounds()
	if maxX < minX then return end
	local pad = 8
	local box = Make("Frame", {
		Active = true,
		BackgroundColor3 = Theme.accent2, BackgroundTransparency = 0.92,
		Position = UDim2.new(minX, -pad, minY, -pad), Size = UDim2.new(maxX - minX, pad * 2, maxY - minY, pad * 2),
		ZIndex = 6,
		Make("UIStroke", { Color = Theme.accent2, Thickness = 2 }),
		Parent = self.overlay,
	})
	self.boxFrame = box
	-- Pressing a handle must start the gesture on the handle, not the canvas
	-- underneath: GUI input goes to the topmost object only.
	local function bindHandle(h: TextButton, name: string)
		h.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				self:beginHandle(name, Vector2.new(input.Position.X, input.Position.Y))
			end
		end)
	end
	box.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self:beginGesture(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	local positions = {
		tl = Vector2.new(0, 0), t = Vector2.new(0.5, 0), tr = Vector2.new(1, 0), r = Vector2.new(1, 0.5),
		br = Vector2.new(1, 1), b = Vector2.new(0.5, 1), bl = Vector2.new(0, 1), l = Vector2.new(0, 0.5),
	}
	for _, name in HANDLES do
		local pos = positions[name]
		local isCorner = #name == 2
		local h = Make("TextButton", {
			Text = "", AutoButtonColor = false,
			BackgroundColor3 = if isCorner then Theme.accent2 else Theme.paper,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(pos.X, pos.Y),
			Size = UDim2.fromOffset(HANDLE_PX, HANDLE_PX),
			ZIndex = 8,
			Make.corner(UDim.new(0, if isCorner then 4 else 9)),
			Make("UIStroke", { Color = Theme.accent2, Thickness = 2 }),
			Parent = box,
		})
		self.handles[name] = h
		bindHandle(h, name)
	end
	-- Rotate handle above the top edge
	local stem = Make("Frame", { BackgroundColor3 = Theme.accent2, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(2, 26), ZIndex = 7, Parent = box })
	local rot = Make("TextButton", {
		Text = "R", TextSize = 13, Font = Theme.font, TextColor3 = Theme.bg, AutoButtonColor = false,
		BackgroundColor3 = Theme.accent, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -26),
		Size = UDim2.fromOffset(HANDLE_PX + 6, HANDLE_PX + 6), ZIndex = 8,
		Make.corner(UDim.new(0.5, 0)), Make("UIStroke", { Color = Theme.bg, Thickness = 1.5 }), Parent = box,
	})
	self.handles.rotate = rot
	bindHandle(rot, "rotate")
	stem.Parent = box
	if self.onSelectionChanged then self.onSelectionChanged(true, box) end
end

function Canvas.setHover(self: Canvas, idx: number?)
	if idx == self.hoverIdx then return end
	self.hoverIdx = idx
	if self.hoverFrame then self.hoverFrame:Destroy() self.hoverFrame = nil end
	if not idx or table.find(self.selection, idx) then return end
	local s = self.strokes[idx]
	if not s then return end
	local f = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = self.overlay })
	self:renderStroke(s, f, 4, Theme.accent2, 6)
	self.hoverFrame = f
end

----------------------------------------------------------------------------
-- Data + ops

function Canvas.setStrokes(self: Canvas, strokes: { Strokes.Stroke }?)
	self.strokes = strokes or {}
	self:setSelection({})
	self:render()
end

function Canvas.getStrokes(self: Canvas): { Strokes.Stroke } return self.strokes end

function Canvas.applyOp(self: Canvas, op: string, payload: any)
	if op == "add" and payload then
		table.insert(self.strokes, payload)
		self:renderStroke(payload, self.layer)
		self.frame.BackgroundColor3 = self:backgroundColor()
	elseif op == "undo" then table.remove(self.strokes) self:render()
	elseif op == "clear" then self.strokes = {} self:render()
	elseif op == "set" and payload then self.strokes = payload self:render() end
end

function Canvas.emit(self: Canvas, op: string, payload: any?)
	if self.onOp then self.onOp(op, payload) end
	if self.onChange then self.onChange() end
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

function Canvas.rewrite(self: Canvas)
	self:render()
	self:emit("set", self.strokes)
end

----------------------------------------------------------------------------
-- Selection + transforms

function Canvas.setSelection(self: Canvas, indices: { number })
	self.selection = indices
	self:setHover(nil)
	self:renderSelection()
	if #indices == 0 and self.onSelectionChanged then self.onSelectionChanged(false, nil) end
end

function Canvas.hasSelection(self: Canvas): boolean return #self.selection > 0 end

function Canvas.selectAll(self: Canvas)
	local all = {}
	for i, s in self.strokes do if s.t ~= "bg" then table.insert(all, i) end end
	self:setSelection(all)
end

function Canvas.forSelected(self: Canvas, fn: (Strokes.Stroke, number) -> Strokes.Stroke?)
	for _, idx in self.selection do
		local s = self.strokes[idx]
		if s then
			local replaced = fn(s, idx)
			if replaced then self.strokes[idx] = replaced end
		end
	end
	self:rewrite()
end

function Canvas.scaleSelection(self: Canvas, k: number)
	if #self.selection == 0 then return end
	local minX, minY, maxX, maxY = self:selectionBounds()
	local cx, cy = (minX + maxX) / 2, (minY + maxY) / 2
	self:forSelected(function(s) Strokes.scaleAbout(s, cx, cy, k) return nil end)
end

function Canvas.flipSelection(self: Canvas, vertical: boolean?)
	if #self.selection == 0 then return end
	local minX, minY, maxX, maxY = self:selectionBounds()
	local cx, cy = (minX + maxX) / 2, (minY + maxY) / 2
	self:forSelected(function(s)
		if vertical then
			Strokes.mirrorY(s, cy)
		else
			for i = 1, #s.p - 1, 2 do s.p[i] = math.clamp(2 * cx - s.p[i], 0, 1) end
		end
		return nil
	end)
end

function Canvas.rotateSelection(self: Canvas, radians: number)
	if #self.selection == 0 then return end
	local minX, minY, maxX, maxY = self:selectionBounds()
	local cx, cy = (minX + maxX) / 2, (minY + maxY) / 2
	self:forSelected(function(s) return Strokes.rotateAbout(s, cx, cy, radians) end)
end

function Canvas.deleteSelection(self: Canvas)
	if #self.selection == 0 then return end
	local remove: { [number]: boolean } = {}
	for _, idx in self.selection do remove[idx] = true end
	local kept = {}
	for i, s in self.strokes do if not remove[i] then table.insert(kept, s) end end
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
			local copy = Strokes.copy(s)
			Strokes.translate(copy, 0.03, 0.03)
			table.insert(self.strokes, copy)
			table.insert(newSel, #self.strokes)
		end
	end
	self:setSelection(newSel)
	self:rewrite()
end

-- Warp mode: the next drag of a corner handle bends the selection instead of scaling it.
function Canvas.beginWarpMode(self: Canvas)
	if #self.selection == 0 then return end
	self.gesture = "none"
	self.handle = "warpmode"
	for _, h in self.handles do h.BackgroundColor3 = Theme.pop end
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
	local minX, minY, maxX, maxY = self:selectionBounds()
	return x >= minX - 0.02 and x <= maxX + 0.02 and y >= minY - 0.02 and y <= maxY + 0.02
end

function Canvas.handleAt(self: Canvas, pos: Vector2): string?
	for name, h in self.handles do
		local p, s = h.AbsolutePosition, h.AbsoluteSize
		if pos.X >= p.X - 6 and pos.X <= p.X + s.X + 6 and pos.Y >= p.Y - 6 and pos.Y <= p.Y + s.Y + 6 then
			return name
		end
	end
	return nil
end

function Canvas.takeSnapshot(self: Canvas)
	local snap = {}
	for _, idx in self.selection do
		local s = self.strokes[idx]
		snap[idx] = Strokes.copy(s)
	end
	self.snapshot = snap
	local minX, minY, maxX, maxY = self:selectionBounds()
	self.selBox = { minX, minY, maxX, maxY }
end

----------------------------------------------------------------------------
-- Fill

function Canvas.fillAt(self: Canvas, x: number, y: number)
	local idx = self:pick(x, y)
	local color = Strokes.fromColor3(self.color)
	if idx then
		local s = self.strokes[idx]
		if s.t == "r" or s.t == "c" then s.f = true end
		s.c = color
	else
		local kept = {}
		for _, s in self.strokes do if s.t ~= "bg" then table.insert(kept, s) end end
		table.insert(kept, 1, { t = "bg", c = color, w = Config.MIN_BRUSH, p = {} })
		self.strokes = kept
	end
	self:rewrite()
end

----------------------------------------------------------------------------
-- Gestures

function Canvas.toLocal(self: Canvas, pos: Vector2): (number, number)
	local abs, size = self.frame.AbsolutePosition, self.frame.AbsoluteSize
	return math.clamp((pos.X - abs.X) / size.X, 0, 1), math.clamp((pos.Y - abs.Y) / size.Y, 0, 1)
end

function Canvas.clearPreview(self: Canvas)
	for _, f in self.preview do f:Destroy() end
	self.preview = {}
end

function Canvas.strokeColor(self: Canvas): Color3
	return if self.tool == "eraser" then self:backgroundColor() else self.color
end

-- A press that started on a transform handle.
function Canvas.beginHandle(self: Canvas, name: string, pos: Vector2)
	if #self.selection == 0 or self.gesture ~= "none" then return end
	local x, y = self:toLocal(pos)
	self.startX, self.startY, self.lastX, self.lastY = x, y, x, y
	self:takeSnapshot()
	if name == "rotate" then
		self.gesture = "rotate"
	elseif self.handle == "warpmode" and #name == 2 then
		self.gesture = "warp"
		local b = self.selBox :: { number }
		self.warpQuad = { b[1], b[2], b[3], b[2], b[3], b[4], b[1], b[4] }
	else
		self.gesture = "stretch"
	end
	self.handle = name
end

function Canvas.beginGesture(self: Canvas, pos: Vector2)
	if self.gesture ~= "none" then return end
	local x, y = self:toLocal(pos)
	self.startX, self.startY, self.lastX, self.lastY = x, y, x, y
	self:clearPreview()

	if self.tool == "transform" then
		if #self.selection > 0 and self:selectionContains(x, y) then
			self:takeSnapshot()
			self.gesture = "move"
			return
		end
		-- A tap on a stroke selects it; a tap on paper deselects.
		self.gesture = "pending"
		return
	end
	if self.tool == "fill" then
		self:fillAt(x, y)
		return
	end
	if #self.selection > 0 then self:setSelection({}) end
	self:startDrawing()
end

function Canvas.startDrawing(self: Canvas)
	local tool = self.tool
	local x, y = self.startX, self.startY
	if tool == "brush" or tool == "airbrush" or tool == "eraser" then
		if #self.strokes >= Config.MAX_STROKES_PER_PANEL then self.gesture = "none" return end
		self.gesture = "draw"
		local alpha = if tool == "eraser" then 1 else self.opacity
		self.current = { t = "p", c = Strokes.fromColor3(self:strokeColor()), w = self.width, a = alpha, s = if tool == "airbrush" then true else nil, p = { x, y } }
		table.insert(self.preview, self:drawSegment(self.layer, self:strokeColor(), self.width, x, y, x, y, nil, if tool == "airbrush" then alpha * 0.5 else alpha))
	elseif tool == "lasso" then
		self.gesture = "lasso"
		self.current = { t = "p", c = Strokes.fromColor3(Theme.accent2), w = 3, p = { x, y } }
	elseif tool == "rect" or tool == "circle" then
		self.gesture = "shape"
	end
end

function Canvas.moveGesture(self: Canvas, pos: Vector2)
	local x, y = self:toLocal(pos)
	local g = self.gesture
	if g == "none" then return end

	if g == "pending" then
		-- In Transform a drag on empty paper does nothing.
		return
	end

	if g == "draw" or g == "lasso" then
		local cur = self.current
		if not cur or #cur.p >= Config.MAX_POINTS_PER_STROKE * 2 then return end
		local lx, ly = cur.p[#cur.p - 1], cur.p[#cur.p]
		if (x - lx) ^ 2 + (y - ly) ^ 2 < MIN_POINT_DIST ^ 2 then return end
		table.insert(cur.p, x)
		table.insert(cur.p, y)
		local color = if g == "lasso" then Theme.accent2 else self:strokeColor()
		local alpha = if g == "lasso" then 1 elseif cur.s then (cur.a or 1) * 0.5 else (cur.a or 1)
		table.insert(self.preview, self:drawSegment(if g == "lasso" then self.overlay else self.layer, color, cur.w, lx, ly, x, y, if g == "lasso" then 7 else nil, alpha))
	elseif g == "shape" then
		self:clearPreview()
		local shape = { t = if self.tool == "rect" then "r" else "c", c = Strokes.fromColor3(self.color), w = self.width, a = self.opacity, f = self.filled, p = { self.startX, self.startY, x, y } }
		table.insert(self.preview, self:drawShape(self.overlay, shape, 7))
	elseif g == "move" then
		local dx, dy = x - self.startX, y - self.startY
		self:applyFromSnapshot(function(s) Strokes.translate(s, dx, dy) return s end)
	elseif g == "stretch" then
		self:applyStretch(x, y)
	elseif g == "rotate" then
		local b = self.selBox :: { number }
		local cx, cy = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2
		local a0 = math.atan2(self.startY - cy, self.startX - cx)
		local a1 = math.atan2(y - cy, x - cx)
		local angle = a1 - a0
		self:applyFromSnapshot(function(s) return Strokes.rotateAbout(s, cx, cy, angle) end)
	elseif g == "warp" then
		local q = self.warpQuad :: { number }
		local map = { tl = 1, tr = 3, br = 5, bl = 7 }
		local i = map[self.handle :: string]
		if i then q[i], q[i + 1] = x, y end
		local b = self.selBox :: { number }
		self:applyFromSnapshot(function(s) return Strokes.warp(s, b, q) end)
	end
	self.lastX, self.lastY = x, y
end

-- Re-derive selected strokes from the gesture-start snapshot (so drags don't accumulate error).
function Canvas.applyFromSnapshot(self: Canvas, fn: (Strokes.Stroke) -> Strokes.Stroke)
	local snap = self.snapshot
	if not snap then return end
	for idx, original in snap do
		self.strokes[idx] = fn(Strokes.copy(original))
	end
	self:render()
end

function Canvas.applyStretch(self: Canvas, x: number, y: number)
	local b = self.selBox :: { number }
	local h = self.handle :: string
	local minX, minY, maxX, maxY = b[1], b[2], b[3], b[4]
	local w, hgt = math.max(maxX - minX, 1e-4), math.max(maxY - minY, 1e-4)
	-- anchor is the opposite side/corner
	local ax = if h:find("l") then maxX elseif h:find("r") then minX else (minX + maxX) / 2
	local ay = if h:find("t") then minY elseif h:find("b") then maxY else (minY + maxY) / 2
	-- careful: "t" means top edge handle; "tl"/"tr" contain t. Anchor y for top handles is the bottom.
	if h == "t" or h == "tl" or h == "tr" then ay = maxY end
	if h == "b" or h == "bl" or h == "br" then ay = minY end
	local kx, ky = 1, 1
	if h:find("l") or h:find("r") then
		kx = (x - ax) / ((if h:find("l") then minX else maxX) - ax)
	end
	if h == "t" or h == "tl" or h == "tr" or h == "b" or h == "bl" or h == "br" then
		local edgeY = if (h == "t" or h == "tl" or h == "tr") then minY else maxY
		ky = (y - ay) / (edgeY - ay)
	end
	if #h == 2 then
		-- corners keep proportion
		local k = math.max(math.abs(kx), math.abs(ky))
		kx = if kx < 0 then -k else k
		ky = if ky < 0 then -k else k
	end
	kx = math.clamp(kx, -8, 8)
	ky = math.clamp(ky, -8, 8)
	if math.abs(kx) < 0.05 then kx = 0.05 end
	if math.abs(ky) < 0.05 then ky = 0.05 end
	self:applyFromSnapshot(function(s)
		Strokes.scaleXY(s, ax, ay, kx, ky)
		return s
	end)
end

function Canvas.endGesture(self: Canvas)
	local g = self.gesture
	self.gesture = "none"
	local x, y = self.lastX, self.lastY
	if g == "pending" then
		-- Transform tap: select what's under the finger, or deselect on empty paper.
		local idx = self:pick(self.startX, self.startY)
		self:setSelection(if idx then { idx } else {})
		self.handle = nil
	elseif g == "draw" then
		local cur = self.current
		self:clearPreview()
		if cur then
			self:commit(cur)
			if self.mirror and self.tool ~= "eraser" then self:commit(Strokes.mirrorX(cur)) end
		end
	elseif g == "shape" then
		self:clearPreview()
		if math.abs(x - self.startX) > 0.01 and math.abs(y - self.startY) > 0.01 then
			local shape = { t = if self.tool == "rect" then "r" else "c", c = Strokes.fromColor3(self.color), w = self.width, a = self.opacity, f = self.filled, p = { self.startX, self.startY, x, y } }
			self:commit(shape)
			if self.mirror then self:commit(Strokes.mirrorX(shape)) end
		end
	elseif g == "lasso" then
		self:clearPreview()
		local cur = self.current
		if cur and #cur.p >= 6 then
			local sel = {}
			for i, s in self.strokes do if Strokes.insideLasso(s, cur.p) then table.insert(sel, i) end end
			self:setSelection(sel)
		end
	elseif g == "move" or g == "stretch" or g == "rotate" or g == "warp" then
		self.snapshot = nil
		self.selBox = nil
		self.warpQuad = nil
		if g == "warp" then self.handle = nil end
		self:renderSelection()
		self:emit("set", self.strokes)
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
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			if self.gesture ~= "none" then
				self:moveGesture(pos)
			elseif input.UserInputType == Enum.UserInputType.MouseMovement then
				-- Hover highlight (mouse only)
				local abs, size = self.frame.AbsolutePosition, self.frame.AbsoluteSize
				if pos.X >= abs.X and pos.X <= abs.X + size.X and pos.Y >= abs.Y and pos.Y <= abs.Y + size.Y then
					local x, y = self:toLocal(pos)
					self:setHover(if self.tool == "transform" then self:pick(x, y) else nil)
				else
					self:setHover(nil)
				end
			end
		end
	end))
	table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
		if isDrawInput(input) and self.gesture ~= "none" then self:endGesture() end
	end))
end

function Canvas.setTool(self: Canvas, tool: Tool)
	self.tool = tool
	self.handle = nil
	if tool ~= "transform" and tool ~= "lasso" then self:setSelection({}) end
	self:setHover(nil)
end

function Canvas.destroy(self: Canvas)
	for _, c in self.connections do c:Disconnect() end
	self.frame:Destroy()
end

return Canvas
