--!strict
--[[
	Plays back every project, frame by frame, in sync with the server.
	Speech bubbles appear one at a time over the panel. In liveDub modes the
	dubber is called up so they can perform the lines over voice chat.
]]
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Canvas = require(UI.Canvas)
local Layout = require(UI.Layout)

local Showcase = {}

function Showcase.show(container: Frame, data: any, ctx: any)
	ctx.hud:set("Showcase", "Sit back. Dubbers, get ready to perform.", nil, false)
	local main, side = Layout.split(container, { mainFraction = 0.62 })

	local canvasArea = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -56), Parent = main })
	local canvas = Canvas.new(canvasArea, false)
	local bubbleLayer = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = canvas.frame })
	local captionLabel = Make.label("", 16, {
		Size = UDim2.new(1, 0, 0, 50), Position = UDim2.new(0, 0, 1, -50),
		TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.font, Parent = main,
	})

	local titleCard = Make("Frame", {
		BackgroundColor3 = Theme.accent, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20,
		Make.corner(UDim.new(0, 10)), Make.pad(24), Make.list(nil, 10, Enum.HorizontalAlignment.Center),
		Parent = canvas.frame,
	})
	local titleKicker = Make.label("", 15, { TextColor3 = Theme.bg, TextXAlignment = Enum.TextXAlignment.Center, Parent = titleCard })
	local titleBig = Make.heading("", 36, { TextColor3 = Theme.bg, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = titleCard })
	local titleSub = Make.label("", 17, { TextColor3 = Theme.bg, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = titleCard })

	local info = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 8), Parent = side })
	local progress = Make.label("", 12, { TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 16), Parent = info })
	local sideTitle = Make.heading("", 22, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = info })
	local sideMeta = Make.label("", 14, { TextColor3 = Theme.textDim, Parent = info })
	local nowDubbing = Make.label("", 15, { TextColor3 = Theme.accent, RichText = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = info })
	local castBox = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 4), Parent = info })

	local projects = data.projects
	local bubbleThreads: { thread } = {}

	local function clearBubbles()
		for _, t in bubbleThreads do task.cancel(t) end
		bubbleThreads = {}
		bubbleLayer:ClearAllChildren()
	end

	local function showBubble(line: any, slot: number, total: number)
		local bubble = Make("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, (slot - 1) / math.max(total, 1) * 0.6 + 0.04, 0),
			Size = UDim2.new(0.86, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 11,
			Make.corner(UDim.new(0, 14)), Make.pad(10),
			Make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2 }),
			Make.label(("<b>%s:</b> %s"):format(line.character, line.text), 16, {
				RichText = true, TextColor3 = Color3.new(0, 0, 0), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 12,
			}),
			Parent = bubbleLayer,
		})
		TweenService:Create(bubble, TweenInfo.new(0.25, Enum.EasingStyle.Back), { BackgroundTransparency = 0 }):Play()
	end

	local function renderCast(project: any)
		for _, c in castBox:GetChildren() do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		for _, c in project.cast do
			Make.label(("<b>%s</b>  <font color=\"#aaaabe\">%s</font>"):format(c.name, c.trait or ""), 14, { RichText = true, Size = UDim2.new(1, 0, 0, 20), Parent = castBox })
		end
	end

	local function linesFor(project: any, panelIndex: number)
		local lines = {}
		for _, l in project.lines do
			if l.panel == panelIndex and l.source == "dub" then table.insert(lines, l) end
		end
		if #lines == 0 then
			for _, l in project.lines do
				if l.panel == panelIndex then table.insert(lines, l) end
			end
		end
		return lines
	end

	local function focus(projectIndex: number, frameIndex: number)
		local project = projects[projectIndex]
		local frame = project and project.frames[frameIndex]
		if not frame then return end
		clearBubbles()
		progress.Text = ("STORY %d OF %d"):format(projectIndex, #projects)
		sideTitle.Text = project.premise and project.premise.title or "Untitled"
		sideMeta.Text = ("by %s"):format(project.ownerName)
		local me = Players.LocalPlayer.DisplayName
		if data.liveDub and project.dubberName then
			nowDubbing.Text = if project.dubberName == me
				then "🎤 <b>You're the dubber.</b> Unmute and perform your lines!"
				else ("🎤 Dubbed by <b>%s</b>"):format(project.dubberName)
		else
			nowDubbing.Text = ""
		end

		if frame.kind == "title" then
			titleCard.Visible = true
			canvas:setStrokes({})
			captionLabel.Text = ""
			titleKicker.Text = ("A story by %s"):format(project.ownerName)
			if frame.blind then
				titleBig.Text = "???"
				titleSub.Text = "The dubber never saw the premise. Let's see what they came up with."
				sideTitle.Text = "???"
				renderCast({ cast = {} })
			else
				titleBig.Text = sideTitle.Text
				titleSub.Text = project.premise and project.premise.logline or ""
				renderCast(project)
			end
		elseif frame.kind == "panel" then
			titleCard.Visible = false
			local panel = project.panels[frame.panel]
			canvas:setStrokes(panel and panel.strokes or {})
			local cap = project.captions[tostring(frame.panel)]
			captionLabel.Text = if cap
				then ("“%s”  — %s"):format(cap.text, cap.authorName)
				else ("Panel %d · drawn by %s"):format(frame.panel, panel and panel.authorName or "?")
			local lines = linesFor(project, frame.panel)
			local perLine = (frame.seconds - 1) / math.max(#lines, 1)
			for i, line in lines do
				table.insert(bubbleThreads, task.delay((i - 1) * perLine + 0.4, showBubble, line, i, #lines))
			end
		elseif frame.kind == "reveal" then
			titleCard.Visible = true
			canvas:setStrokes({})
			titleKicker.Text = "THE REAL PREMISE WAS..."
			titleBig.Text = project.premise and project.premise.title or "Untitled"
			titleSub.Text = project.premise and project.premise.logline or ""
			renderCast(project)
		end
	end

	if projects[1] then focus(1, 1) end

	return {
		collect = nil,
		focus = focus,
		destroy = function() clearBubbles() canvas:destroy() container:ClearAllChildren() end,
	}
end

return Showcase
