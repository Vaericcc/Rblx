--!strict
--[[
	Client router.
	Lobby state: the 3D hub is visible; the Lobby module draws the matchmaking UI.
	Match state: a full-screen overlay hosts the current phase screen; movement is disabled.

	The chrome (HUD + lobby) is rebuilt when the screen flips between compact and
	regular, e.g. a tablet rotating or a desktop window being resized.
]]
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local UI = script.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Hud = require(UI.Hud)
local Responsive = require(UI.Responsive)
local Controls = require(UI.Controls)

local AvatarStage = require(UI.AvatarStage)
local Screens = script.Parent.Screens
local Lobby = require(Screens.Lobby)
local TextPhases = require(Screens.TextPhases)
local Claim = require(Screens.Claim)
local Draw = require(Screens.Draw)
local Dub = require(Screens.Dub)
local Wait = require(Screens.Wait)
local Showcase = require(Screens.Showcase)
local Vote = require(Screens.Vote)
local Results = require(Screens.Results)

local player = Players.LocalPlayer
if not player then
	return -- e.g. the Studio server view: nothing to draw for
end
local playerGui = player:WaitForChild("PlayerGui")
local Menu = require(UI.Menu)
local Settings = require(UI.Settings)
local UserInputService = game:GetService("UserInputService")

-- The camera reports a tiny viewport for a moment at startup; measuring then
-- would pick the phone layout on a desktop.
Responsive.waitUntilReady()

----------------------------------------------------------------------------
-- Root GUI

local gui = Make("ScreenGui", {
	Name = "DubbleTake",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})
local function uiScale(): number
	return Responsive.scale() * (Settings.get("uiScale") or 1)
end
local scale = Make("UIScale", { Scale = uiScale(), Parent = gui })
Settings.apply()

local matchRoot = Make("Frame", {
	BackgroundColor3 = Theme.bg,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	Active = true,
	Parent = gui,
})
Make.coverInset(matchRoot, Responsive.inset())

-- Centered column that caps content width on wide screens.
local column = Make("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromScale(1, 1),
	Parent = matchRoot,
})
-- Cap the column in *unscaled* pixels so the cap shrinks with the UI scale and the side panel stays on screen.
local columnCap = Make("UISizeConstraint", { MaxSize = Vector2.new(Responsive.MAX_CONTENT_WIDTH, math.huge), Parent = column })
local function fitColumn()
	local v = Responsive.viewport()
	columnCap.MaxSize = Vector2.new(math.min(Responsive.MAX_CONTENT_WIDTH, v.X / uiScale()), math.huge)
end

local toast = Make.label("", 15, {
	BackgroundColor3 = Theme.panelAlt,
	BackgroundTransparency = 1,
	TextTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.new(0, 480, 0, 40),
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 100,
	Make.corner(),
	Parent = gui,
})

local function showToast(text: string)
	toast.Text = text
	toast.BackgroundTransparency = 0
	toast.TextTransparency = 0
	task.delay(4, function()
		if toast.Text == text then
			toast.BackgroundTransparency = 1
			toast.TextTransparency = 1
		end
	end)
end

----------------------------------------------------------------------------
-- Chrome (rebuilt on compact <-> regular flips)

local hud: Hud.Hud
local lobby: Lobby.Lobby
local togglePlayersMenu
local content: Frame
local chromeCompact: boolean? = nil
local lobbyState = { init = nil :: any, rooms = {} :: { any }, room = nil :: any, pad = nil :: any, members = nil :: any }
local inMatch = false

