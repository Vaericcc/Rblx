--!strict
--[[
	Layout.split(container, opts) -> main, side
	Regular screens: main and side sit side by side (main gets `mainFraction`).
	Compact screens: main sits on top at `compactMainHeight` px, side scrolls below.
	Both frames always exist so screens never branch on screen size themselves.
]]
local Make = require(script.Parent.Make)
local Responsive = require(script.Parent.Responsive)

local Layout = {}

export type SplitOpts = {
	mainFraction: number?,
	compactMainHeight: number?,
	sideScrolls: boolean?,
	gap: number?,
}

local function scroller(parent: Instance, size: UDim2, position: UDim2?): ScrollingFrame
	return Make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = size,
		Position = position or UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 6,
		ScrollBarImageTransparency = 0.4,
		Make.list(nil, 10),
		Make("UIPadding", { PaddingRight = UDim.new(0, 12) }),
		Parent = parent,
	})
end

function Layout.split(container: Instance, opts: SplitOpts?): (Frame, GuiObject)
	local o = opts or {}
	local gap = o.gap or 12
	local mainFraction = o.mainFraction or 0.6
	if Responsive.isCompact() then
		local wrapper = scroller(container, UDim2.fromScale(1, 1))
		local v = Responsive.viewport()
		local mainH = o.compactMainHeight or math.min(v.X - 32, math.floor(v.Y * 0.5))
		local main = Make("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, mainH),
			LayoutOrder = 1,
			Parent = wrapper,
		})
		local side = Make("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Make.list(nil, 10),
			Parent = wrapper,
		})
		return main, side
	else
		local main = Make("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(mainFraction, -gap / 2, 1, 0),
			Parent = container,
		})
		local side: GuiObject
		if o.sideScrolls ~= false then
			side = scroller(container, UDim2.new(1 - mainFraction, -gap / 2, 1, 0), UDim2.new(mainFraction, gap / 2, 0, 0))
		else
			side = Make("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1 - mainFraction, -gap / 2, 1, 0),
				Position = UDim2.new(mainFraction, gap / 2, 0, 0),
				Make.list(nil, 10),
				Parent = container,
			})
		end
		return main, side
	end
end

-- A vertical scrolling form that fills its parent.
function Layout.form(parent: Instance): ScrollingFrame
	return scroller(parent, UDim2.fromScale(1, 1))
end

return Layout
