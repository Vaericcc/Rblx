--!strict
--[[
	One place that answers "what kind of screen is this?".
	compact  = phone-sized: stack panels vertically, bigger touch targets
	regular  = tablet landscape / desktop: side-by-side panels
]]
local UserInputService = game:GetService("UserInputService")

local Responsive = {}

local camera = workspace.CurrentCamera

function Responsive.viewport(): Vector2
	return camera.ViewportSize
end

function Responsive.isCompact(): boolean
	local v = camera.ViewportSize
	return v.X < 820 or v.Y < 480
end

function Responsive.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- UI scale so 720p layouts shrink gracefully on small screens.
function Responsive.scale(): number
	local v = camera.ViewportSize
	if Responsive.isCompact() then
		return 1 -- compact layouts are designed at native size
	end
	return math.clamp(v.Y / 760, 0.75, 1)
end

-- Minimum comfortable tap target height.
function Responsive.touchSize(): number
	return if Responsive.isTouch() then 48 else 40
end

Responsive.changed = camera:GetPropertyChangedSignal("ViewportSize")

return Responsive
