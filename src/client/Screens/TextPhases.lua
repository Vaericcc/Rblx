--!strict
-- Premise, Cast, Script and Caption screens. All are forms; `collect` returns the data to submit.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Layout = require(UI.Layout)
local Canvas = require(UI.Canvas)
local StoryInfo = require(UI.StoryInfo)
local Responsive = require(UI.Responsive)

local TextPhases = {}

local function watch(box: TextBox, ctx: any)
	box:GetPropertyChangedSignal("Text"):Connect(function() ctx.markDirty() end)
end

local function infoCard(parent: Instance, opts: any)
	local card = StoryInfo.build(parent, opts)
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	return card
end

----------------------------------------------------------------------------
function TextPhases.premise(container: Frame, data: any, ctx: any)
	local f = Layout.form(container)
	local card = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 10), Parent = f })
	Make.heading("Title", 15, { TextColor3 = Theme.accent, Parent = card })
	local title = Make.input("e.g. The Last Slice", Config.MAX_TITLE_LEN, { Parent = card })
	Make.heading("Premise", 15, { TextColor3 = Theme.accent, Parent = card })
	local logline = Make.input("One sentence. Who wants what, and what's in the way?", Config.MAX_LOGLINE_LEN, {
		Size = UDim2.new(1, 0, 0, 96),
		TextYAlignment = Enum.TextYAlignment.Top,
		MultiLine = true,
		Parent = card,
	})
	watch(title, ctx)
	watch(logline, ctx)
	Make.label("A strong premise gives your artist something to draw and your dubber something to say.", 13, {
		TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 36), Parent = f,
	})
	return {
		collect = function() return { title = title.Text, logline = logline.Text } end,
		destroy = function() f:Destroy() end,
	}
end

----------------------------------------------------------------------------
function TextPhases.cast(container: Frame, data: any, ctx: any)
	local f: GuiObject
	if Responsive.isCompact() then
		f = Layout.form(container)
		infoCard(f, { premise = data.premise })
	else
		local main, side = Layout.split(container, { mainFraction = 0.6 })
		f = Layout.form(main)
		infoCard(side, { premise = data.premise })
	end
	local boxes = {}
	for i = 1, data.count do
		local card = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 8), Parent = f })
		Make.heading(("Character %d"):format(i), 14, { TextColor3 = Theme.accent, Parent = card })
		local name = Make.input("Name", Config.MAX_CHAR_NAME_LEN, { Parent = card })
		local trait = Make.input("Defining trait (e.g. terrified of pigeons)", Config.MAX_CHAR_TRAIT_LEN, { Parent = card })
		watch(name, ctx)
		watch(trait, ctx)
		boxes[i] = { name = name, trait = trait }
	end
	return {
		collect = function()
			local out = {}
			for _, b in boxes do table.insert(out, { name = b.name.Text, trait = b.trait.Text }) end
			return out
		end,
		destroy = function() container:ClearAllChildren() end,
	}
end

