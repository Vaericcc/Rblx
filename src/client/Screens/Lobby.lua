--!strict
--[[
	Hub UI. The 3D world stays visible and walkable; this draws:
		- a small top-left bar with a Play button
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
	panel: Frame,
	panelBody: Frame,
	tabs: Frame,
	banner: Frame,
	bannerText: TextLabel,
	init: any,
	rooms: { any },
	room: any,
	pad: any,
	tab: string,
	visibility: string,
	open: boolean,
	heartbeat: RBXScriptConnection?,
}, Lobby))

local function send(action: string, data: any?)
	Net.remote:FireServer(action, data)
end

function Lobby.new(parent: Instance): Lobby
	local self = setmetatable({}, Lobby)
	self.init = { modes = {}, minPlayers = 2, maxPlayers = 10 }
	self.rooms = {}
	self.room = nil
	self.pad = nil
	self.tab = "join"
	self.visibility = "public"
	self.open = false
	local compact = Responsive.isCompact()

	self.root = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })

	-- Top-left bar
	self.bar = Make("Frame", {
		BackgroundColor3 = Theme.panel,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(0, Responsive.touchSize() + 8),
		AutomaticSize = Enum.AutomaticSize.X,
		Make.corner(),
		Make.pad(6),
		Make.list(Enum.FillDirection.Horizontal, 8),
		Parent = self.root,
	})
	Make.heading("STORY<font color=\"#ffc43d\">DUB</font>", 20, {
		RichText = true, Size = UDim2.fromOffset(110, Responsive.touchSize() - 4), TextYAlignment = Enum.TextYAlignment.Center, LayoutOrder = 1, Parent = self.bar,
	})
	Make.button("Play", Theme.accent, function() self:setOpen(not self.open) end, {
		Size = UDim2.fromOffset(90, Responsive.touchSize() - 4), LayoutOrder = 2, Parent = self.bar,
	})

	-- Matchmaking panel
	self.panel = Make("Frame", {
		BackgroundColor3 = Theme.bg,
		BackgroundTransparency = 0.04,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = if compact then UDim2.new(1, -16, 1, -16) else UDim2.fromOffset(760, 520),
		Visible = false,
		Active = true,
		Make.corner(UDim.new(0, 16)),
		Make.pad(14),
		Make("UIStroke", { Color = Theme.panelAlt, Thickness = 1 }),
		Parent = self.root,
	})
	local header = Make.row(Responsive.touchSize(), 8, { Parent = self.panel })
	self.tabs = header
	Make.button("✕", Theme.panelAlt, function() self:setOpen(false) end, {
		Size = UDim2.fromOffset(Responsive.touchSize(), Responsive.touchSize()),
		TextColor3 = Theme.text,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Parent = self.panel,
	})
	self.panelBody = Make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, Responsive.touchSize() + 12),
		Size = UDim2.new(1, 0, 1, -(Responsive.touchSize() + 12)),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 6,
		Make.list(nil, 10),
		Parent = self.panel,
	})

	-- Pad banner
	self.banner = Make("Frame", {
		BackgroundColor3 = Theme.panel,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = if compact then UDim2.new(1, -24, 0, 92) else UDim2.fromOffset(560, 72),
		Visible = false,
		Make.corner(),
		Make.pad(10),
		Make("UIStroke", { Color = Theme.accent, Thickness = 1 }),
		Parent = self.root,
	})
	self.bannerText = Make.label("", 15, { RichText = true, Size = UDim2.new(1, -130, 1, 0), TextYAlignment = Enum.TextYAlignment.Center, Parent = self.banner })
	Make.button("Vote mode", Theme.accent2, function()
		self.tab = "room"
		self:setOpen(true)
	end, { Size = UDim2.fromOffset(120, Responsive.touchSize()), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Parent = self.banner })

	self.heartbeat = RunService.Heartbeat:Connect(function()
		self:tickBanner()
	end)
	return self
end

----------------------------------------------------------------------------
-- State setters (called by Main when the server sends updates)

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

