--!strict
--[[
	Hub UI, drawn like a comic page: cream paper, heavy ink borders, a pop
	colour for emphasis. The 3D world stays visible and walkable; this draws:
		- a top-left bar with the logo, your points and a Play button
		- the matchmaking panel (Join / Create / Your Room tabs)
		- a bottom banner when you're standing on a platform
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Responsive = require(UI.Responsive)
local ModeGrid = require(UI.ModeGrid)

local Lobby = {}
Lobby.__index = Lobby

export type Lobby = typeof(setmetatable({} :: {
	root: Frame,
	bar: Frame,
	pointsLabel: TextLabel,
	panel: Frame,
	panelBody: Frame,
	tabs: Frame,
	banner: Frame,
	bannerText: TextLabel,
	init: any,
	rooms: { any },
	room: any,
	pad: any,
	points: number,
	tab: string,
	visibility: string,
	open: boolean,
	heartbeat: RBXScriptConnection?,
}, Lobby))

local function send(action: string, data: any?)
	Net.remote:FireServer(action, data)
end

----------------------------------------------------------------------------
-- Comic-styled primitives

-- A "panel": cream card with a thick ink border.
local function inkPanel(props: { [any]: any }): Frame
	local p = {
		BackgroundColor3 = Theme.cream,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Make.corner(UDim.new(0, 6)),
		Make.pad(14),
		Make.list(nil, 6),
		Make("UIStroke", { Color = Theme.ink, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	}
	for k, v in props do p[k] = v end
	local panel = Make("Frame", p)
	return panel
end

local function inkText(text: string, size: number, props: { [any]: any }?)
	local p = { TextColor3 = Theme.ink, Font = Theme.fontBody, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }
	if props then for k, v in props do p[k] = v end end
	return Make.label(text, size, p)
end

local function inkHeading(text: string, size: number, props: { [any]: any }?)
	local p = { TextColor3 = Theme.ink, Font = Theme.fontDisplay, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }
	if props then for k, v in props do p[k] = v end end
	return Make.label(text, size, p)
end

local function inkButton(text: string, fill: Color3, textColor: Color3, onClick: () -> (), props: { [any]: any }?)
	local p = {
		TextColor3 = textColor,
		Font = Theme.fontDisplay,
		TextSize = 15,
		Make("UIStroke", { Color = Theme.ink, Thickness = 2.5 }),
	}
	if props then for k, v in props do p[k] = v end end
	local b = Make.button(text, fill, onClick, p)
	b.TextColor3 = textColor
	return b
end

local function tabPill(text: string, selected: boolean, onClick: () -> (), order: number, parent: Instance)
	return inkButton(text, if selected then Theme.accent else Theme.cream, Theme.ink, onClick, {
		Size = UDim2.new(0, 120, 0, Responsive.touchSize() - 6), LayoutOrder = order, Parent = parent,
	})
end

----------------------------------------------------------------------------

function Lobby.new(parent: Instance): Lobby
	local self = setmetatable({}, Lobby)
	self.init = { modes = {}, minPlayers = 2, maxPlayers = 10 }
	self.rooms = {}
	self.room = nil
	self.pad = nil
	self.points = 0
	self.tab = "join"
	self.visibility = "public"
	self.open = false
	local compact = Responsive.isCompact()
	local touch = Responsive.touchSize()

	self.root = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })

	-- Top-left bar
	self.bar = Make("Frame", {
		BackgroundColor3 = Theme.cream,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(0, touch + 12),
		AutomaticSize = Enum.AutomaticSize.X,
		Rotation = -1.5,
		Make.corner(UDim.new(0, 6)),
		Make.pad(6),
		Make.list(Enum.FillDirection.Horizontal, 8),
		Make("UIStroke", { Color = Theme.ink, Thickness = 3 }),
		Parent = self.root,
	})
	Make.label("STORY<font color=\"#ff5678\">DUB</font>", 22, {
		RichText = true, Font = Theme.fontDisplay, TextColor3 = Theme.ink,
		Size = UDim2.fromOffset(120, touch), TextYAlignment = Enum.TextYAlignment.Center, LayoutOrder = 1, Parent = self.bar,
	})
	self.pointsLabel = Make.label("", 13, {
		TextColor3 = Theme.ink, Font = Theme.font, Size = UDim2.fromOffset(0, touch), AutomaticSize = Enum.AutomaticSize.X,
		TextYAlignment = Enum.TextYAlignment.Center, LayoutOrder = 2, Parent = self.bar,
	})
	inkButton("PLAY", Theme.accent, Theme.ink, function() self:setOpen(not self.open) end, {
		Size = UDim2.fromOffset(96, touch), LayoutOrder = 3, Parent = self.bar,
	})

	-- Matchmaking panel: a comic page
	self.panel = Make("Frame", {
		BackgroundColor3 = Theme.creamDark,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = if compact then UDim2.new(1, -16, 1, -16) else UDim2.fromOffset(820, 560),
		Visible = false,
		Active = true,
		Make.corner(UDim.new(0, 8)),
		Make.pad(16),
		Make("UIStroke", { Color = Theme.ink, Thickness = 4 }),
		Parent = self.root,
	})
	-- Soft paper gradient
	Make("UIGradient", {
		Color = ColorSequence.new(Theme.cream, Theme.creamDark),
		Rotation = 90,
		Parent = self.panel,
	})
	local header = Make.row(touch, 8, { Parent = self.panel })
	self.tabs = header
	inkButton("✕", Theme.pop, Theme.cream, function() self:setOpen(false) end, {
		Size = UDim2.fromOffset(touch, touch),
		TextSize = 18,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Parent = self.panel,
	})
	self.panelBody = Make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, touch + 16),
		Size = UDim2.new(1, 0, 1, -(touch + 16)),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.ink,
		Make.list(nil, 14),
		Make("UIPadding", { PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8) }),
		Parent = self.panel,
	})

	-- Pad banner
	self.banner = Make("Frame", {
		BackgroundColor3 = Theme.cream,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = if compact then UDim2.new(1, -24, 0, 92) else UDim2.fromOffset(600, 76),
		Visible = false,
		Make.corner(UDim.new(0, 6)),
		Make.pad(10),
		Make("UIStroke", { Color = Theme.ink, Thickness = 3 }),
		Parent = self.root,
	})
	self.bannerText = Make.label("", 15, { RichText = true, TextColor3 = Theme.ink, Size = UDim2.new(1, -140, 1, 0), TextYAlignment = Enum.TextYAlignment.Center, Parent = self.banner })
	inkButton("Vote mode", Theme.accent2, Theme.ink, function()
		self.tab = "room"
		self:setOpen(true)
	end, { Size = UDim2.fromOffset(124, touch), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Parent = self.banner })

	self.heartbeat = RunService.Heartbeat:Connect(function() self:tickBanner() end)
	self:setPoints(0)
	return self
