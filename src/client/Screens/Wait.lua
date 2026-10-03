--!strict
-- Shown to players with nothing to do. During a draw phase it becomes a live
-- gallery: one canvas per artist, updated stroke by stroke from the server.
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Canvas = require(UI.Canvas)
local Layout = require(UI.Layout)
local Responsive = require(UI.Responsive)
local AvatarStage = require(UI.AvatarStage)
local Players = game:GetService("Players")

local Wait = {}

function Wait.show(container: Frame, data: any, ctx: any)
	local artists = data and data.artists or {}
	if #artists == 0 then
		-- The party on stage, each popping in with a glow, under a short note.
		local stageHolder = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -80), Position = UDim2.fromOffset(0, 70), Parent = container })
		local stage = AvatarStage.new(stageHolder, { mode = "party" })
		local members = (ctx.partyMembers and ctx.partyMembers()) or {}
		local queued = 0
		for _, m in members do
			local p = Players:GetPlayerByUserId(m.userId)
			if p then
				queued += 1
				task.delay(0.35 * queued, function() if stageHolder.Parent then stage:addPlayer(p) end end)
			end
		end
		if queued == 0 then stage:addPlayer(Players.LocalPlayer) end
		local card = Make.card({
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 520, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			Make.list(nil, 4, Enum.HorizontalAlignment.Center), Parent = container,
		})
		Make.heading("THE PARTY", 22, { Font = Theme.fontDisplay, TextXAlignment = Enum.TextXAlignment.Center, Parent = card })
		Make.label(if data and data.phaseKind then "Others are busy with this phase. Your turn comes soon." else "Waiting for everyone...", 14, {
			TextColor3 = Theme.textDim, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = card,
		})
		return { collect = nil, destroy = function() stage:destroy() container:ClearAllChildren() end }
	end

	local root = Layout.form(container)
	local cols = if Responsive.isCompact() then 1 else math.min(3, #artists)
	local grid = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = root })
	local cellW = 1 / cols
	local cellH = if Responsive.isCompact() then Responsive.viewport().X - 32 else 300
	Make("UIGridLayout", {
		CellSize = UDim2.new(cellW, -10, 0, cellH + 50),
		CellPadding = UDim2.new(0, 10, 0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local rows = math.ceil(#artists / cols)
	grid.Size = UDim2.new(1, 0, 0, rows * (cellH + 60))

	-- state[artistId] = { strokes = { [panel] = {...} }, shown = panel, canvas, tabs }
	local state: { [number]: any } = {}
	for i, a in artists do
		local cell = Make("Frame", { BackgroundColor3 = Theme.panel, LayoutOrder = i, Make.corner(), Make.pad(8), Parent = grid })
		Make.heading(a.name, 14, { Size = UDim2.new(1, 0, 0, 18), Parent = cell })
		local tabs = Make.row(24, 4, { Position = UDim2.fromOffset(0, 20), Parent = cell })
		local holder = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -50), Position = UDim2.fromOffset(0, 50), Parent = cell })
		local c = Canvas.new(holder, false)
		local st = { strokes = {}, shown = 1, canvas = c, tabButtons = {} }
		state[a.userId] = st
		for p = 1, a.panels do
			st.strokes[p] = {}
			local b = Make.pill(tostring(p), p == 1, function()
				st.shown = p
				c:setStrokes(st.strokes[p])
				for q, tb in st.tabButtons do
					tb.BackgroundColor3 = if q == p then Theme.accent else Theme.panelAlt
					tb.TextColor3 = if q == p then Theme.bg else Theme.text
				end
			end, { Size = UDim2.fromOffset(28, 22), TextSize = 11, Parent = tabs })
			st.tabButtons[p] = b
		end
		if a.panels == 1 then tabs.Visible = false end
	end

	return {
		collect = nil,
		onLiveStroke = function(msg: any)
			local st = state[msg.artistId]
			if not st then return end
			local list = st.strokes[msg.panel]
			if not list then return end
			if msg.op == "add" and msg.stroke then
				table.insert(list, msg.stroke)
			elseif msg.op == "undo" then
				table.remove(list)
			elseif msg.op == "clear" then
				st.strokes[msg.panel] = {}
				list = st.strokes[msg.panel]
			elseif msg.op == "set" and msg.strokes then
				st.strokes[msg.panel] = msg.strokes
				list = st.strokes[msg.panel]
			end
			if st.shown == msg.panel then
				if msg.op == "add" then st.canvas:applyOp("add", msg.stroke) else st.canvas:setStrokes(list) end
			end
		end,
		destroy = function()
			for _, st in state do st.canvas:destroy() end
			container:ClearAllChildren()
		end,
	}
end

return Wait