-- In-match pause menu: resume, players (host can remove), settings, leave.
local pauseMenu: Menu.Menu? = nil
function togglePlayersMenu()
	if pauseMenu then
		local m = pauseMenu
		pauseMenu = nil
		m:close()
		return
	end
	local m: Menu.Menu
	matchRoot.Visible = false
	m = Menu.open({
		title = "PAUSED",
		parent = gui,
		dim = 0.5,
		stage = "solo",
		items = {
			{ id = "resume", label = "RESUME", onClick = function() togglePlayersMenu() end },
			{ id = "players", label = "PLAYERS", onClick = function()
				m:clearContent()
				local body = m:content()
				local info = lobbyState.members or { members = {} }
				local isHost = info.hostId == player.UserId
				Menu.heading(body, "PLAYERS")
				for _, mem in info.members do
					local row = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), ZIndex = 306, Parent = body })
					local tag = if mem.userId == info.hostId then "  👑" elseif mem.userId == player.UserId then "  (you)" else ""
					Make.label(mem.name .. tag, 16, { Font = Theme.fontBody, TextColor3 = Theme.ink, Size = UDim2.new(1, -110, 1, 0), TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 306, Parent = row })
					if isHost and mem.userId ~= player.UserId then
						Menu.button(row, "REMOVE", Theme.cream, function()
							Net.remote:FireServer(Net.C2S.KickPlayer, mem.userId)
						end, { Size = UDim2.fromOffset(100, 28), TextSize = 14, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0) })
					end
				end
				if not isHost then Menu.text(body, "Only the host can remove players.", 13, true) end
			end },
			{ id = "settings", label = "SETTINGS", onClick = function()
				m:settingsPage(function() scale.Scale = uiScale() end)
			end },
			{ id = "leave", label = "LEAVE MATCH", accent = true, onClick = function()
				Net.remote:FireServer(Net.C2S.LeaveRoom)
				togglePlayersMenu()
			end },
		},
		onClose = function()
			pauseMenu = nil
			if inMatch then matchRoot.Visible = true end
		end,
	})
	pauseMenu = m
end

local function buildChrome()
fitColumn()
	local compact = Responsive.isCompact()
	chromeCompact = compact
	if hud then hud:destroy() end
	if lobby then lobby:destroy() end
	if content then content:Destroy() end

	local padding = column:FindFirstChildOfClass("UIPadding") or Make("UIPadding", { Parent = column })
	local p = if compact then 10 else 16
	padding.PaddingTop = UDim.new(0, p)
	padding.PaddingBottom = UDim.new(0, p)
	padding.PaddingLeft = UDim.new(0, p)
	padding.PaddingRight = UDim.new(0, p)

	hud = Hud.new(column)
	hud.players.Activated:Connect(function() togglePlayersMenu() end)
	local topInset, bottomInset = hud:contentInsets()
	content = Make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -(topInset + bottomInset)),
		Position = UDim2.new(0, 0, 0, topInset),
		Parent = column,
	})

	lobby = Lobby.new(gui)
	lobby.onUiScale = function() scale.Scale = uiScale() end
	if lobbyState.init then lobby:setInit(lobbyState.init) end
	lobby:setRooms(lobbyState.rooms)
	lobby:setRoom(lobbyState.room)
	lobby:setPad(lobbyState.pad)
	lobby:setVisible(not inMatch)
end

buildChrome()

----------------------------------------------------------------------------
-- Match / lobby switching

local setOverlay -- defined below
local current: any = nil
local function setInMatch(active: boolean)
	if inMatch == active then return end
	inMatch = active
	matchRoot.Visible = active
	lobby:setVisible(not active)
	Controls.setGameplayEnabled(not active)
	if active and not current and setOverlay then
		setOverlay("Setting up your match")
	end
end

----------------------------------------------------------------------------
-- Briefing card: tells you your job at the start of each phase.