end

----------------------------------------------------------------------------
-- State setters

function Lobby.setInit(self: Lobby, data: any)
	self.init = data
	self:render()
end

function Lobby.setRooms(self: Lobby, rooms: { any })
	self.rooms = rooms
	if self.open and self.tab == "join" then self:render() end
end

function Lobby.setRoom(self: Lobby, room: any)
	local hadRoom = self.room ~= nil
	self.room = room
	if room and not hadRoom then
		self.tab = "room"
		self:setOpen(true)
	elseif not room and hadRoom and self.tab == "room" then
		self.tab = "join"
	end
	self:render()
end

function Lobby.setPad(self: Lobby, pad: any)
	self.pad = pad
	self.banner.Visible = pad ~= nil
	if not pad and self.room == nil and self.tab == "room" then
		self.tab = "join"
	end
	self:render()
end

function Lobby.setPoints(self: Lobby, total: number)
	self.points = total
	local pro = self.init.proPoints or 10000
	self.pointsLabel.Text = if total >= pro then ("★ %d pts · PRO"):format(total) else ("★ %d pts"):format(total)
end

function Lobby.setOpen(self: Lobby, open: boolean)
	self.open = open
	self.panel.Visible = open
	if open then self:render() end
end

function Lobby.setVisible(self: Lobby, visible: boolean)
	self.root.Visible = visible
	if not visible then self:setOpen(false) end
end

----------------------------------------------------------------------------
-- Rendering

function Lobby.activeRoom(self: Lobby): any
	return self.room or self.pad
end