----------------------------------------------------------------------------
-- "Who says what" rows for one panel. Used by Script and Dub.
-- castNames may be empty (blind dub): then the speaker is free text.
function TextPhases.lineEditor(parent: Instance, panelIndex: number, castNames: { string }, ctx: any, maxLines: number)
	local card = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 6), Parent = parent })
	local title = Make.heading(("Panel %d"):format(panelIndex), 14, { TextColor3 = Theme.accent, Parent = card })
	local rows = {}
	local h = Responsive.touchSize()

	local function addRow()
		if #rows >= maxLines then return end
		local row = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, h), LayoutOrder = #rows + 1, Parent = card })
		local who: any
		if #castNames > 0 then
			local idx = ((#rows) % #castNames) + 1
			local btn = Make.button(castNames[idx], Theme.panelAlt, function() end, {
				Size = UDim2.new(0.32, -6, 1, 0), TextSize = 13, TextColor3 = Theme.text, TextTruncate = Enum.TextTruncate.AtEnd,
			})
			btn.Activated:Connect(function()
				idx = (idx % #castNames) + 1
				btn.Text = castNames[idx]
				ctx.markDirty()
			end)
			btn.Parent = row
			who = btn
		else
			who = Make.input("Who?", Config.MAX_CHAR_NAME_LEN, { Size = UDim2.new(0.32, -6, 1, 0), TextSize = 14, Parent = row })
			watch(who, ctx)
		end
		local text = Make.input("Says...", Config.MAX_LINE_LEN, {
			Size = UDim2.new(0.68, 0, 1, 0), Position = UDim2.new(0.32, 0, 0, 0), TextSize = 15, Parent = row,
		})
		watch(text, ctx)
		table.insert(rows, { who = who, text = text })
	end

	addRow()
	Make.button("+ line", Theme.panelAlt, addRow, { Size = UDim2.new(0, 90, 0, 32), TextSize = 13, TextColor3 = Theme.text, LayoutOrder = 999, Parent = card })

	return {
		frame = card,
		title = title,
		collect = function()
			local out = {}
			for _, r in rows do
				if r.text.Text ~= "" then
					table.insert(out, { panel = panelIndex, character = r.who.Text, text = r.text.Text })
				end
			end
			return out
		end,
	}
end

function TextPhases.script(container: Frame, data: any, ctx: any)
	local castNames = {}
	for _, c in data.cast do table.insert(castNames, c.name) end
	local editors = {}
	local f: GuiObject
	if Responsive.isCompact() then
		f = Layout.form(container)
		infoCard(f, { premise = data.premise, cast = data.cast, roles = data.roles })
	else
		local main, side = Layout.split(container, { mainFraction = 0.6 })
		f = Layout.form(main)
		infoCard(side, { premise = data.premise, cast = data.cast, roles = data.roles })
	end
	for i = 1, data.panels do
		editors[i] = TextPhases.lineEditor(f, i, castNames, ctx, 3)
	end
	return {
		collect = function()
			local out = {}
			for _, e in editors do
				for _, l in e.collect() do table.insert(out, l) end
			end
			return out
		end,
		destroy = function() container:ClearAllChildren() end,
	}
end

----------------------------------------------------------------------------
-- Co-op: the director writes one scene per panel (one panel per player).
function TextPhases.scenes(container: Frame, data: any, ctx: any)
	local f: GuiObject
	if Responsive.isCompact() then
		f = Layout.form(container)
		infoCard(f, { premise = data.premise, cast = data.cast })
	else
		local main, side = Layout.split(container, { mainFraction = 0.6 })
		f = Layout.form(main)
		infoCard(side, { premise = data.premise, cast = data.cast })
	end
	Make.label(("You're directing. Describe what happens in each of the %d panels. A different player draws each one."):format(data.count), 14, {
		TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = f,
	})
	local boxes = {}
	for i = 1, data.count do
		local card = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 6), Parent = f })
		Make.heading(("Panel %d"):format(i), 14, { TextColor3 = Theme.accent, Parent = card })
		local box = Make.input("What happens here? Who's in it?", Config.MAX_LOGLINE_LEN, { Size = UDim2.new(1, 0, 0, 64), MultiLine = true, TextYAlignment = Enum.TextYAlignment.Top, Parent = card })
		watch(box, ctx)
		boxes[i] = box
	end
	return {
		collect = function()
			local out = {}
			for i, b in boxes do out[i] = b.Text end
			return out
		end,
		destroy = function() container:ClearAllChildren() end,
	}
end

----------------------------------------------------------------------------
function TextPhases.caption(container: Frame, data: any, ctx: any)
	local main, side = Layout.split(container, { mainFraction = 0.55 })
	local canvas = Canvas.new(main, false)
	canvas:setStrokes(data.panel and data.panel.strokes or {})
	local card = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 8), Parent = side })
	Make.heading("What is happening here?", 16, { TextColor3 = Theme.accent, Parent = card })
	local box = Make.input("Describe it in one sentence...", Config.MAX_CAPTION_LEN, {
		Size = UDim2.new(1, 0, 0, 96), MultiLine = true, TextYAlignment = Enum.TextYAlignment.Top, Parent = card,
	})
	watch(box, ctx)
	Make.label("Drawn by " .. (data.panel and data.panel.authorName or "?"), 13, { TextColor3 = Theme.textDim, Parent = card })
	return {
		collect = function() return { text = box.Text } end,
		destroy = function() canvas:destroy() container:ClearAllChildren() end,
	}
end

return TextPhases
