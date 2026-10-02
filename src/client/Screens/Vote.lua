--!strict
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Canvas = require(UI.Canvas)
local Layout = require(UI.Layout)
local Responsive = require(UI.Responsive)

local Vote = {}

function Vote.show(container: Frame, data: any, ctx: any)
	ctx.hud:set("Vote", "Hand out the awards. One pick per category; you can't pick your own.", data.endsAt, true)
	local root = Layout.form(container)
	local me = Players.LocalPlayer.DisplayName
	local ballot: { [string]: number } = {}
	local canvases = {}
	local cell = if Responsive.isCompact() then 104 else 124

	for _, award in data.awards do
		local buttons: { [number]: TextButton } = {}
		local row = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 8), Parent = root })
		Make.heading(("%s %s"):format(award.emoji, award.name), 18, { Parent = row })
		local strip = Make("ScrollingFrame", {
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, cell + 40),
			AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(),
			ScrollBarThickness = 4, ScrollingDirection = Enum.ScrollingDirection.X,
			Make.list(Enum.FillDirection.Horizontal, 10), Parent = row,
		})
		for _, p in data.projects do
			local mine = (data.mine and data.mine[tostring(p.index)]) or p.ownerName == me
			local tile = Make("Frame", { BackgroundColor3 = Theme.panelAlt, Size = UDim2.fromOffset(cell, cell + 40), Make.corner(UDim.new(0, 8)), Make.pad(6), Parent = strip })
			local thumb = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, cell - 36), Parent = tile })
			local c = Canvas.new(thumb, false)
			c:setStrokes(p.thumbnail)
			table.insert(canvases, c)
			Make.label(p.title, 12, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, cell - 32), TextTruncate = Enum.TextTruncate.AtEnd, Parent = tile })
			local credit = if p.teamColor then p.ownerName else "by " .. p.ownerName
			if p.actors and #p.actors > 0 then credit ..= "  🎤 " .. table.concat(p.actors, ", ") end
			Make.label(credit, 11, { TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, cell - 16), TextTruncate = Enum.TextTruncate.AtEnd, Parent = tile })
			local btn = Make.button(if mine then "yours" else "Pick", Theme.panel, function() end, {
				Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 1, -30), TextSize = 13, TextColor3 = if mine then Theme.textDim else Theme.text, Parent = tile,
			})
			buttons[p.index] = btn
			if not mine then
				btn.Activated:Connect(function()
					ballot[award.id] = p.index
					for idx, b in buttons do
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
			container:ClearAllChildren()
		end,
	}
end

return Vote
