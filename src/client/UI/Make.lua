--!strict
-- Tiny declarative Instance builder: Make("Frame", { props..., children })
local Theme = require(script.Parent.Theme)
local Responsive = require(script.Parent.Responsive)

local function Make(className: string, props: { [any]: any }): any
	local inst = Instance.new(className)
	local children = {}
	for key, value in props do
		if typeof(key) == "number" then
			table.insert(children, value)
		elseif key == "Parent" then
			-- set last
		else
			(inst :: any)[key] = value
		end
	end
	for _, child in children do
		-- UIStroke defaults to Contextual, which outlines the letters of a text
		-- object instead of its box and turns heavy fonts into scribbles.
		if child:IsA("UIStroke") and (inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")) then
			child.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		end
		child.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local M = {}
setmetatable(M, { __call = function(_, ...) return Make(...) end })

-- Merge caller props into defaults. Numeric keys are children: append, don't overwrite.
local function merge(defaults: { [any]: any }, props: { [any]: any }?): { [any]: any }
	if props then
		for k, v in props do
			if typeof(k) == "number" then
				table.insert(defaults, v)
			else
				defaults[k] = v
			end
		end
	end
	return defaults
end

function M.corner(radius: UDim?)
	return Make("UICorner", { CornerRadius = radius or Theme.radius })
end

function M.pad(all: number)
	return Make("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, all),
		PaddingRight = UDim.new(0, all),
	})
end

function M.list(direction: Enum.FillDirection?, padding: number?, align: Enum.HorizontalAlignment?)
	return Make("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
	})
end

function M.label(text: string, size: number, props: { [any]: any }?)
	local p = {
		Text = text,
		TextSize = size,
		Font = Theme.fontBody,
		TextColor3 = Theme.text,
		BackgroundTransparency = 1,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, size + 6),
	}
	merge(p, props)
	return Make("TextLabel", p)
end

function M.heading(text: string, size: number, props: { [any]: any }?)
	local p = merge({ Font = Theme.font }, props)
	return M.label(text, size, p)
end

function M.button(text: string, color: Color3, onClick: () -> (), props: { [any]: any }?)
	local p = {
		Text = text,
		TextSize = 18,
		Font = Theme.font,
		TextColor3 = if color == Theme.accent then Theme.bg else Theme.text,
		BackgroundColor3 = color,
		AutoButtonColor = true,
		Size = UDim2.new(0, 160, 0, Responsive.touchSize()),
		M.corner(),
	}
	merge(p, props)
	local b = Make("TextButton", p)
	b.Activated:Connect(onClick)
	return b
end

function M.input(placeholder: string, maxLen: number, props: { [any]: any }?)
	local p = {
		PlaceholderText = placeholder,
		PlaceholderColor3 = Theme.textDim,
		Text = "",
		TextSize = 18,
		Font = Theme.fontBody,
		TextColor3 = Theme.text,
		BackgroundColor3 = Theme.panelAlt,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, Responsive.touchSize()),
		M.corner(UDim.new(0, 8)),
		M.pad(10),
	}
	merge(p, props)
	local box = Make("TextBox", p)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if #box.Text > maxLen then
			box.Text = box.Text:sub(1, maxLen)
		end
	end)
	return box
end

function M.card(props: { [any]: any }?)
	local p = {
		BackgroundColor3 = Theme.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 100),
		M.corner(),
		M.pad(14),
	}
	merge(p, props)
	return Make("Frame", p)
end

function M.spacer(height: number, order: number?)
	return Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height), LayoutOrder = order or 0 })
end

-- Horizontal row that lays children out left to right.
function M.row(height: number, padding: number?, props: { [any]: any }?)
	local p = {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
		M.list(Enum.FillDirection.Horizontal, padding or 8),
	}
	merge(p, props)
	return Make("Frame", p)
end

-- Square icon button: image when the icon has an asset, short text otherwise.
function M.iconButton(iconName: string, size: number, color: Color3, onClick: () -> (), props: { [any]: any }?)
	local Icons = require(script.Parent.Icons)
	local p = {
		Size = UDim2.fromOffset(size, size),
		TextSize = if #Icons.label(iconName) > 3 then 11 else 15,
		Font = Theme.font,
		TextColor3 = Theme.text,
		Text = if Icons.has(iconName) then "" else Icons.label(iconName),
	}
	merge(p, props)
	local b = M.button(p.Text, color, onClick, p)
	if Icons.has(iconName) then
		Make("ImageLabel", {
			BackgroundTransparency = 1,
			Image = Icons.image(iconName),
			ImageColor3 = p.TextColor3,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.7, 0.7),
			ZIndex = b.ZIndex + 1,
			Parent = b,
		})
	end
	return b
end

-- Pill-style toggle button used for tabs and segmented choices.
function M.pill(text: string, selected: boolean, onClick: () -> (), props: { [any]: any }?)
	local p = {
		Size = UDim2.new(0, 110, 0, Responsive.touchSize() - 6),
		TextSize = 14,
		BackgroundColor3 = if selected then Theme.accent else Theme.panelAlt,
		TextColor3 = if selected then Theme.bg else Theme.text,
	}
	merge(p, props)
	return M.button(text, p.BackgroundColor3, onClick, p)
end

-- A full-screen frame normally starts below the Roblox top bar, leaving a strip
-- of world visible above it. This stretches it up under the bar and pads the
-- content back down, so backdrops cover everything and content stays clear.
function M.coverInset(frame: GuiObject, inset: number)
	frame.Position = UDim2.new(0, 0, 0, -inset)
	frame.Size = UDim2.new(1, 0, 1, inset)
	local pad = frame:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding", frame)
	pad.PaddingTop = UDim.new(0, inset)
end

return M
