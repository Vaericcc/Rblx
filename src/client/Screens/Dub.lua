--!strict
--[[
	Dub phase. data.projects is a list of stories you have lines in.
		Role-based (most modes): each story carries myRoles; you write only for those.
		Blind dub: one story, no cast shown, you invent the speakers.
	Stories are tabs across the top; panels are tabs under the picture.
]]
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Canvas = require(UI.Canvas)
local Layout = require(UI.Layout)
local StoryInfo = require(UI.StoryInfo)
local TextPhases = require(script.Parent.TextPhases)

local Dub = {}

function Dub.show(container: Frame, data: any, ctx: any)
	local projects = data.projects or {}
	local main, side = Layout.split(container, { mainFraction = 0.5 })

	local storyTabs = Make.row(36, 6, { Parent = main })
	local panelTabs = Make.row(32, 6, { Position = UDim2.fromOffset(0, 42), Parent = main })
	local canvasArea = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -82), Position = UDim2.fromOffset(0, 82), Parent = main })
	local canvas = Canvas.new(canvasArea, false)

	-- editors[storyIndex][panelIndex]
	local editors: { { any } } = {}
	local sideGroups: { Frame } = {}
	local storyButtons: { TextButton } = {}
	local panelButtons: { TextButton } = {}
	local currentStory, currentPanel = 1, 1

	local function paintTabs(buttons: { TextButton }, active: number)
		for i, b in buttons do
			b.BackgroundColor3 = if i == active then Theme.accent else Theme.panelAlt
			b.TextColor3 = if i == active then Theme.bg else Theme.text
		end
	end

	local function selectPanel(i: number)
		currentPanel = i
		local project = projects[currentStory]
		canvas:setStrokes(project.panels[i] and project.panels[i].strokes or {})
		paintTabs(panelButtons, i)
		for j, e in editors[currentStory] do
			(e.frame :: Frame).BackgroundColor3 = if j == i then Theme.panelAlt else Theme.panel
		end
	end

	local function selectStory(s: number)
		currentStory = s
		paintTabs(storyButtons, s)
		for i, group in sideGroups do group.Visible = (i == s) end
		for _, b in panelButtons do b:Destroy() end
		panelButtons = {}
		for i = 1, #projects[s].panels do
			panelButtons[i] = Make.pill(("Panel %d"):format(i), false, function() selectPanel(i) end, { Size = UDim2.new(0, 84, 1, 0), TextSize = 13, Parent = panelTabs })
		end
		selectPanel(1)
	end

	for s, project in projects do
		storyButtons[s] = Make.pill(project.premise and project.premise.title or ("Story %d"):format(s), false, function() selectStory(s) end, {
			Size = UDim2.new(0, 140, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = storyTabs,
		})
		local group = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, Make.list(nil, 10), Parent = side })
		sideGroups[s] = group

		local speakers: { string }
		if data.blind then
			speakers = {}
			local note = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = group })
			Make.label("🙈 BLIND DUB. You don't get the premise or the cast. Name the characters yourself and make it up.", 14, {
				TextColor3 = Theme.accent, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = note,
			})
		else
			speakers = project.myRoles or {}
			local who = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 4), Parent = group })
			Make.label(("🎤 You voice <b>%s</b>"):format(table.concat(speakers, "</b> and <b>")), 15, {
				RichText = true, TextColor3 = Theme.accent, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = who,
			})
			Make.label("Write a line for each panel where your character has something to say. Leave a panel blank to stay quiet.", 13, {
				TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = who,
			})
			local info = StoryInfo.build(group, { premise = project.premise, cast = project.cast, roles = project.roles, ownerName = project.ownerName })
			info.Size = UDim2.new(1, 0, 0, 0)
			info.AutomaticSize = Enum.AutomaticSize.Y
		end

		editors[s] = {}
		for i = 1, #project.panels do
			local editor = TextPhases.lineEditor(group, i, speakers, ctx, 2)
			editors[s][i] = editor
			local hit = Make("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(-14, -14), Parent = editor.frame })
			hit.Activated:Connect(function()
				if currentStory ~= s then selectStory(s) end
				selectPanel(i)
			end)
		end
	end
	if #projects > 0 then selectStory(1) end
	storyTabs.Visible = #projects > 1

	return {
		collect = function()
			local out = {}
			for s, project in projects do
				for _, e in editors[s] do
					for _, l in e.collect() do
						l.projectIndex = project.index
						table.insert(out, l)
					end
				end
			end
			return out
		end,
		destroy = function() canvas:destroy() container:ClearAllChildren() end,
	}
end

return Dub
