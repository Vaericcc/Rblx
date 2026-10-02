--!strict
--[[
	Hub UI built on the Menu system.
		- a small ink badge top-left with the logo, your points and PLAY
		- PLAY opens the menu: JOIN / CREATE / YOUR ROOM or PLATFORM / SETTINGS / CLOSE
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
local Menu = require(UI.Menu)
local ModeGrid = require(UI.ModeGrid)

local Lobby = {}
Lobby.__index = Lobby

export type Lobby = typeof(setmetatable({} :: {
	root: Frame,
	bar: Frame,
	pointsLabel: TextLabel,
	banner: Frame,
	bannerText: TextLabel,
	menu: Menu.Menu?,
	init: any,
	rooms: { any },
	room: any,
	pad: any,
	points: number,
	page: string,
	visibility: string,
	heartbeat: RBXScriptConnection?,
	onUiScale: ((number) -> ())?,
}, Lobby))

local function send(action: string, data: any?)
	Net.remote:FireServer(action, data)
end

local VIS_ICON = { public = "🌐", friends = "🔒", pro = "★" }
local VIS_NAME = { public = "Public", friends = "Friends only", pro = "Pro" }

function Lobby.new(parent: Instance): Lobby
	local self = setmetatable({}, Lobby)
	self.init = { modes = {}, minPlayers = 2, maxPlayers = 10 }
	self.rooms = {}
	self.room = nil
	self.pad = nil
	self.points = 0
	self.page = "join"
	self.visibility = "public"
	self.menu = nil
	local compact = Responsive.isCompact()
	local touch = Responsive.touchSize()

	self.root = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })

	-- Badge
	self.bar = Make("Frame", {
		BackgroundColor3 = Theme.ink,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(0, touch + 12),
		AutomaticSize = Enum.AutomaticSize.X,
		Rotation = -1.5,
		Make.corner(UDim.new(0, 4)),
		Make.pad(6),
		Make.list(Enum.FillDirection.Horizontal, 10),
		Make("UIStroke", { Color = Theme.cream, Thickness = 2 }),
		Parent = self.root,
	})
	Make.label("STORY<font color=\"#ff466e\">DUB</font>", 30, {
		RichText = true, Font = Theme.fontDisplay, TextColor3 = Theme.cream,
		Size = UDim2.fromOffset(140, touch), TextYAlignment = Enum.TextYAlignment.Center, LayoutOrder = 1, Parent = self.bar,
	})
	self.pointsLabel = Make.label("", 14, {
		TextColor3 = Theme.cream, Font = Theme.font, Size = UDim2.fromOffset(0, touch), AutomaticSize = Enum.AutomaticSize.X,
		TextYAlignment = Enum.TextYAlignment.Center, LayoutOrder = 2, Parent = self.bar,
	})
	Make.button("PLAY", Theme.pop, function() self:openMenu() end, {
		Font = Theme.fontDisplay, TextSize = 24, TextColor3 = Theme.cream,
		Size = UDim2.fromOffset(100, touch), LayoutOrder = 3, Make("UIStroke", { Color = Theme.cream, Thickness = 2 }), Parent = self.bar,
	})

	-- Pad banner
	self.banner = Make("Frame", {
		BackgroundColor3 = Theme.ink,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = if compact then UDim2.new(1, -24, 0, 92) else UDim2.fromOffset(620, 76),
		Rotation = -0.8,
		Visible = false,
		Make.corner(UDim.new(0, 4)),
		Make.pad(10),
		Make("UIStroke", { Color = Theme.cream, Thickness = 2 }),
		Parent = self.root,
	})
	self.bannerText = Make.label("", 15, { RichText = true, TextColor3 = Theme.cream, Size = UDim2.new(1, -150, 1, 0), TextYAlignment = Enum.TextYAlignment.Center, Parent = self.banner })
	Make.button("VOTE MODE", Theme.accent, function()
		self.page = "room"
		self:openMenu()
	end, { Font = Theme.fontDisplay, TextSize = 20, TextColor3 = Theme.ink, Size = UDim2.fromOffset(136, touch), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Parent = self.banner })

	self.heartbeat = RunService.Heartbeat:Connect(function() self:tickBanner() end)
	self:setPoints(0)
	return self
end

----------------------------------------------------------------------------
-- State

