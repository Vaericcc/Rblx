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
local playerGui = player:WaitForChild("PlayerGui")

-- The camera reports a tiny viewport for a moment at startup; measuring then
-- would pick the phone layout on a desktop.
Responsive.waitUntilReady()

----------------------------------------------------------------------------
-- Root GUI

local gui = Make("ScreenGui", {
	Name = "StoryDub",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})
local scale = Make("UIScale", { Scale = Responsive.scale(), Parent = gui })

local matchRoot = Make("Frame", {
	BackgroundColor3 = Theme.bg,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	Active = true,
	Parent = gui,
})

-- Centered column that caps content width on wide screens.
local column = Make("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromScale(1, 1),
	Make("UISizeConstraint", { MaxSize = Vector2.new(Responsive.MAX_CONTENT_WIDTH, math.huge) }),
	Parent = matchRoot,
})

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

-- In-match players menu: who's here, and Remove buttons for the host.
local playersMenu: Frame? = nil
function togglePlayersMenu()
	if playersMenu then
		playersMenu:Destroy()
		playersMenu = nil
		return
	end
	local info = lobbyState.members
	if not info then return end
	local isHost = info.hostId == player.UserId
	local menu = Make.card({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 360, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 60,
		Make.list(nil, 6),
		Make("UIStroke", { Color = Theme.panelAlt, Thickness = 1 }),
		Parent = matchRoot,
	})
	playersMenu = menu
	Make.heading("Players", 18, { ZIndex = 61, Parent = menu })
	for _, m in info.members do
		local row = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), ZIndex = 61, Parent = menu })
		local tag = if m.userId == info.hostId then "  👑" elseif m.userId == player.UserId then "  (you)" else ""
		Make.label(m.name .. tag, 15, { Size = UDim2.new(1, -100, 1, 0), TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 62, Parent = row })
		if isHost and m.userId ~= player.UserId then
			Make.button("Remove", Theme.panelAlt, function()
				Net.remote:FireServer(Net.C2S.KickPlayer, m.userId)
				togglePlayersMenu()
			end, { Size = UDim2.fromOffset(90, 28), TextSize = 12, TextColor3 = Theme.danger, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), ZIndex = 62, Parent = row })
		end
	end
	if not isHost then
		Make.label("Only the host can remove players.", 12, { TextColor3 = Theme.textDim, ZIndex = 61, Parent = menu })
	end
	Make.button("Close", Theme.panelAlt, function() togglePlayersMenu() end, { Size = UDim2.new(1, 0, 0, 36), TextSize = 14, TextColor3 = Theme.text, ZIndex = 61, Parent = menu })
end

local function buildChrome()
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
	if lobbyState.init then lobby:setInit(lobbyState.init) end
	lobby:setRooms(lobbyState.rooms)
	lobby:setRoom(lobbyState.room)
	lobby:setPad(lobbyState.pad)
	lobby:setVisible(not inMatch)
end

buildChrome()

----------------------------------------------------------------------------
-- Match / lobby switching

local function setInMatch(active: boolean)
	if inMatch == active then return end
	inMatch = active
	matchRoot.Visible = active
	lobby:setVisible(not active)
	Controls.setGameplayEnabled(not active)
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

local current: any = nil
local autoSubmitThread: thread? = nil

local ctx = {
	hud = nil :: any,
	markDirty = function() hud:unmarkSubmitted() end,
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
	draw = Draw.show,
	dub = Dub.show,
	wait = Wait.show,
}

----------------------------------------------------------------------------
-- Server messages

local handlers: { [string]: (any) -> () } = {
	[Net.S2C.LobbyInit] = function(data) lobbyState.init = data lobby:setInit(data) end,
	[Net.S2C.RoomList] = function(data) lobbyState.rooms = data.rooms or {} lobby:setRooms(lobbyState.rooms) end,
	[Net.S2C.RoomState] = function(data) lobbyState.room = data lobby:setRoom(data) end,
	[Net.S2C.PadState] = function(data) lobbyState.pad = data lobby:setPad(data) end,

	[Net.S2C.Phase] = function(data)
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
	[Net.S2C.Showcase] = function(data) mount(Showcase.show, data, nil) end,
	[Net.S2C.ShowcaseFocus] = function(data)
		if current and current.focus then current.focus(data.projectIndex, data.frameIndex, data.lineIndex, data.endsAt) end
	end,
	[Net.S2C.Vote] = function(data) mount(Vote.show, data, data.endsAt) end,
	[Net.S2C.Results] = function(data) mount(Results.show, data, nil) end,
	[Net.S2C.MatchEnd] = function()
		if playersMenu then playersMenu:Destroy() playersMenu = nil end
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

Net.remote:FireServer(Net.C2S.Hello)

-- Resize / rotate: rescale, and rebuild the chrome if the layout class changed.
-- Phase screens keep their layout until the next phase so nobody loses typed text.
Responsive.onChanged(function()
	if not Responsive.ready() then return end
	scale.Scale = Responsive.scale()
	if Responsive.isCompact() ~= chromeCompact and not current then
		buildChrome()
	end
end)

player.CharacterAdded:Connect(function()
	task.wait(0.5)
	Controls.setGameplayEnabled(not inMatch)
end)
