--!strict
--[[
	Plays back every story in sync with the server, one line at a time.
	The actor for the current line gets an on-air panel: mic toggle, level
	meter and a Next Line button. Everyone else sees who's speaking.
]]
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Canvas = require(UI.Canvas)
local Layout = require(UI.Layout)
local Mic = require(UI.Mic)

local Showcase = {}

function Showcase.show(container: Frame, data: any, ctx: any)
	ctx.hud:set("Showcase", "Sit back and watch. When your character speaks, you're on.", nil, false)
	local me = Players.LocalPlayer
	local main, side = Layout.split(container, { mainFraction = 0.6 })

	-- Stage
	local canvasArea = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -50), Parent = main })
	local canvas = Canvas.new(canvasArea, false)
	local bubbleLayer = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = canvas.frame })
	local captionLabel = Make.label("", 15, {
		Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 1, -44),
		TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.font, TextColor3 = Theme.textDim, Parent = main,
	})
	local titleCard = Make("Frame", {
		BackgroundColor3 = Theme.accent, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20,
		Make.corner(UDim.new(0, 10)), Make.pad(24), Make.list(nil, 10, Enum.HorizontalAlignment.Center),
		Parent = canvas.frame,
	})
	local titleKicker = Make.label("", 15, { TextColor3 = Theme.bg, TextXAlignment = Enum.TextXAlignment.Center, Parent = titleCard })
	local titleBig = Make.heading("", 36, { TextColor3 = Theme.bg, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = titleCard })
	local titleSub = Make.label("", 17, { TextColor3 = Theme.bg, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = titleCard })
	local titleCast = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 2, Enum.HorizontalAlignment.Center), Parent = titleCard })

	-- Side: story info
	local info = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 6), Parent = side })
	local progress = Make.label("", 12, { TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 16), Parent = info })
	local sideTitle = Make.heading("", 20, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = info })
	local sideMeta = Make.label("", 13, { TextColor3 = Theme.textDim, Parent = info })

	-- Side: who's speaking / on-air panel
	local onAir = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 8), Parent = side })
	local onAirHead = Make.heading("", 16, { RichText = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = onAir })
	local onAirLine = Make.label("", 18, { RichText = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = onAir })
	local timerBar = Make("Frame", { BackgroundColor3 = Theme.bg, Size = UDim2.new(1, 0, 0, 6), Make.corner(UDim.new(0.5, 0)), Parent = onAir })
	local timerFill = Make("Frame", { BackgroundColor3 = Theme.accent2, Size = UDim2.new(1, 0, 1, 0), Make.corner(UDim.new(0.5, 0)), Parent = timerBar })
	local mic: Mic.Mic? = nil
	local nextButton = Make.button("Done, next line  ▶", Theme.accent, function()
		Net.remote:FireServer(Net.C2S.ShowcaseNext)
	end, { Size = UDim2.new(1, 0, 0, 48), Visible = false, Parent = onAir })

	local castBox = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 4), Parent = side })

	local projects = data.projects
	local lineEndsAt: number? = nil
	local lineStarted = 0

	local function clearChildren(frame: Instance)
		for _, c in frame:GetChildren() do
			if c:IsA("GuiObject") then c:Destroy() end
		end
	end

	local function renderCast(project: any, into: Frame, dark: boolean)
		clearChildren(into)
		for _, c in project.cast do
			local role = project.roles and project.roles[c.name]
			local who = if role then ("  🎤 %s"):format(role.name) else ""
			Make.label(("<b>%s</b>  <font color=\"%s\">%s</font>%s"):format(c.name, if dark then "#5a4a10" else "#aaaabe", c.trait or "", who), 14, {
				RichText = true, TextColor3 = if dark then Theme.bg else Theme.text,
				TextXAlignment = if dark then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
				Size = UDim2.new(1, 0, 0, 20), Parent = into,
			})
		end
	end

	local function showBubble(line: any, slot: number, total: number, live: boolean)
		local bubble = Make("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, (slot - 1) / math.max(total, 1) * 0.6 + 0.04, 0),
			Size = UDim2.new(0.86, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 11,
			Make.corner(UDim.new(0, 14)), Make.pad(10),
			Make("UIStroke", { Color = if live then Theme.accent else Color3.new(0, 0, 0), Thickness = if live then 4 else 2 }),
			Make.label(("<b>%s:</b> %s%s"):format(line.character, line.text, if line.actorName then ("  <font color=\"#888888\" size=\"12\">🎤 %s</font>"):format(line.actorName) else ""), 16, {
				RichText = true, TextColor3 = Color3.new(0, 0, 0), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 12,
			}),
			Parent = bubbleLayer,
		})
		TweenService:Create(bubble, TweenInfo.new(0.25, Enum.EasingStyle.Back), { BackgroundTransparency = if live then 0 else 0.15 }):Play()
		return bubble
	end

	local function setOnAir(line: any?, endsAt: number?)
		if mic then mic:destroy() mic = nil end
		nextButton.Visible = false
		lineEndsAt = endsAt
		lineStarted = workspace:GetServerTimeNow()
		if not line then
			onAir.Visible = false
			return
		end
		onAir.Visible = true
		local isMe = line.actorId == me.UserId
		if isMe then
			onAirHead.Text = ("🔴 <font color=\"#ff5c5c\">YOU'RE ON</font> as <b>%s</b>"):format(line.character)
			onAirLine.Text = ("“%s”"):format(line.text)
			mic = Mic.new(onAir)
			mic:setMuted(false)
			nextButton.Visible = true
			nextButton.LayoutOrder = 100
		else
			onAirHead.Text = ("🎤 <b>%s</b> as %s"):format(line.actorName or "Narrator", line.character)
			onAirLine.Text = ("“%s”"):format(line.text)
		end
	end

	local function focus(projectIndex: number, frameIndex: number, lineIndex: number)
		local project = projects[projectIndex]
		local frame = project and project.frames[frameIndex]
		if not frame then return end
		progress.Text = ("STORY %d OF %d"):format(projectIndex, #projects)
		sideTitle.Text = project.premise and project.premise.title or "Untitled"
		sideMeta.Text = ("by %s"):format(project.ownerName)
		clearChildren(bubbleLayer)

		if frame.kind == "title" then
			titleCard.Visible = true
			canvas:setStrokes({})
			captionLabel.Text = ""
			titleKicker.Text = ("A story by %s"):format(project.ownerName)
			if frame.blind then
				titleBig.Text = "???"
				titleSub.Text = "The dubber never saw the premise. Let's see what they came up with."
				sideTitle.Text = "???"
				clearChildren(titleCast)
				clearChildren(castBox)
			else
				titleBig.Text = sideTitle.Text
				titleSub.Text = project.premise and project.premise.logline or ""
				renderCast(project, titleCast, true)
				renderCast(project, castBox, false)
			end
			setOnAir(nil, nil)
		elseif frame.kind == "panel" then
			titleCard.Visible = false
			local panel = project.panels[frame.panel]
			canvas:setStrokes(panel and panel.strokes or {})
			local cap = project.captions[tostring(frame.panel)]
			captionLabel.Text = if cap
				then ("“%s”  — %s"):format(cap.text, cap.authorName)
				else ("Panel %d · drawn by %s"):format(frame.panel, panel and panel.authorName or "?")
			local lines = frame.lines or {}
			for i = 1, math.min(lineIndex, #lines) do
				showBubble(lines[i], i, #lines, i == lineIndex)
			end
			setOnAir(lines[lineIndex], nil)
		elseif frame.kind == "reveal" then
			titleCard.Visible = true
			canvas:setStrokes({})
			titleKicker.Text = "THE REAL PREMISE WAS..."
			titleBig.Text = project.premise and project.premise.title or "Untitled"
			titleSub.Text = project.premise and project.premise.logline or ""
			renderCast(project, titleCast, true)
			renderCast(project, castBox, false)
			setOnAir(nil, nil)
		end
	end

	local heartbeat = RunService.Heartbeat:Connect(function()
		if lineEndsAt then
			local total = math.max(0.1, lineEndsAt - lineStarted)
			local left = math.clamp((lineEndsAt - workspace:GetServerTimeNow()) / total, 0, 1)
			timerFill.Size = UDim2.new(left, 0, 1, 0)
			timerBar.Visible = true
		else
			timerBar.Visible = false
		end
	end)

	if projects[1] then focus(1, 1, 0) end

	return {
		collect = nil,
		focus = function(projectIndex: number, frameIndex: number, lineIndex: number?, endsAt: number?)
			focus(projectIndex, frameIndex, lineIndex or 0)
			lineEndsAt = if (lineIndex or 0) > 0 then endsAt else nil
			lineStarted = workspace:GetServerTimeNow()
		end,
		destroy = function()
			heartbeat:Disconnect()
			if mic then mic:destroy() end
			canvas:destroy()
			container:ClearAllChildren()
		end,
	}
end

return Showcase
