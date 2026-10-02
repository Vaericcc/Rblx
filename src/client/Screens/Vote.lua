--!strict
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Canvas = require(UI.Canvas)

local Vote = {}

function Vote.show(container: Frame, data: any, ctx: any)
	ctx.hud:set("Vote", "Hand out the awards. One pick per category, and you can't pick your own.", data.endsAt, true)
	local root = Make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 6,
		Make.list(nil, 12),
		Parent = container,
	})
	local me = Players.LocalPlayer.DisplayName
	local ballot: { [string]: number } = {}
	local canvases = {}
	local buttonsByAward: { [string]: { [number]: TextButton } } = {}

	for _, award in data.awards do
		buttonsByAward[award.id] = {}
		local row = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 8), Parent = root })
		Make.heading(("%s %s"):format(award.emoji, award.name), 20, { Parent = row })
		local strip = Make("ScrollingFrame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 160),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 4,
			ScrollingDirection = Enum.ScrollingDirection.X,
			Make.list(Enum.FillDirection.Horizontal, 10),
			Parent = row,
		})
		for _, p in data.projects do
			local mine = p.ownerName == me
			local cell = Make("Frame", { BackgroundColor3 = Theme.panelAlt, Size = UDim2.fromOffset(120, 150), Make.corner(UDim.new(0, 8)), Make.pad(6), Parent = strip })
			local thumbHolder = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 90), Parent = cell })
			local c = Canvas.new(thumbHolder, false)
			c:setStrokes(p.thumbnail)
			table.insert(canvases, c)
			Make.label(p.title, 12, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 94), TextTruncate = Enum.TextTruncate.AtEnd, Parent = cell })
			local btn = Make.button(if mine then "yours" else "Pick", Theme.panel, function() end, {
				Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 1, -26), TextSize = 13, TextColor3 = Theme.text,
			})
			btn.Parent = cell
			buttonsByAward[award.id][p.index] = btn
			if not mine then
				btn.Activated:Connect(function()
					ballot[award.id] = p.index
					for idx, b in buttonsByAward[award.id] do
						b.BackgroundColor3 = if idx == p.index then Theme.accent else Theme.panel
						b.TextColor3 = if idx == p.index then Theme.bg else Theme.text
					end
					ctx.markDirty()
				end)
			end
		end
	end

	return {
		collect = function() return ballot end,
		submitAction = Net.C2S.Vote,
		destroy = function()
			for _, c in canvases do c:destroy() end
			root:Destroy()
		end,
	}
end

return Vote