function Lobby.setInit(self: Lobby, data: any) self.init = data self:render() end
function Lobby.setRooms(self: Lobby, rooms: { any }) self.rooms = rooms if self.page == "join" then self:render() end end
function Lobby.setPoints(self: Lobby, total: number)
	self.points = total
	local pro = self.init.proPoints or 10000
	self.pointsLabel.Text = if total >= pro then ("★ %d · PRO"):format(total) else ("★ %d"):format(total)
end

function Lobby.setRoom(self: Lobby, room: any)
	local hadRoom = self.room ~= nil
	self.room = room
	if room and not hadRoom then
		self.page = "room"
		self:openMenu()
	elseif not room and hadRoom and self.page == "room" then
		self.page = "join"
	end
	self:render()
end

function Lobby.setPad(self: Lobby, pad: any)
	self.pad = pad
	self.banner.Visible = pad ~= nil
	if not pad and self.room == nil and self.page == "room" then self.page = "join" end
	self:render()
end

function Lobby.setVisible(self: Lobby, visible: boolean)
	self.root.Visible = visible
	if not visible then self:closeMenu() end
end

function Lobby.activeRoom(self: Lobby): any
	return self.room or self.pad
end

function Lobby.tickBanner(self: Lobby)
	local pad = self.pad
	if not pad then return end
	local status
	if pad.state == "starting" and pad.startsAt then
		local left = math.max(0, math.ceil(pad.startsAt - workspace:GetServerTimeNow()))
		status = ("<font color=\"#60dc8c\"><b>starting in %ds</b></font>"):format(left)
	else
		status = ("need %d to start"):format(pad.minPlayers)
	end
	self.bannerText.Text = ("<b>Platform %d</b>  ·  %d/%d players  ·  %s\n<font size=\"12\">Step off the platform to leave.</font>"):format(
		pad.padIndex or 0, #pad.members, pad.maxPlayers, status)
end

----------------------------------------------------------------------------
-- Menu

function Lobby.openMenu(self: Lobby)
	if self.menu then self:render() return end
	self.menu = Menu.open({
		title = "STORYDUB",
		items = {},
		parent = self.root,
		onClose = function() self.menu = nil end,
	})
	self:render()
end

function Lobby.closeMenu(self: Lobby)
	if self.menu then
		local m = self.menu
		self.menu = nil
		m:close()
	end
end

function Lobby.render(self: Lobby)
	local menu = self.menu
	if not menu then return end
	local active = self:activeRoom()
	local items: { Menu.Item } = {
		{ id = "join", label = "JOIN", onClick = function() self.page = "join" self:render() end },
		{ id = "create", label = "CREATE", onClick = function() self.page = "create" self:render() end },
	}
	if active then
		table.insert(items, { id = "room", label = if active.kind == "pad" then "PLATFORM" else "YOUR ROOM", accent = true, onClick = function() self.page = "room" self:render() end })
	end
	table.insert(items, { id = "settings", label = "SETTINGS", onClick = function() self.page = "settings" self:render() end })
	table.insert(items, { id = "close", label = "CLOSE", onClick = function() self:closeMenu() end })
	if self.page == "room" and not active then self.page = "join" end
	menu:setItems(items)
	menu:select(self.page)

	if self.page == "settings" then
		menu:settingsPage(self.onUiScale)
		return
	end
	menu:clearContent()
	local body = menu:content()
	if self.page == "join" then self:renderJoin(body)
	elseif self.page == "create" then self:renderCreate(body)
	else self:renderRoom(body, active) end
end

function Lobby.voiceBlocked(self: Lobby): boolean
	return self.init.voiceEnabled == false
end

function Lobby.isPro(self: Lobby): boolean
	return self.points >= (self.init.proPoints or 10000)
end

function Lobby.renderVoiceWarning(self: Lobby, body: Instance)
	local card = Menu.card(body)
	Menu.heading(card, "VOICE CHAT REQUIRED", 22)
	Menu.text(card, self.init.voiceMessage or "StoryDub is played with voice chat. Turn it on in your Roblox settings, then rejoin.")
	Menu.text(card, "Settings → Privacy → Voice chat. You must be 13+ with a verified account.", 13, true)
end

function Lobby.renderJoin(self: Lobby, body: Instance)
	Menu.heading(body, "JOIN A ROOM")
	if self:voiceBlocked() then self:renderVoiceWarning(body) return end
	Menu.text(body, "Pick a room below, or walk onto a glowing platform outside to play with whoever is standing there.", 13, true)
	if self.room then Menu.text(body, "You're already in a room. Leave it to join another.", 13) end
	if #self.rooms == 0 then
		local empty = Menu.card(body)
		Menu.heading(empty, "NO OPEN ROOMS", 20)
		Menu.text(empty, "Create one. Friends Only shows it to your friends alone; Pro needs the points.", 13, true)
		return
	end
	for i, r in self.rooms do
		local row = Menu.card(body, { LayoutOrder = i })
		Menu.heading(row, ("%s  %s'S ROOM"):format(VIS_ICON[r.visibility] or "", r.hostName:upper()), 20)
		Menu.text(row, ("%d/%d players  ·  %s%s"):format(r.memberCount, r.maxPlayers, VIS_NAME[r.visibility] or r.visibility, if r.state ~= "waiting" then "  ·  playing" else ""), 13, true)
		local joinable = r.state == "waiting" and r.memberCount < r.maxPlayers and not self.room
		Menu.button(row, if r.state ~= "waiting" then "PLAYING" elseif r.memberCount >= r.maxPlayers then "FULL" else "JOIN",
			if joinable then Theme.pop else Theme.creamDark, function()
				if joinable then send(Net.C2S.JoinRoom, r.id) end
			end)
	end
end

function Lobby.renderCreate(self: Lobby, body: Instance)
	Menu.heading(body, "CREATE A ROOM")
	if self:voiceBlocked() then self:renderVoiceWarning(body) return end
	local card = Menu.card(body)
	Menu.heading(card, "WHO CAN JOIN?", 18)
	local row = Make.row(Responsive.touchSize(), 6, { ZIndex = 306, Parent = card })
	local function choice(id: string, label: string, enabled: boolean)
		Menu.button(row, label, if self.visibility == id then Theme.pop elseif enabled then Theme.cream else Theme.creamDark, function()
			if enabled then self.visibility = id self:render() end
		end, { Size = UDim2.new(1 / 3, -4, 1, 0), TextSize = 16 })
	end
	choice("public", "PUBLIC", true)
	choice("friends", "FRIENDS", true)
	choice("pro", "PRO", self:isPro())
	local pro = self.init.proPoints or 10000
	Menu.text(card, if self.visibility == "friends" then "Only your Roblox friends can see or join."
		elseif self.visibility == "pro" then ("Pro room: only players with %d+ points can see or join."):format(pro)
		else "Anyone on this server can see and join.")
	if not self:isPro() then
		Menu.text(card, ("Pro unlocks at %d points. You have %d."):format(pro, self.points), 13, true)
	end
	Menu.text(card, ("Rooms hold %d to %d players. Vote on a mode together; the host starts. The party moves to its own private server for the match."):format(self.init.liveMinPlayers or 2, self.init.maxPlayers), 13, true)
	local canCreate = self.room == nil
	Menu.button(card, if canCreate then "CREATE ROOM" else "LEAVE YOUR ROOM FIRST", if canCreate then Theme.pop else Theme.creamDark, function()
		if canCreate then send(Net.C2S.CreateRoom, { visibility = self.visibility }) end
	end)
end

local function teamColor(colors: any, t: number): Color3
	local c = colors and colors[t]
	return if c then Color3.fromRGB(c.r, c.g, c.b) else Theme.accent2
end

function Lobby.renderRoom(self: Lobby, body: Instance, room: any)
	local me = Players.LocalPlayer.UserId
	local isPad = room.kind == "pad"
	local isHost = room.hostId == me
	Menu.heading(body, if isPad then ("PLATFORM %d"):format(room.padIndex or 0) else ("%s'S ROOM"):format(room.hostName:upper()))
	Menu.text(body, if isPad then "Everyone standing on the platform plays. The match starts automatically once enough people are on it. Step off to leave."
		else (VIS_NAME[room.visibility] or "") .. ". The host starts the match.", 13, true)

	-- Members
	local teamOf: { [number]: number } = {}
	for _, t in room.teams or {} do teamOf[t.userId] = t.team end
	local card = Menu.card(body)
	Menu.heading(card, ("%d/%d PLAYERS"):format(#room.members, room.maxPlayers), 16)
	for _, m in room.members do
		local row = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), ZIndex = 306, Parent = card })
		local tag = if m.userId == room.hostId and not isPad then "  👑" elseif m.userId == me then "  (you)" else ""
		local t = teamOf[m.userId]
		Make.label(m.name .. tag, 14, { Font = Theme.fontBody, TextColor3 = Theme.ink, Size = UDim2.new(1, -200, 1, 0), TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 306, Parent = row })
		if t then
			Make("Frame", { BackgroundColor3 = teamColor(room.teamColors, t), Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -100, 0.5, 0), ZIndex = 306, Make.corner(UDim.new(0.5, 0)), Parent = row })
		end
		if isHost and not isPad and m.userId ~= me then
			Menu.button(row, "REMOVE", Theme.cream, function() send(Net.C2S.KickPlayer, m.userId) end,
				{ Size = UDim2.fromOffset(92, 28), TextSize = 14, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0) })
		end
	end

	-- Actions
	if not isPad then
		local enough = #room.members >= room.minPlayers
		local actions = Make.row(Responsive.touchSize(), 8, { ZIndex = 306, Parent = body })
		if isHost then
			Menu.button(actions, if enough then "START MATCH" else ("NEED %d PLAYERS"):format(room.minPlayers), if enough then Theme.pop else Theme.creamDark, function()
				if enough then send(Net.C2S.StartRoom) end
			end, { Size = UDim2.new(0.6, -4, 1, 0) })
		else
			Menu.text(actions, if enough then "Waiting for the host..." else ("Waiting for players (%d needed)"):format(room.minPlayers), 14)
		end
		Menu.button(actions, "LEAVE", Theme.cream, function() send(Net.C2S.LeaveRoom) end, { Size = UDim2.new(0.4, -4, 1, 0) })
	end

	-- Teams (VS Comic)
	if room.likelyModeId == "versus" then
		local teams = Menu.card(body)
		Menu.heading(teams, "TEAMS", 16)
		local count = room.teamCount or 2
		if not isPad then
			local modeRow = Make.row(Responsive.touchSize() - 8, 6, { ZIndex = 306, Parent = teams })
			for _, def in { { "random", "RANDOM" }, { "pick", "PICK" }, { "assign", "HOST ASSIGNS" } } do
				Menu.button(modeRow, def[2], if room.teamMode == def[1] then Theme.pop else Theme.cream, function()
					if isHost then send(Net.C2S.SetTeamMode, def[1]) end
				end, { Size = UDim2.new(1 / 3, -4, 1, 0), TextSize = 14 })
			end
			if not isHost then Menu.text(teams, "Only the host can change how teams are picked.", 12, true) end
		end
		if room.teamMode == "random" or isPad then
			Menu.text(teams, ("%d teams, dealt at random when the match starts."):format(count), 13, true)
		else
			for t = 1, count do
				local trow = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 306, Make.list(nil, 4), Parent = teams })
				local names = {}
				for _, m in room.members do if teamOf[m.userId] == t then table.insert(names, m.name) end end
				local cname = room.teamColors and room.teamColors[t] and room.teamColors[t].name or tostring(t)
				Menu.button(trow, ("TEAM %s  (%d)"):format(cname:upper(), #names), teamColor(room.teamColors, t), function()
					if room.teamMode == "pick" then send(Net.C2S.PickTeam, t) end
				end, { TextColor3 = Theme.ink, TextSize = 16, Size = UDim2.new(1, 0, 0, 36) })
				Menu.text(trow, if #names > 0 then table.concat(names, ", ") else "nobody yet", 12, true)
				if room.teamMode == "assign" and isHost then
					local pickRow = Make.row(28, 4, { ZIndex = 306, Parent = trow })
					for _, m in room.members do
						if teamOf[m.userId] ~= t then
							Menu.button(pickRow, "+ " .. m.name, Theme.cream, function()
								send(Net.C2S.PickTeam, { userId = m.userId, team = t })
							end, { Size = UDim2.fromOffset(110, 26), TextSize = 12 })
						end
					end
				end
			end
		end
	end

	-- Mode vote
	Menu.heading(body, "VOTE FOR A MODE", 18)
	local myVote: string? = nil
	for _, m in room.members do if m.userId == me then myVote = m.vote end end
	ModeGrid.build(body, {
		modes = self.init.modes, votes = room.votes or {}, myVote = myVote, playerCount = #room.members,
		likelyModeId = room.likelyModeId, onVote = function(modeId) send(Net.C2S.VoteMode, modeId) end, comic = true,
	})
end

function Lobby.destroy(self: Lobby)
	if self.heartbeat then self.heartbeat:Disconnect() end
	self:closeMenu()
	self.root:Destroy()
end

return Lobby
