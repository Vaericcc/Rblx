--!strict
-- Premise, Cast, Script and Caption screens. All are forms; `collect` returns the data to submit.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Canvas = require(UI.Canvas)
local StoryInfo = require(UI.StoryInfo)

local TextPhases = {}

local function twoColumn(container: Frame): (Frame, Frame)
	local left = Make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.6, -8, 1, 0),
		Parent = container,
	})
	local right = Make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.4, -8, 1, 0),
		Position = UDim2.new(0.6, 8, 0, 0),
		Parent = container,
	})
	return left, right
end

local function form(parent: Instance): Frame
	return Make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 6,
		Make.list(nil, 10),
		Parent = parent,
	})
end

local function watch(box: TextBox, ctx: any)
	box:GetPropertyChangedSignal("Text"):Connect(function() ctx.markDirty() end)
end

----------------------------------------------------------------------------
function TextPhases.premise(container: Frame, data: any, ctx: any)
	local f = form(container)
	local card = Make.card({ Size = UDim2.new(1, 0, 0, 260), Make.list(nil, 10), Parent = f })
	Make.heading("Title", 16, { TextColor3 = Theme.accent, Parent = card })
	local title = Make.input("e.g. The Last Slice", Config.MAX_TITLE_LEN, { Parent = card })
	Make.heading("Premise", 16, { TextColor3 = Theme.accent, Parent = card })
	local logline = Make.input("One sentence. Who wants what, and what's in the way?", Config.MAX_LOGLINE_LEN, {
		Size = UDim2.new(1, 0, 0, 90),
		TextYAlignment = Enum.TextYAlignment.Top,
		MultiLine = true,
		Parent = card,
	})
	watch(title, ctx)
	watch(logline, ctx)
	Make.label("Tip: a strong premise gives your artist something to draw AND your dubber something to say.", 13, { TextColor3 = Theme.textDim, Parent = f })
	return {
		collect = function() return { title = title.Text, logline = logline.Text } end,
		destroy = function() f:Destroy() end,
	}
end

----------------------------------------------------------------------------
function TextPhases.cast(container: Frame, data: any, ctx: any)
	local left, right = twoColumn(container)
	local f = form(left)
	local boxes = {}
	for i = 1, data.count do
		local card = Make.card({ Size = UDim2.new(1, 0, 0, 130), Make.list(nil, 8), Parent = f })
		Make.heading(("Character %d"):format(i), 14, { TextColor3 = Theme.accent, Parent = card })
		local name = Make.input("Name", Config.MAX_CHAR_NAME_LEN, { Parent = card })
		local trait = Make.input("Defining trait (e.g. terrified of pigeons)", Config.MAX_CHAR_TRAIT_LEN, { Parent = card })
		watch(name, ctx)
		watch(trait, ctx)
		boxes[i] = { name = name, trait = trait }
	end
	StoryInfo.build(right, { premise = data.premise })
	return {
		collect = function()
			local out = {}
			for _, b in boxes do
				table.insert(out, { name = b.name.Text, trait = b.trait.Text })
			end
			return out
		end,
		destroy = function() left:Destroy() right:Destroy() end,
	}
end

----------------------------------------------------------------------------
-- A reusable "who says what" row list used by Script and Dub.
-- Returns {frame, collect} ; castNames may be empty (blind dub) -> free text.
function TextPhases.lineEditor(parent: Instance, panelIndex: number, castNames: { string }, ctx: any, maxLines: number)
	local card = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 6), Parent = parent })
	Make.heading(("Panel %d"):format(panelIndex), 14, { TextColor3 = Theme.accent, Parent = card })
	local rows = {}

	local function addRow()
		if #rows >= maxLines then return end
		local row = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = card })
		local who: TextBox
		if #castNames > 0 then
			-- cycle button through the cast
			local idx = ((#rows) % #castNames) + 1
			local btn = Make.button(castNames[idx], Theme.panelAlt, function() end, {
				Size = UDim2.new(0.3, -6, 1, 0),
				TextSize = 14,
				TextColor3 = Theme.text,
			})
			btn.Activated:Connect(function()
				idx = (idx % #castNames) + 1
				btn.Text = castNames[idx]
				ctx.markDirty()
			end)
			btn.Parent = row
			who = btn :: any
		else
			who = Make.input("Who?", Config.MAX_CHAR_NAME_LEN, { Size = UDim2.new(0.3, -6, 1, 0), TextSize = 14, Parent = row })
			watch(who, ctx)
		end
		local text = Make.input("Says...", Config.MAX_LINE_LEN, {
			Size = UDim2.new(0.7, 0, 1, 0),
			Position = UDim2.new(0.3, 0, 0, 0),
			TextSize = 15,
			Parent = row,
		})
		watch(text, ctx)
		table.insert(rows, { who = who, text = text })
	end

	addRow()
	local addBtn = Make.button("+ line", Theme.panelAlt, addRow, { Size = UDim2.new(0, 90, 0, 30), TextSize = 13, TextColor3 = Theme.text, LayoutOrder = 999 })
	addBtn.Parent = card

	return {
		frame = card,
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
	local left, right = twoColumn(container)
	local f = form(left)
	local castNames = {}
	for _, c in data.cast do table.insert(castNames, c.name) end
	local editors = {}
	for i = 1, data.panels do
		editors[i] = TextPhases.lineEditor(f, i, castNames, ctx, 3)
	end
	StoryInfo.build(right, { premise = data.premise, cast = data.cast })
	return {
		collect = function()
			local out = {}
			for _, e in editors do
				for _, l in e.collect() do table.insert(out, l) end
			end
			return out
		end,
		destroy = function() left:Destroy() right:Destroy() end,
	}
end

----------------------------------------------------------------------------
function TextPhases.caption(container: Frame, data: any, ctx: any)
	local left, right = twoColumn(container)
	local canvasHolder = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = left })
	local canvas = Canvas.new(canvasHolder, false)
	canvas:setStrokes(data.panel and data.panel.strokes or {})
	local card = Make.card({ Size = UDim2.new(1, 0, 0, 200), Make.list(nil, 8), Parent = right })
	Make.heading("What is happening here?", 16, { TextColor3 = Theme.accent, Parent = card })
	local box = Make.input("Describe it in one sentence...", Config.MAX_CAPTION_LEN, {
		Size = UDim2.new(1, 0, 0, 100),
		MultiLine = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	watch(box, ctx)
	Make.label("Drawn by " .. (data.panel and data.panel.authorName or "?"), 13, { TextColor3 = Theme.textDim, Parent = card })
	return {
		collect = function() return { text = box.Text } end,
		destroy = function() canvas:destroy() left:Destroy() right:Destroy() end,
	}
end

return TextPhases