-- The room shown in the "Your Room" tab: a UI room if you're in one, else the pad under you.
function Lobby.activeRoom(self: Lobby): any
	return self.room or self.pad
end

function Lobby.tickBanner(self: Lobby)
	local pad = self.pad
	if not pad then return end
	local status
	if pad.state == "starting" and pad.startsAt then
		local left = math.max(0, math.ceil(pad.startsAt - workspace:GetServerTimeNow()))
		status = ("<font color=\"#60dc8c\">starting in %ds</font>"):format(left)
	else
		status = ("<font color=\"#aaaabe\">need %d to start</font>"):format(pad.minPlayers)
	end
	self.bannerText.Text = ("<b>Platform %d</b>  ·  %d/%d players  ·  %s\n<font color=\"#aaaabe\" size=\"12\">Step off the platform to leave.</font>"):format(
		pad.padIndex or 0, #pad.members, pad.maxPlayers, status)
end

function Lobby.render(self: Lobby)
	if not self.open then return end
	-- Tabs
	for _, child in self.tabs:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	local active = self:activeRoom()
	local tabDefs = {
		{ id = "join", label = "Join" },
		{ id = "create", label = "Create" },
	}
	if active then
		table.insert(tabDefs, { id = "room", label = if active.kind == "pad" then "Platform" else "Your Room" })
	end
	if self.tab == "room" and not active then self.tab = "join" end
	for i, def in tabDefs do
		Make.pill(def.label, self.tab == def.id, function()
			self.tab = def.id
			self:render()
		end, { LayoutOrder = i, Parent = self.tabs })
	end

	-- Body
	for _, child in self.panelBody:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	if self.tab == "join" then
		self:renderJoin()
	elseif self.tab == "create" then
		self:renderCreate()
	else
		self:renderRoom(active)
	end
end

function Lobby.renderJoin(self: Lobby)
	local body = self.panelBody
	if self.room then
		Make.label("You're already in a room. Leave it to join another.", 14, { TextColor3 = Theme.textDim, Parent = body })
	end
	Make.label("Or walk onto one of the glowing platforms outside to start a match with whoever's standing there.", 13, {
		TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 34), Parent = body,
	})
	if #self.rooms == 0 then
		local empty = Make.card({ Size = UDim2.new(1, 0, 0, 110), Parent = body })
		Make.heading("No open rooms", 18, { Parent = empty })
		Make.label("Create one, or invite friends and set it to Friends Only so only they can see it.", 14, {
			TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 50), Position = UDim2.fromOffset(0, 28), Parent = empty,
		})
		return
	end
	for i, r in self.rooms do
		local row = Make.card({ Size = UDim2.new(1, 0, 0, 72), LayoutOrder = i, Parent = body })
		local icon = if r.visibility == "friends" then "🔒" else "🌐"
		Make.heading(("%s  %s's room"):format(icon, r.hostName), 17, { Size = UDim2.new(1, -120, 0, 22), Parent = row })
		local sub = ("%d/%d players  ·  %s%s"):format(r.memberCount, r.maxPlayers,
			if r.visibility == "friends" then "Friends only" else "Public",
			if r.state ~= "waiting" then "  ·  playing" else "")
		Make.label(sub, 13, { TextColor3 = Theme.textDim, Size = UDim2.new(1, -120, 0, 18), Position = UDim2.fromOffset(0, 24), Parent = row })
		local joinable = r.state == "waiting" and r.memberCount < r.maxPlayers and not self.room
		Make.button(if r.state ~= "waiting" then "Playing" elseif r.memberCount >= r.maxPlayers then "Full" else "Join",
			if joinable then Theme.accent else Theme.panelAlt,
			function() if joinable then send(Net.C2S.JoinRoom, r.id) end end,
			{ Size = UDim2.fromOffset(100, Responsive.touchSize() - 4), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), TextColor3 = if joinable then Theme.bg else Theme.textDim, Parent = row })
	end
end

