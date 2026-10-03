--!strict
--[[
	Compact colour picker: a hue ring built from rotated segments, plus
	saturation and value sliders and a live preview. No image assets needed.
	ColorPicker.new(parent, initial, onChange) -> picker; picker:set(color)
]]
local UserInputService = game:GetService("UserInputService")
local Make = require(script.Parent.Make)
local Theme = require(script.Parent.Theme)

local ColorPicker = {}
ColorPicker.__index = ColorPicker

export type ColorPicker = typeof(setmetatable({} :: {
	frame: Frame,
	ring: Frame,
	preview: Frame,
	satFill: Frame,
	valFill: Frame,
	satTrack: TextButton,
	valTrack: TextButton,
	h: number, s: number, v: number,
	onChange: (Color3) -> (),
	connections: { RBXScriptConnection },
}, ColorPicker))

local RING_SEGMENTS = 36

function ColorPicker.new(parent: Instance, initial: Color3, onChange: (Color3) -> ()): ColorPicker
	local self = setmetatable({}, ColorPicker)
	self.onChange = onChange
	self.connections = {}
	self.h, self.s, self.v = initial:ToHSV()

	self.frame = Make("Frame", {
		BackgroundColor3 = Theme.panel, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Make.corner(), Make.pad(10), Make.list(nil, 8, Enum.HorizontalAlignment.Center), Parent = parent,
	})

	-- Hue ring
	local ringSize = 190
	self.ring = Make("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromOffset(ringSize, ringSize), LayoutOrder = 1, Parent = self.frame,
	}) :: any
	local radius = ringSize / 2 - 11
	for i = 0, RING_SEGMENTS - 1 do
		local a = i / RING_SEGMENTS * math.pi * 2
		Make("Frame", {
			BackgroundColor3 = Color3.fromHSV(i / RING_SEGMENTS, 1, 1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(a) * radius, 0.5, math.sin(a) * radius),
			Size = UDim2.fromOffset(2 * math.pi * radius / RING_SEGMENTS + 2, 20),
			Rotation = math.deg(a) + 90,
			BorderSizePixel = 0,
			Parent = self.ring,
		})
	end
	local hueKnob = Make("Frame", {
		BackgroundColor3 = Theme.text, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(16, 16), ZIndex = 3,
		Make.corner(UDim.new(0.5, 0)), Make("UIStroke", { Color = Theme.bg, Thickness = 2 }), Parent = self.ring,
	})

	-- Saturation / brightness square inside the ring (Clip Studio style):
	-- white -> hue left to right, then transparent -> black top to bottom.
	local sq = math.floor((ringSize - 56) / math.sqrt(2))
	local svBase = Make("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(sq, sq), ZIndex = 2,
		Make.corner(UDim.new(0, 4)), Make("UIStroke", { Color = Theme.bg, Thickness = 2 }), Parent = self.ring,
	})
	local hueGrad = Make("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(self.h, 1, 1)), Parent = svBase })
	local svDark = Make("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.fromScale(1, 1), ZIndex = 3, Make.corner(UDim.new(0, 4)), Parent = svBase,
	})
	Make("UIGradient", { Color = ColorSequence.new(Color3.new(0, 0, 0)), Transparency = NumberSequence.new(1, 0), Rotation = 90, Parent = svDark })
	local svKnob = Make("Frame", {
		BackgroundColor3 = Theme.text, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14), ZIndex = 4,
		Make.corner(UDim.new(0.5, 0)), Make("UIStroke", { Color = Theme.bg, Thickness = 2 }), Parent = svBase,
	})
	-- Current colour swatch
	self.preview = Make("Frame", {
		BackgroundColor3 = initial, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 2, Make.corner(UDim.new(0, 6)),
		Make("UIStroke", { Color = Theme.text, Thickness = 1, Transparency = 0.5 }), Parent = self.frame,
	})
	-- Keep the type's slider fields pointing at something harmless
	self.satTrack, self.satFill = svBase, svDark
	self.valTrack, self.valFill = svBase, svDark

	local draggingHue, draggingSV = false, false
	local function apply()
		local color = Color3.fromHSV(self.h, self.s, self.v)
		self.preview.BackgroundColor3 = color
		hueGrad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(self.h, 1, 1))
		local a = self.h * math.pi * 2
		hueKnob.Position = UDim2.new(0.5, math.cos(a) * radius, 0.5, math.sin(a) * radius)
		svKnob.Position = UDim2.fromScale(self.s, 1 - self.v)
		self.onChange(color)
	end
	local function hueFrom(pos: Vector2)
		local c = self.ring.AbsolutePosition + self.ring.AbsoluteSize / 2
		local d = pos - c
		local a = math.atan2(d.Y, d.X)
		if a < 0 then a += math.pi * 2 end
		self.h = a / (math.pi * 2)
		apply()
	end
	local function svFrom(pos: Vector2)
		local p, sz = svBase.AbsolutePosition, svBase.AbsoluteSize
		self.s = math.clamp((pos.X - p.X) / math.max(sz.X, 1), 0, 1)
		self.v = 1 - math.clamp((pos.Y - p.Y) / math.max(sz.Y, 1), 0, 1)
		apply()
	end
	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	self.ring.InputBegan:Connect(function(input) if isPress(input) then draggingHue = true hueFrom(Vector2.new(input.Position.X, input.Position.Y)) end end)
	svBase.InputBegan:Connect(function(input) if isPress(input) then draggingSV = true svFrom(Vector2.new(input.Position.X, input.Position.Y)) end end)
	table.insert(self.connections, UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if draggingSV then svFrom(pos) elseif draggingHue then hueFrom(pos) end
	end))
	table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
		if isPress(input) then draggingHue, draggingSV = false, false end
	end))
	apply()
	return self
end

function ColorPicker.set(self: ColorPicker, color: Color3)
	self.h, self.s, self.v = color:ToHSV()
	self.preview.BackgroundColor3 = color
end

function ColorPicker.destroy(self: ColorPicker)
	for _, c in self.connections do c:Disconnect() end
	self.frame:Destroy()
end

return ColorPicker