function Lobby.tickBanner(self: Lobby)
	local pad = self.pad
	if not pad then return end
	local status
	if pad.state == "starting" and pad.startsAt then
		local left = math.max(0, math.ceil(pad.startsAt - workspace:GetServerTimeNow()))
		status = ("<font color=\"#1f8a4c\"><b>starting in %ds</b></font>"):format(left)
	else
		status = ("need %d to start"):format(pad.minPlayers)
	end
	self.bannerText.Text = ("<b>Platform %d</b>  ·  %d/%d players  ·  %s\n<font size=\"12\">Step off the platform to leave.</font>"):format(
		pad.padIndex or 0, #pad.members, pad.maxPlayers, status)
end

function Lobby.voiceBlocked(self: Lobby): boolean
	return self.init.voiceEnabled == false
end

function Lobby.isPro(self: Lobby): boolean
	return self.points >= (self.init.proPoints or 10000)
end

local function clearGui(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
end

function Lobby.render(self: Lobby)
	if not self.open then return end
	clearGui(self.tabs)
	local active = self:activeRoom()
	local tabDefs = { { id = "join", label = "JOIN" }, { id = "create", label = "CREATE" } }
	if active then
		table.insert(tabDefs, { id = "room", label = if active.kind == "pad" then "PLATFORM" else "YOUR ROOM" })
	end
	if self.tab == "room" and not active then self.tab = "join" end
	for i, def in tabDefs do
		tabPill(def.label, self.tab == def.id, function()
			self.tab = def.id
			self:render()
		end, i, self.tabs)
	end

	clearGui(self.panelBody)
	if self.tab == "join" then
		self:renderJoin()
	elseif self.tab == "create" then
		self:renderCreate()
	else
		self:renderRoom(active)
	end
end

function Lobby.renderVoiceWarning(self: Lobby, body: Instance)
	local card = inkPanel({ Parent = body })
	inkHeading("🎤 VOICE CHAT REQUIRED", 18, { TextColor3 = Theme.pop, Parent = card })
	inkText(self.init.voiceMessage or "StoryDub is played with voice chat. Turn it on in your Roblox settings, then rejoin.", 14, { Parent = card })
	inkText("Settings → Privacy → Voice chat. You must be 13+ with a verified account.", 13, { TextTransparency = 0.35, Parent = card })
end

local VIS_ICON = { public = "🌐", friends = "🔒", pro = "★" }
local VIS_NAME = { public = "Public", friends = "Friends only", pro = "Pro" }

function Lobby.renderJoin(self: Lobby)
	local body = self.panelBody
	if self:voiceBlocked() then self:renderVoiceWarning(body) return end
	if self.room then
		inkText("You're already in a room. Leave it to join another.", 14, { Parent = body })
	end
	local tip = inkPanel({ BackgroundColor3 = Theme.accent, Parent = body })
	inkHeading("TWO WAYS TO PLAY", 14, { Parent = tip })
	inkText("Join a room below, or walk onto a glowing platform outside to play with whoever is standing there.", 14, { Parent = tip })

	if #self.rooms == 0 then
		local empty = inkPanel({ Parent = body })
		inkHeading("NO OPEN ROOMS", 18, { Parent = empty })
		inkText("Create one. Set it to Friends Only so only your friends can see it, or Pro if you've earned it.", 14, { Parent = empty })
		return
	end
	for i, r in self.rooms do
		local row = inkPanel({ LayoutOrder = i, Parent = body })
		row.Size = UDim2.new(1, 0, 0, 78)
		row.AutomaticSize = Enum.AutomaticSize.None
		local layout = row:FindFirstChildOfClass("UIListLayout")
		if layout then layout:Destroy() end
		inkHeading(("%s  %s's room"):format(VIS_ICON[r.visibility] or "", r.hostName), 17, { Size = UDim2.new(1, -130, 0, 22), AutomaticSize = Enum.AutomaticSize.None, Parent = row })
		inkText(("%d/%d players  ·  %s%s"):format(r.memberCount, r.maxPlayers, VIS_NAME[r.visibility] or r.visibility, if r.state ~= "waiting" then "  ·  playing" else ""), 13, {
			Size = UDim2.new(1, -130, 0, 18), AutomaticSize = Enum.AutomaticSize.None, Position = UDim2.fromOffset(0, 26), TextTransparency = 0.3, Parent = row,
		})
		local joinable = r.state == "waiting" and r.memberCount < r.maxPlayers and not self.room
		inkButton(if r.state ~= "waiting" then "PLAYING" elseif r.memberCount >= r.maxPlayers then "FULL" else "JOIN",
			if joinable then Theme.accent else Theme.creamDark, Theme.ink,
			function() if joinable then send(Net.C2S.JoinRoom, r.id) end end,
			{ Size = UDim2.fromOffset(110, Responsive.touchSize() - 4), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Parent = row })
	end
end

function Lobby.renderCreate(self: Lobby)
	local body = self.panelBody
	if self:voiceBlocked() then self:renderVoiceWarning(body) return end
	local card = inkPanel({ Parent = body })
	inkHeading("WHO CAN JOIN?", 18, { Parent = card })
	local row = Make.row(Responsive.touchSize(), 8, { Parent = card })
	local function choice(id: string, label: string, enabled: boolean)
		inkButton(label, if self.visibility == id then Theme.accent elseif enabled then Theme.cream else Theme.creamDark, Theme.ink, function()
			if enabled then
				self.visibility = id
				self:render()
			end
		end, { Size = UDim2.new(1 / 3, -6, 1, 0), TextSize = 13, Parent = row })
	end
	choice("public", "🌐 PUBLIC", true)
	choice("friends", "🔒 FRIENDS", true)
	choice("pro", "★ PRO", self:isPro())
	local pro = self.init.proPoints or 10000
	local explain = if self.visibility == "friends"
		then "Only your Roblox friends can see or join this room."
		elseif self.visibility == "pro" then ("A Pro room. Only players with %d+ points can see or join, so expect serious artists."):format(pro)
		else "Anyone on this server can see and join this room."
	inkText(explain, 14, { Parent = card })
	if not self:isPro() then
		inkText(("Pro rooms unlock at %d points. You have %d. Points come from every finished round and every award you win."):format(pro, self.points), 13, { TextTransparency = 0.35, Parent = card })
	end
	inkText(("Rooms hold %d to %d players. Vote on a mode together; the host starts. The party is moved to its own private server for the match."):format(self.init.minPlayers, self.init.maxPlayers), 13, { TextTransparency = 0.35, Parent = card })
	local canCreate = self.room == nil
	inkButton(if canCreate then "CREATE ROOM" else "LEAVE YOUR ROOM FIRST", if canCreate then Theme.pop else Theme.creamDark, if canCreate then Theme.cream else Theme.ink, function()
		if canCreate then send(Net.C2S.CreateRoom, { visibility = self.visibility }) end
	end, { Size = UDim2.new(1, 0, 0, Responsive.touchSize()), Parent = card })
end

function Lobby.renderRoom(self: Lobby, room: any)
	local body = self.panelBody
	local me = Players.LocalPlayer.UserId
	local isPad = room.kind == "pad"
	local isHost = room.hostId == me

	local head = inkPanel({ Parent = body })
	if isPad then
		inkHeading(("PLATFORM %d"):format(room.padIndex or 0), 20, { Parent = head })
		inkText("Everyone standing on the platform plays. The match starts automatically once enough people are on it. Step off to leave.", 13, { TextTransparency = 0.3, Parent = head })
	else
		inkHeading(("%s  %s'S ROOM"):format(VIS_ICON[room.visibility] or "", room.hostName:upper()), 20, { Parent = head })
		inkText(if room.visibility == "friends" then "Friends only." elseif room.visibility == "pro" then "Pro room." else "Public.", 13, { TextTransparency = 0.3, Parent = head })
	end
	inkHeading(("%d/%d PLAYERS"):format(#room.members, room.maxPlayers), 13, { Parent = head })
	for _, m in room.members do
		local row = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), Parent = head })
		local tag = if m.userId == room.hostId and not isPad then "  👑 host" elseif m.userId == me then "  (you)" else ""
		inkText(m.name .. tag, 14, { Size = UDim2.new(1, -100, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextYAlignment = Enum.TextYAlignment.Center, Parent = row })
		if isHost and not isPad and m.userId ~= me then
			inkButton("REMOVE", Theme.cream, Theme.pop, function() send(Net.C2S.KickPlayer, m.userId) end,
				{ Size = UDim2.fromOffset(92, 28), TextSize = 11, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Parent = row })
		end
	end

	if not isPad then
		local actions = Make.row(Responsive.touchSize(), 8, { Parent = body })
		local enough = #room.members >= room.minPlayers
		if isHost then
			inkButton(if enough then "START MATCH" else ("NEED %d PLAYERS"):format(room.minPlayers), if enough then Theme.pop else Theme.creamDark, if enough then Theme.cream else Theme.ink, function()
				if enough then send(Net.C2S.StartRoom) end
			end, { Size = UDim2.new(0.6, -4, 1, 0), Parent = actions })
		else
			inkText(if enough then "Waiting for the host to start..." else ("Waiting for players (%d needed)..."):format(room.minPlayers), 14, {
				Size = UDim2.new(0.6, -4, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextYAlignment = Enum.TextYAlignment.Center, Parent = actions,
			})
		end
		inkButton("LEAVE", Theme.cream, Theme.ink, function() send(Net.C2S.LeaveRoom) end, { Size = UDim2.new(0.4, -4, 1, 0), Parent = actions })
	end

	inkHeading("VOTE FOR A MODE", 15, { TextColor3 = Theme.pop, Parent = body })
	local myVote: string? = nil
	for _, m in room.members do
		if m.userId == me then myVote = m.vote end
	end
	ModeGrid.build(body, {
		modes = self.init.modes,
		votes = room.votes or {},
		myVote = myVote,
		playerCount = #room.members,
		likelyModeId = room.likelyModeId,
		onVote = function(modeId) send(Net.C2S.VoteMode, modeId) end,
		comic = true,
	})
end

function Lobby.destroy(self: Lobby)
	if self.heartbeat then self.heartbeat:Disconnect() end
	self.root:Destroy()
end

return Lobby