local function briefing(title: string, text: string)
	local card = Make("Frame", {
		BackgroundColor3 = Theme.accent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(0, 460, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 50,
		Make.corner(UDim.new(0, 16)),
		Make.pad(24),
		Make.list(nil, 8, Enum.HorizontalAlignment.Center),
		Make("UISizeConstraint", { MaxSize = Vector2.new(Responsive.viewport().X - 32, math.huge) }),
		Parent = matchRoot,
	})
	Make.label("YOUR JOB", 12, { TextColor3 = Theme.bg, TextXAlignment = Enum.TextXAlignment.Center, Parent = card })
	Make.heading(title, 30, { TextColor3 = Theme.bg, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = card })
	Make.label(text, 16, { TextColor3 = Theme.bg, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = card })
	local close = Make.button("Got it", Theme.bg, function() card:Destroy() end, { Size = UDim2.new(0, 140, 0, 40), Parent = card })
	close.TextColor3 = Theme.accent
	task.delay(Config.PHASE_BRIEFING_SECONDS, function()
		if card.Parent then
			local tween = TweenService:Create(card, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
			for _, d in card:GetDescendants() do
				if d:IsA("TextLabel") or d:IsA("TextButton") then
					TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
				end
			end
			tween:Play()
			tween.Completed:Wait()
			card:Destroy()
		end
	end)
end

----------------------------------------------------------------------------
-- Screen mounting

local autoSubmitThread: thread? = nil

local ctx = {
	hud = nil :: any,
	markDirty = function() hud:unmarkSubmitted() end,
	partyMembers = function()
		if lobbyState.members then return lobbyState.members.members end
		if lobbyState.room then return lobbyState.room.members end
		return {}
	end,
}

local function unmount()
	if autoSubmitThread then
		task.cancel(autoSubmitThread)
		autoSubmitThread = nil
	end
	if current then
		current.destroy()
		current = nil
	end
	hud.onSubmit = nil
end

local function submitCurrent()
	if not current or not current.collect then return end
	Net.remote:FireServer(current.submitAction or Net.C2S.Submit, current.collect())
	hud:markSubmitted()
end

local function mount(screenFn: (Frame, any, any) -> any, data: any, endsAt: number?)
	setInMatch(true)
	unmount()
	setOverlay(nil)
	ctx.hud = hud
	current = screenFn(content, data, ctx)
	if current.collect then
		hud.onSubmit = submitCurrent
		if endsAt then
			local delay = math.max(0, endsAt - workspace:GetServerTimeNow() - 0.5)
			autoSubmitThread = task.delay(delay, function()
				if current and not hud.submitted then submitCurrent() end
			end)
		end
	end
end

local PHASE_SCREENS: { [string]: (Frame, any, any) -> any } = {
	premise = TextPhases.premise,
	cast = TextPhases.cast,
	claim = Claim.show,
	script = TextPhases.script,
	caption = TextPhases.caption,
	scenes = TextPhases.scenes,
	draw = Draw.show,
	dub = Dub.show,
	wait = Wait.show,
}

----------------------------------------------------------------------------
-- Teleport / gathering overlay (private match servers)

local overlay: Frame? = nil
local overlayLabel: TextLabel? = nil
local overlayStyle: string? = nil
-- style: nil = match loading (party on stage); "join" = first screen after joining,
-- big title and your avatar waiting against a wall at the side.
function setOverlay(message: string?, style: string?)
	if not message then
		if overlay then
			local old = overlay
			overlay = nil overlayLabel = nil overlayStyle = nil
			-- Out: text and avatar fade, the slash sweeps away, the ink lifts.
			local IN = Enum.EasingDirection.In
			for _, c in old:GetChildren() do
				if c:IsA("TextLabel") or c:IsA("TextButton") then
					TweenService:Create(c, TweenInfo.new(0.25, Enum.EasingStyle.Quint, IN), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
				elseif c.Name == "Slash" then
					TweenService:Create(c, TweenInfo.new(0.35, Enum.EasingStyle.Quint, IN), { Position = c.Position - UDim2.fromScale(0.9, 0) }):Play()
				elseif c.Name == "StageHolder" then
					local vp = c:FindFirstChildOfClass("ViewportFrame")
					if vp then TweenService:Create(vp, TweenInfo.new(0.3, Enum.EasingStyle.Quint, IN), { ImageTransparency = 1 }):Play() end
				end
			end
			TweenService:Create(old, TweenInfo.new(0.4, Enum.EasingStyle.Quint, IN), { BackgroundTransparency = 1 }):Play()
			task.delay(0.42, function() old:Destroy() end)
		end
		return
	end
	if overlay and overlayLabel and overlayStyle == style then
		overlayLabel.Text = message
		return
	end
	if overlay then overlay:Destroy() overlay = nil overlayLabel = nil end
	overlayStyle = style
	local join = style == "join"
	local compact = Responsive.isCompact()
	overlay = Make("Frame", { BackgroundColor3 = Theme.ink, Size = UDim2.fromScale(1, 1), ZIndex = 200, Active = true, Parent = gui })
	Make.coverInset(overlay, Responsive.inset())
	-- the slash, as in every menu
	local slash = Make("Frame", {
		Name = "Slash", BackgroundColor3 = Theme.inkSoft, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(-0.6, 0.5),
		Size = UDim2.new(0.42, 0, 2.6, 0), Rotation = if compact then 0 else 14, ZIndex = 201, Parent = overlay,
	})
	TweenService:Create(slash, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.22, 0.5) }):Play()
	-- Compact: title top-left, text under it, avatar on the right half.
	local title = Make.label(if join then "DUBBLE TAKE" else "LOADING", if compact then 40 elseif join then 84 else 96, {
		Font = Theme.fontDisplay, TextColor3 = Theme.cream, TextXAlignment = if compact then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
		AnchorPoint = if compact then Vector2.new(0, 0) else Vector2.new(0.5, 0.5), Rotation = if compact then 0 else -90,
		Position = if compact then UDim2.new(0, 24, 0, 10) else UDim2.fromScale(0.07, 0.5),
		Size = if compact then UDim2.new(0.5, 0, 0, 48) else UDim2.fromOffset(math.floor(Responsive.viewport().Y * 0.86), 120),
		ZIndex = 202, TextTransparency = 1, Parent = overlay,
	})
	TweenService:Create(title, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
	overlayLabel = Make.label(message, if compact then 17 else 20, {
		Font = Theme.fontBody, TextColor3 = Theme.cream, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Position = if compact then UDim2.new(0, 26, 0, 66) else UDim2.fromScale(0.18, 0.42),
		Size = if compact then UDim2.new(0.45, 0, 0, 24) else UDim2.new(0, 520, 0, 80), ZIndex = 202, Parent = overlay,
	})
	-- animated dots
	task.spawn(function()
		local n = 0
		while overlay and overlayLabel and overlay.Parent do
			n = (n % 3) + 1
			local base = overlayLabel.Text:gsub("%.+$", "")
			overlayLabel.Text = base .. string.rep(".", n)
			task.wait(0.5)
		end
	end)
	if join then
		-- Just you, waiting against a wall at the right edge of the screen
		local stageHolder = Make("Frame", {
			Name = "StageHolder", BackgroundTransparency = 1, ZIndex = 201,
			Position = if compact then UDim2.fromScale(0.76, 0.55) else UDim2.fromScale(0.8, 0.56),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = if compact then UDim2.fromScale(0.5, 1) else UDim2.fromScale(0.42, 0.92),
			Parent = overlay,
		})
		local stage = AvatarStage.new(stageHolder, { mode = "lean" })
		overlay.Destroying:Connect(function() stage:destroy() end)
		Make.label("write it  ·  draw it  ·  dub it", 18, {
			Font = Theme.fontBody, TextColor3 = Theme.creamDark, TextXAlignment = Enum.TextXAlignment.Left,
			Position = if compact then UDim2.new(0, 26, 0, 94) else UDim2.fromScale(0.18, 0.49),
			Size = if compact then UDim2.new(0.45, 0, 0, 24) else UDim2.new(0, 520, 0, 30), ZIndex = 202, Parent = overlay,
		})
		return
	end
	-- The party (or just you) on stage, right side
	local stageHolder = Make("Frame", {
		Name = "StageHolder", BackgroundTransparency = 1, ZIndex = 201,
		Position = if compact then UDim2.fromScale(0.68, 0.6) else UDim2.fromScale(0.68, 0.55),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = if compact then UDim2.fromScale(0.64, 0.95) else UDim2.fromScale(0.6, 0.9),
		Parent = overlay,
	})
	local stage = AvatarStage.new(stageHolder, { mode = "party" })
	local members = ctx.partyMembers()
	local n = 0
	for _, m in members do
		local p = Players:GetPlayerByUserId(m.userId)
		if p then n += 1 task.delay(0.3 * n, function() if stageHolder.Parent then stage:addPlayer(p) end end) end
	end
	if n == 0 then stage:addPlayer(player) end
	overlay.Destroying:Connect(function() stage:destroy() end)

	-- MENU button at the side (opens settings / leave)
	Make.button("MENU", Theme.cream, function() togglePlayersMenu() end, {
		Font = Theme.fontDisplay, TextSize = 22, TextColor3 = Theme.ink, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 24), Size = UDim2.fromOffset(110, 46), ZIndex = 202,
		Make("UIStroke", { Color = Theme.ink, Thickness = 2 }), Parent = overlay,
	})
end

-- The join screen stays up at least this long, and until your character has
-- loaded, so the avatar on it is actually seen.
local JOIN_MIN_SECONDS = 2.5
local joinShownAt = 0
local function dismissJoinScreen()
	task.spawn(function()
		local deadline = os.clock() + 6
		while os.clock() < deadline and not (player.Character and player.Character:FindFirstChild("HumanoidRootPart")) do task.wait(0.1) end
		local left = JOIN_MIN_SECONDS - (os.clock() - joinShownAt)
		if left > 0 then task.wait(left) end
		if overlayStyle == "join" then setOverlay(nil) end
	end)
end

----------------------------------------------------------------------------
-- Server messages

local handlers: { [string]: (any) -> () } = {
	[Net.S2C.LobbyInit] = function(data)
		lobbyState.init = data
		lobby:setInit(data)
		if not data.isMatchServer and not inMatch then
			if overlayStyle == "join" then dismissJoinScreen() else setOverlay(nil) end
		end
		if data.isMatchServer then
			-- We're on a private match server: no hub UI, just wait for the round.
			setInMatch(true)
		end
	end,
	[Net.S2C.Points] = function(data) lobby:setPoints(data.total or 0) end,
	[Net.S2C.Teleporting] = function(data) setOverlay(if data then data.message else nil) end,
	[Net.S2C.RoomState] = function(data)
		lobbyState.room = data
		lobby:setRoom(data)
		if data and data.state == "playing" and not inMatch then
			setInMatch(true)
			setOverlay("Setting up your match")
		end
	end,
	[Net.S2C.LiveStroke] = function(data)
		if current and current.onLiveStroke then current.onLiveStroke(data) end
	end,
	[Net.S2C.RoomList] = function(data) lobbyState.rooms = data.rooms or {} lobby:setRooms(lobbyState.rooms) end,
	[Net.S2C.PadState] = function(data) lobbyState.pad = data lobby:setPad(data) end,

	[Net.S2C.Phase] = function(data)
		setOverlay(nil)
		local screen = PHASE_SCREENS[data.kind]
		if not screen then return end
		mount(screen, data.payload, data.endsAt)
		hud:set(data.title, data.instructions, data.endsAt, current.collect ~= nil)
		if data.kind ~= "wait" then
			briefing(data.title, data.instructions)
		end
	end,
	[Net.S2C.RoomMembers] = function(data) lobbyState.members = data end,
	[Net.S2C.SkipState] = function(data)
		if current and current.onSkipState then current.onSkipState(data) end
	end,
	[Net.S2C.ClaimState] = function(data)
		if current and current.onClaimState then current.onClaimState(data) end
	end,
	[Net.S2C.Showcase] = function(data) setOverlay(nil) mount(Showcase.show, data, nil) end,
	[Net.S2C.ShowcaseFocus] = function(data)
		if current and current.focus then current.focus(data.projectIndex, data.frameIndex, data.lineIndex, data.endsAt) end
	end,
	[Net.S2C.Vote] = function(data) mount(Vote.show, data, data.endsAt) end,
	[Net.S2C.Results] = function(data) mount(Results.show, data, nil) end,
	[Net.S2C.MatchEnd] = function()
		setOverlay(nil)
		if pauseMenu then togglePlayersMenu() end
		unmount()
		setInMatch(false)
	end,
	[Net.S2C.SubmitAck] = function() hud:markSubmitted() end,
	[Net.S2C.Toast] = function(data) showToast(tostring(data)) end,
}

Net.remote.OnClientEvent:Connect(function(action: string, data: any)
	local handler = handlers[action]
	if handler then handler(data) end
end)

-- Loading from the first frame until the hub answers, and for at least a
-- couple of seconds so the join screen (and your avatar) are actually seen.
joinShownAt = os.clock()
setOverlay("Loading", "join")
Net.remote:FireServer(Net.C2S.Hello)

-- Resize / rotate: rescale, and rebuild the chrome if the layout class changed.
-- Phase screens keep their layout until the next phase so nobody loses typed text.
Responsive.onChanged(function()
	if not Responsive.ready() then return end
	scale.Scale = uiScale()
	fitColumn()
	if Responsive.isCompact() ~= chromeCompact and not current then
		buildChrome()
	end
end)

-- Esc / Start opens the pause menu during a match.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if inMatch and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonStart or input.KeyCode == Enum.KeyCode.P) then
		togglePlayersMenu()
	end
