--!strict
-- Shown to players who have nothing to do in the current phase.
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)

local Wait = {}

function Wait.show(container: Frame, data: any, ctx: any)
	local card = Make.card({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.new(0, 420, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Make.list(nil, 8, Enum.HorizontalAlignment.Center),
		Parent = container,
	})
	Make.heading("☕", 40, { TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 50), Parent = card })
	Make.label("Nothing for you this phase. The showcase starts as soon as everyone's lines are in.", 15, {
		TextColor3 = Theme.textDim, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = card,
	})
	return { collect = nil, destroy = function() container:ClearAllChildren() end }
end

return Wait
