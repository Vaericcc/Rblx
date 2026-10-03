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
local RING_SIZE = 150

local function slider(parent: Instance, label: string, order: number): (TextButton, Frame)
	Make.label(label, 11, { TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = order, Parent = parent })
	local track = Make("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.bg, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = order + 1,
		Make.corner(UDim.new(0.5, 0)), Parent = parent,
	})
	local fill = Make("Frame", { BackgroundColor3 = Theme.accent2, Size = UDim2.new(1, 0, 1, 0), Make.corner(UDim.new(0.5, 0)), Parent = track })
	local knob = Make("Frame", { BackgroundColor3 = Theme.text, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(16, 16), ZIndex = 2, Make.corner(UDim.new(0.5, 0)), Make("UIStroke", { Color = Theme.bg, Thickness = 2 }), Parent = fill })
	knob.Name = "Knob"
	return track, fill
end

function ColorPicker.new(parent: Instance, initial: Color3, onChange: (Color3) -> ()): ColorPicker
	local self = setmetatable({}, ColorPicker)
	self.onChange = onChange
	self.connections = {}
	self.h, self.s, self.v = initial:ToHSV()

	self.frame = Make("Frame", {
		BackgroundColor3 = Theme.panel, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Make.corner(), Make.pad(10), Make.list(nil, 6, Enum.HorizontalAlignment.Center), Parent = parent,
	})

	-- Hue ring
	self.ring = Make("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromOffset(RING_SIZE, RING_SIZE), LayoutOrder = 1, Parent = self.frame,
	}) :: any
	local radius = RING_SIZE / 2 - 10
	for i = 0, RING_SEGMENTS - 1 do
		local a = i / RING_SEGMENTS * math.pi * 2
		Make("Frame", {
			BackgroundColor3 = Color3.fromHSV(i / RING_SEGMENTS, 1, 1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(a) * radius, 0.5, math.sin(a) * radius),
			Size = UDim2.fromOffset(2 * math.pi * radius / RING_SEGMENTS + 2, 18),
			Rotation = math.deg(a) + 90,
			BorderSizePixel = 0,
			Parent = self.ring,
		})
	end
	self.preview = Make("Frame", {
		BackgroundColor3 = initial, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(RING_SIZE - 56, RING_SIZE - 56), Make.corner(UDim.new(0.5, 0)),
		Make("UIStroke", { Color = Theme.text, Thickness = 2 }), Parent = self.ring,
	})
	local hueKnob = Make("Frame", {
		BackgroundColor3 = Theme.text, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14), ZIndex = 3,
		Make.corner(UDim.new(0.5, 0)), Make("UIStroke", { Color = Theme.bg, Thickness = 2 }), Parent = self.ring,
	})
	hueKnob.Name = "HueKnob"

	self.satTrack, self.satFill = slider(self.frame, "Saturation", 10)
	self.valTrack, self.valFill = slider(self.frame, "Brightness", 20)

	local draggingHue, draggingSat, draggingVal = false, false, false
	local function apply()
		local color = Color3.fromHSV(self.h, self.s, self.v)
		self.preview.BackgroundColor3 = color
		self.satFill.Size = UDim2.new(self.s, 0, 1, 0)
		self.valFill.Size = UDim2.new(self.v, 0, 1, 0)
		self.satFill.BackgroundColor3 = Color3.fromHSV(self.h, 1, 1)
		self.valFill.BackgroundColor3 = Color3.fromHSV(self.h, self.s, 1)
		local a = self.h * math.pi * 2
		hueKnob.Position = UDim2.new(0.5, math.cos(a) * radius, 0.5, math.sin(a) * radius)
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
	local function frac(track: GuiObject, x: number): number
		return math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
	end
	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	self.ring.InputBegan:Connect(function(input) if isPress(input) then draggingHue = true hueFrom(Vector2.new(input.Position.X, input.Position.Y)) end end)
	self.satTrack.InputBegan:Connect(function(input) if isPress(input) then draggingSat = true self.s = frac(self.satTrack, input.Position.X) apply() end end)
	self.valTrack.InputBegan:Connect(function(input) if isPress(input) then draggingVal = true self.v = frac(self.valTrack, input.Position.X) apply() end end)
	table.insert(self.connections, UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if draggingHue then hueFrom(Vector2.new(input.Position.X, input.Position.Y))
		elseif draggingSat then self.s = frac(self.satTrack, input.Position.X) apply()
		elseif draggingVal then self.v = frac(self.valTrack, input.Position.X) apply() end
	end))
	table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
		if isPress(input) then draggingHue, draggingSat, draggingVal = false, false, false end
	end))
	apply()
	return self
end

function ColorPicker.set(self: ColorPicker, color: Color3)
	self.h, self.s, self.v = color:ToHSV()
	self.preview.BackgroundColor3 = color
	self.satFill.Size = UDim2.new(self.s, 0, 1, 0)
	self.valFill.Size = UDim2.new(self.v, 0, 1, 0)
end

function ColorPicker.destroy(self: ColorPicker)
	for _, c in self.connections do c:Disconnect() end
	self.frame:Destroy()
end

return ColorPicker
