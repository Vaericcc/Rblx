--!strict
--[[
	Square drawing surface. Strokes are stored normalized (0..1) so the same
	data renders identically at any size, on any client.
]]
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Strokes = require(Shared.Strokes)
local Make = require(script.Parent.Make)
local Theme = require(script.Parent.Theme)

local Canvas = {}
Canvas.__index = Canvas

export type Canvas = typeof(setmetatable({} :: {
	frame: Frame,
	layer: Frame,
	strokes: { Strokes.Stroke },
	editable: boolean,
	color: Color3,
	width: number,
	drawing: boolean,
	current: Strokes.Stroke?,
	currentFrames: { GuiObject },
	connections: { RBXScriptConnection },
	onChange: (() -> ())?,
}, Canvas))

local MIN_POINT_DIST = 0.004 -- normalized; filters jitter

function Canvas.new(parent: Instance, editable: boolean): Canvas
	local self = setmetatable({}, Canvas)
	self.frame = Make("Frame", {
		BackgroundColor3 = Theme.paper,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ClipsDescendants = true,
		Make.corner(UDim.new(0, 6)),
		Make("UIAspectRatioConstraint", { AspectRatio = 1 }),
		Parent = parent,
	})
	self.layer = Make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = self.frame,
	})
	self.strokes = {}
	self.editable = editable
	self.color = Theme.palette[1]
	self.width = Theme.brushSizes[2]
	self.drawing = false
	self.current = nil
	self.currentFrames = {}
	self.connections = {}
	self.onChange = nil

	table.insert(self.connections, self.frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:render()
	end))

	if editable then
		self:bindInput()
	end
	return self
end

function Canvas.pixelsPerUnit(self: Canvas): number
	return self.frame.AbsoluteSize.X
end

-- Draw one segment (or a dot) into `into`
function Canvas.drawSegment(self: Canvas, into: Frame, color: Color3, width: number, x1: number, y1: number, x2: number, y2: number)
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
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = seg
	seg.Parent = into
	return seg
end

function Canvas.renderStroke(self: Canvas, stroke: Strokes.Stroke, into: Frame)
	local color = Strokes.toColor3(stroke.c)
	local p = stroke.p
	if #p == 2 then
		self:drawSegment(into, color, stroke.w, p[1], p[2], p[1], p[2])
		return
	end
	for i = 1, #p - 3, 2 do
		self:drawSegment(into, color, stroke.w, p[i], p[i + 1], p[i + 2], p[i + 3])
	end
end

function Canvas.render(self: Canvas)
	self.layer:ClearAllChildren()
	for _, stroke in self.strokes do
		self:renderStroke(stroke, self.layer)
	end
end

function Canvas.setStrokes(self: Canvas, strokes: { Strokes.Stroke }?)
	self.strokes = strokes or {}
	self:render()
end

function Canvas.getStrokes(self: Canvas): { Strokes.Stroke }
	return self.strokes
end

function Canvas.undo(self: Canvas)
	if #self.strokes > 0 then
		table.remove(self.strokes)
		self:render()
		if self.onChange then self.onChange() end
	end
end

function Canvas.clear(self: Canvas)
	self.strokes = {}
	self:render()
	if self.onChange then self.onChange() end
end

function Canvas.toLocal(self: Canvas, pos: Vector2): (number, number)
	local abs = self.frame.AbsolutePosition
	local size = self.frame.AbsoluteSize
	return math.clamp((pos.X - abs.X) / size.X, 0, 1), math.clamp((pos.Y - abs.Y) / size.Y, 0, 1)
end

function Canvas.beginStroke(self: Canvas, pos: Vector2)
	if #self.strokes >= Config.MAX_STROKES_PER_PANEL then return end
	local x, y = self:toLocal(pos)
	self.drawing = true
	self.current = { c = Strokes.fromColor3(self.color), w = self.width, p = { x, y } }
	self.currentFrames = { self:drawSegment(self.layer, self.color, self.width, x, y, x, y) }
end

function Canvas.extendStroke(self: Canvas, pos: Vector2)
	local cur = self.current
	if not self.drawing or not cur then return end
	if #cur.p >= Config.MAX_POINTS_PER_STROKE * 2 then return end
	local x, y = self:toLocal(pos)
	local lx, ly = cur.p[#cur.p - 1], cur.p[#cur.p]
	if (x - lx) ^ 2 + (y - ly) ^ 2 < MIN_POINT_DIST ^ 2 then return end
	table.insert(cur.p, x)
	table.insert(cur.p, y)
	table.insert(self.currentFrames, self:drawSegment(self.layer, self.color, self.width, lx, ly, x, y))
end

function Canvas.endStroke(self: Canvas)
	if not self.drawing then return end
	self.drawing = false
	if self.current then
		table.insert(self.strokes, self.current)
	end
	self.current = nil
	self.currentFrames = {}
	if self.onChange then self.onChange() end
end

local function isDrawInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

function Canvas.bindInput(self: Canvas)
	table.insert(self.connections, self.frame.InputBegan:Connect(function(input)
		if isDrawInput(input) then
			self:beginStroke(Vector2.new(input.Position.X, input.Position.Y))
		end
	end))
	table.insert(self.connections, UserInputService.InputChanged:Connect(function(input)
		if not self.drawing then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			self:extendStroke(Vector2.new(input.Position.X, input.Position.Y))
		end
	end))
	table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
		if isDrawInput(input) then
			self:endStroke()
		end
	end))
end

function Canvas.destroy(self: Canvas)
	for _, c in self.connections do c:Disconnect() end
	self.frame:Destroy()
end

return Canvas
