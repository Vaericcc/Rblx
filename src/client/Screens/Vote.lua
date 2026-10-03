--!strict
--[[
	Awards vote in the Persona shop register, StoryDub palette: an ink
	backdrop with a chain-link lattice, a big slanted title, and for each
	award a tilted stack of cards you flick through and stamp a pick on.
]]
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Canvas = require(UI.Canvas)
local Responsive = require(UI.Responsive)

local Vote = {}

local function lattice(parent: Instance)
	-- two sets of thin diagonal lines = chain-link
	for _, rot in { 45, -45 } do
		for i = -12, 12 do
			Make("Frame", {
				BackgroundColor3 = Theme.cream, BackgroundTransparency = 0.9, BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, i * 70, 0.5, 0),
				Size = UDim2.new(0, 2, 2.2, 0), Rotation = rot, ZIndex = 1, Parent = parent,
			})
		end
	end
end

function Vote.show(container: Frame, data: any, ctx: any)
	ctx.hud:set("VOTE", "Stamp one pick per award. You can't pick your own.", data.endsAt, true)
	local compact = Responsive.isCompact()
	local root = Make("Frame", { BackgroundColor3 = Theme.ink, Size = UDim2.fromScale(1, 1), ClipsDescendants = true, Make.corner(), Parent = container })
	lattice(root)

	-- Big slanted title
	Make.label("WHADDYA\nPICK?", if compact then 34 else 56, {
		Font = Theme.fontDisplay, TextColor3 = Theme.cream, TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(24, 12), Size = UDim2.new(0, 320, 0, 130), Rotation = -6, ZIndex = 3, Parent = root,
	})
	Make.label("one stamp per award", 14, {
		Font = Theme.fontBody, TextColor3 = Theme.pop, Position = UDim2.fromOffset(28, 140), Size = UDim2.new(0, 300, 0, 20), Rotation = -6, ZIndex = 3, Parent = root,
	})

	local me = Players.LocalPlayer.DisplayName
	local ballot: { [string]: number } = {}
	local canvases = {}

	-- Award columns: each is a tilted stack; tap arrows to flip through, STAMP to pick
	local area = Make("ScrollingFrame", {
		BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, if compact then 170 else 150), Size = UDim2.new(1, 0, 1, if compact then -170 else -150),
		AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), ScrollBarThickness = 6, ScrollBarImageColor3 = Theme.cream,
		ScrollingDirection = Enum.ScrollingDirection.X, ZIndex = 2,
		Make.list(Enum.FillDirection.Horizontal, 18), Make("UIPadding", { PaddingLeft = UDim.new(0, 24), PaddingRight = UDim.new(0, 24), PaddingTop = UDim.new(0, 10) }),
		Parent = root,
	})
	local cardW = if compact then 230 else 260
	local cardH = if compact then 330 else 380

	for ai, award in data.awards do
		local col = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(cardW + 30, cardH + 90), LayoutOrder = ai, ZIndex = 2, Parent = area })
		-- Award tag (slanted ink label)
		Make.label(("%s %s"):format(award.emoji, award.name:upper()), 22, {
			Font = Theme.fontDisplay, TextColor3 = Theme.ink, BackgroundColor3 = Theme.accent, TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(0, cardW - 20, 0, 36), Position = UDim2.fromOffset(20, 0), Rotation = -3, ZIndex = 4,
			Make.corner(UDim.new(0, 4)), Make("UIStroke", { Color = Theme.ink, Thickness = 3 }), Parent = col,
		})
		local index = 1
		local stack = Make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 46), Size = UDim2.fromOffset(cardW, cardH), ZIndex = 3, Parent = col })
		-- back cards for the stacked look
		for b = 2, 1, -1 do
			Make("Frame", { BackgroundColor3 = Theme.creamDark, Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(b * 6, b * -6), Rotation = b * 2.5, ZIndex = 3, Make.corner(UDim.new(0, 6)), Make("UIStroke", { Color = Theme.ink, Thickness = 3 }), Parent = stack })
		end
		local card = Make("Frame", { BackgroundColor3 = Theme.cream, Size = UDim2.fromScale(1, 1), Rotation = -1.5, ZIndex = 4, Make.corner(UDim.new(0, 6)), Make.pad(12), Make("UIStroke", { Color = Theme.ink, Thickness = 3 }), Parent = stack })
		local thumbHolder = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, cardW - 24), ZIndex = 5, Parent = card })
		local thumb = Canvas.new(thumbHolder, false)
		table.insert(canvases, thumb)
		local title = Make.label("", 18, { Font = Theme.fontDisplay, TextColor3 = Theme.ink, Position = UDim2.new(0, 0, 0, cardW - 18), Size = UDim2.new(1, 0, 0, 24), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5, Parent = card })
		local credit = Make.label("", 12, { Font = Theme.fontBody, TextColor3 = Theme.ink, TextTransparency = 0.35, Position = UDim2.new(0, 0, 0, cardW + 6), Size = UDim2.new(1, 0, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5, Parent = card })
		local stamp = Make.label("PICKED", 30, {
			Font = Theme.fontDisplay, TextColor3 = Theme.pop, Rotation = -18, Visible = false, ZIndex = 6,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(170, 50), TextXAlignment = Enum.TextXAlignment.Center,
			Make("UIStroke", { Color = Theme.pop, Thickness = 3 }), Parent = card,
		})
		local stampBtn = Make.button("STAMP", Theme.pop, function() end, {
			Font = Theme.fontDisplay, TextSize = 20, TextColor3 = Theme.cream, Size = UDim2.new(1, 0, 0, 38), Position = UDim2.new(0, 0, 1, -38), ZIndex = 5,
			Make("UIStroke", { Color = Theme.ink, Thickness = 2.5 }), Parent = card,
		})

		local function show()
			local p = data.projects[index]
			if not p then return end
			thumb:setStrokes(p.thumbnail)
			title.Text = p.title
			credit.Text = if p.teamColor then p.ownerName else ("by %s"):format(p.ownerName)
			if p.actors and #p.actors > 0 then credit.Text ..= "  🎤 " .. table.concat(p.actors, ", ") end
			local mine = (data.mine and data.mine[tostring(p.index)]) or p.ownerName == me
			stamp.Visible = ballot[award.id] == p.index
			stampBtn.Text = if mine then "YOURS" elseif ballot[award.id] == p.index then "PICKED" else "STAMP"
			stampBtn.BackgroundColor3 = if mine then Theme.creamDark else Theme.pop
			stampBtn.TextColor3 = if mine then Theme.ink else Theme.cream
			stampBtn.Active = not mine
		end
		stampBtn.Activated:Connect(function()
			local p = data.projects[index]
			if not p then return end
			local mine = (data.mine and data.mine[tostring(p.index)]) or p.ownerName == me
			if mine then return end
			ballot[award.id] = p.index
			show()
			stamp.Size = UDim2.fromOffset(260, 80)
			TweenService:Create(stamp, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(170, 50) }):Play()
			ctx.markDirty()
		end)
		-- arrows
		local arrows = Make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, cardH + 52), Size = UDim2.fromOffset(cardW, 32), ZIndex = 4, Parent = col })
		local counter = Make.label("", 13, { Font = Theme.fontBody, TextColor3 = Theme.cream, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, -100, 1, 0), Position = UDim2.fromOffset(50, 0), ZIndex = 4, Parent = arrows })
		local function go(delta: number)
			local n = #data.projects
			index = ((index - 1 + delta) % n) + 1
			counter.Text = ("%d / %d"):format(index, n)
			show()
		end
		Make.button("<", Theme.cream, function() go(-1) end, { Font = Theme.fontDisplay, TextSize = 18, TextColor3 = Theme.ink, Size = UDim2.fromOffset(44, 32), ZIndex = 4, Parent = arrows })
		Make.button(">", Theme.cream, function() go(1) end, { Font = Theme.fontDisplay, TextSize = 18, TextColor3 = Theme.ink, Size = UDim2.fromOffset(44, 32), Position = UDim2.new(1, -44, 0, 0), ZIndex = 4, Parent = arrows })
		-- start each award on a different story so the wall isn't four identical cards
		index = ((ai - 1) % math.max(#data.projects, 1)) + 1
		counter.Text = ("%d / %d"):format(index, #data.projects)
		show()
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