end)

-- Screenshot tour in Studio: press F8 or type /tour in chat (see scripts/capture.ps1)
if game:GetService("RunService"):IsStudio() then
	local Tour = require(Screens.Tour)
	local touring = false
	local function startTour()
		if touring then return end
		touring = true
		local camera = workspace.CurrentCamera
		local savedType = camera and camera.CameraType
		task.spawn(function()
			local ok, err = pcall(Tour.run, {
				mount = mount, unmount = unmount, hud = hud, lobby = lobby, setOverlay = setOverlay,
				togglePause = togglePlayersMenu, isPaused = function() return pauseMenu ~= nil end,
				setInMatch = setInMatch, gui = gui,
				screens = { premise = TextPhases.premise, cast = TextPhases.cast, claim = Claim.show, draw = Draw.show, dub = Dub.show, showcase = Showcase.show, vote = Vote.show, results = Results.show },
				currentScreen = function() return current end,
				setCamera = function(cf: CFrame)
					local cam = workspace.CurrentCamera
					if cam then cam.CameraType = Enum.CameraType.Scriptable cam.CFrame = cf end
				end,
				resetCamera = function()
					local cam = workspace.CurrentCamera
					if cam then cam.CameraType = savedType or Enum.CameraType.Custom end
				end,
			})
			if not ok then warn("TOUR failed:", err) end
			touring = false
		end)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F8 then startTour() end
	end)
	pcall(function()
		local TextChatService = game:GetService("TextChatService")
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "TourCommand"
		cmd.PrimaryAlias = "/tour"
		cmd.Triggered:Connect(function() startTour() end)
		cmd.Parent = TextChatService
	end)
	print("[DubbleTake] Tour ready: press F8 or type /tour")
end

player.CharacterAdded:Connect(function()
	task.wait(0.5)
	Controls.setGameplayEnabled(not inMatch)
end)