function Lobby.renderCreate(self: Lobby)
	local body = self.panelBody
	local card = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 10), Parent = body })
	Make.heading("Who can join?", 18, { Parent = card })
	local row = Make.row(Responsive.touchSize(), 8, { Parent = card })
	local function choice(id: string, label: string)
		Make.pill(label, self.visibility == id, function()
			self.visibility = id
			self:render()
		end, { Size = UDim2.new(0.5, -4, 1, 0), Parent = row })
	end
	choice("public", "🌐  Public")
	choice("friends", "🔒  Friends only")
	Make.label(
		if self.visibility == "friends"
			then "Only your Roblox friends can see or join this room. Great for private sessions."
			else "Anyone in this server can see and join this room.",
		13, { TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 34), Parent = card })
	Make.label(("Rooms hold %d to %d players. You pick a mode together and the host starts the match."):format(self.init.minPlayers, self.init.maxPlayers), 13, {
		TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 34), Parent = card,
	})
	local canCreate = self.room == nil
	Make.button(if canCreate then "Create room" else "Leave your room first", if canCreate then Theme.good else Theme.panelAlt, function()
		if canCreate then send(Net.C2S.CreateRoom, { visibility = self.visibility }) end
	end, { Size = UDim2.new(1, 0, 0, Responsive.touchSize()), Parent = card })
end

function Lobby.renderRoom(self: Lobby, room: any)
	local body = self.panelBody
	local me = Players.LocalPlayer.UserId
	local isPad = room.kind == "pad"
	local isHost = room.hostId == me

	local head = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 6), Parent = body })
	if isPad then
		Make.heading(("Platform %d"):format(room.padIndex or 0), 20, { Parent = head })
		Make.label("Everyone standing on the platform plays. The match starts automatically once enough people are on it. Step off to leave.", 13, {
			TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 40), Parent = head,
		})
	else
		Make.heading(("%s  %s's room"):format(if room.visibility == "friends" then "🔒" else "🌐", room.hostName), 20, { Parent = head })
		Make.label(if room.visibility == "friends" then "Friends only. Only the host's friends can see this room." else "Public. Anyone on this server can join.", 13, {
			TextColor3 = Theme.textDim, Parent = head,
		})
	end
	-- Members
	local names = {}
	for _, m in room.members do
		table.insert(names, if m.userId == room.hostId and not isPad then m.name .. " 👑" else m.name)
	end
	Make.label(("<b>%d/%d</b>  %s"):format(#room.members, room.maxPlayers, table.concat(names, "  ·  ")), 14, {
		RichText = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = head,
	})

	-- Actions
	local actions = Make.row(Responsive.touchSize(), 8, { Parent = body })
	if not isPad then
		local enough = #room.members >= room.minPlayers
		if isHost then
			Make.button(if enough then "Start match" else ("Need %d players"):format(room.minPlayers), if enough then Theme.good else Theme.panelAlt, function()
				if enough then send(Net.C2S.StartRoom) end
			end, { Size = UDim2.new(0.6, -4, 1, 0), TextColor3 = if enough then Theme.text else Theme.textDim, Parent = actions })
		else
			Make.label(if enough then "Waiting for the host to start..." else ("Waiting for players (%d needed)..."):format(room.minPlayers), 14, {
				TextColor3 = Theme.textDim, Size = UDim2.new(0.6, -4, 1, 0), TextYAlignment = Enum.TextYAlignment.Center, Parent = actions,
			})
		end
		Make.button("Leave", Theme.danger, function() send(Net.C2S.LeaveRoom) end, { Size = UDim2.new(0.4, -4, 1, 0), Parent = actions })
	else
		actions:Destroy()
	end

	-- Mode vote
	Make.heading("Vote for a mode", 16, { TextColor3 = Theme.accent, Parent = body })
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
		onVote = function(modeId)
			send(Net.C2S.VoteMode, modeId)
		end,
	})
end

function Lobby.destroy(self: Lobby)
	if self.heartbeat then self.heartbeat:Disconnect() end
	self.root:Destroy()
end

return Lobby
