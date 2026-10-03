--!strict
--[[
	UI tour for screenshots (Studio only). Press F8: after a 10-second on-screen
	countdown, every screen is shown with sample data for 5 seconds each, with a
	label in the corner, and "TOUR: <step>" printed to Output. Pair it with
	scripts/capture.ps1, which grabs the screen on the same cadence.
]]
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Modes = require(Shared.Modes)
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)

local Tour = {}

Tour.STEP_SECONDS = 5
Tour.COUNTDOWN = 10

local function smiley(): { any }
	local pts = {}
	for i = 0, 40 do
		local a = i / 40 * math.pi * 2
		table.insert(pts, 0.5 + math.cos(a) * 0.3)
		table.insert(pts, 0.5 + math.sin(a) * 0.3)
	end
	local mouth = {}
	for i = 0, 16 do
		local a = math.rad(20 + i / 16 * 140)
		table.insert(mouth, 0.5 + math.cos(a) * 0.17)
		table.insert(mouth, 0.5 + math.sin(a) * 0.17)
	end
	local air = {}
	for i = 0, 30 do
		table.insert(air, 0.1 + i / 30 * 0.8)
		table.insert(air, 0.88 + math.sin(i / 3) * 0.04)
	end
	return {
		{ t = "r", c = { 0.37, 0.59, 1 }, w = 8, a = 1, f = true, fc = { 1, 0.86, 0.24 }, p = { 0.08, 0.08, 0.3, 0.3 } },
		{ t = "p", c = { 0.08, 0.08, 0.08 }, w = 10, a = 1, p = pts },
		{ t = "p", c = { 0.08, 0.08, 0.08 }, w = 12, a = 1, p = { 0.4, 0.42, 0.4, 0.42 } },
		{ t = "p", c = { 0.08, 0.08, 0.08 }, w = 12, a = 1, p = { 0.6, 0.42, 0.6, 0.42 } },
		{ t = "p", c = { 0.08, 0.08, 0.08 }, w = 9, a = 1, p = mouth },
		{ t = "p", c = { 0.9, 0.24, 0.24 }, w = 60, a = 0.6, s = true, p = air },
		{ t = "c", c = { 0.3, 0.8, 0.35 }, w = 6, a = 0.8, f = false, p = { 0.7, 0.1, 0.92, 0.32 } },
	}
end

local function sampleProject()
	local me = Players.LocalPlayer
	return {
		index = 1,
		ownerName = me.DisplayName,
		premise = { title = "The Last Slice", logline = "Two roommates, one pizza slice, no witnesses.", authorName = me.DisplayName },
		cast = { { name = "Milo", trait = "lies constantly" }, { name = "Juniper", trait = "can smell fear" } },
		roles = { Milo = { userId = me.UserId, name = me.DisplayName }, Juniper = { userId = me.UserId, name = me.DisplayName } },
		panels = { { strokes = smiley(), authorId = me.UserId, authorName = me.DisplayName } },
		lines = {
			{ panel = 1, character = "Milo", text = "I didn't touch it.", authorId = me.UserId, authorName = me.DisplayName, source = "dub" },
			{ panel = 1, character = "Juniper", text = "You're chewing.", authorId = me.UserId, authorName = me.DisplayName, source = "dub" },
		},
		captions = {},
		scenes = {},
		dubberName = me.DisplayName,
		frames = {
			{ kind = "title", blind = false, seconds = 4 },
			{ kind = "panel", panel = 1, seconds = 10, lines = {
				{ character = "Milo", text = "I didn't touch it.", actorId = me.UserId, actorName = me.DisplayName },
				{ character = "Juniper", text = "You're chewing.", actorId = me.UserId, actorName = me.DisplayName },
			} },
		},
	}
end

local function sampleRoom()
	local me = Players.LocalPlayer
	return {
		id = "ui_tour", kind = "ui", hostId = me.UserId, hostName = me.DisplayName, visibility = "friends",
		members = { { userId = me.UserId, name = me.DisplayName, vote = "classic" }, { userId = 1, name = "Roblox", vote = "comic" } },
		votes = { classic = 1, comic = 1 }, likelyModeId = "classic", state = "waiting", minPlayers = 2, maxPlayers = 10,
		teamMode = "random", teams = {}, teamColors = {}, teamCount = 2,
	}
end

-- api: { mount, unmount, hud, lobby, setOverlay, togglePause, setInMatch, screens, gui, setCamera, resetCamera }
function Tour.run(api: any)
	local me = Players.LocalPlayer
	local label = Make.label("", 20, {
		Font = Theme.fontDisplay, TextColor3 = Theme.cream, BackgroundColor3 = Theme.pop,
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.new(0, 0, 0, 36), AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 1000,
		Make.corner(UDim.new(0, 6)), Make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
		Make("UIStroke", { Color = Theme.ink, Thickness = 3 }), Parent = api.gui,
	})
	local function say(step: string)
		label.Text = ("TOUR  ·  %s"):format(step)
		print("TOUR: " .. step)
	end
	for i = Tour.COUNTDOWN, 1, -1 do
		label.Text = ("TOUR starts in %d  ·  switch to this window"):format(i)
		task.wait(1)
	end

	local project = sampleProject()
	local room = sampleRoom()
	local endsAt = function() return workspace:GetServerTimeNow() + 90 end
	local function hold() task.wait(Tour.STEP_SECONDS) end

	-- Hub shots
	api.setInMatch(false)
	api.lobby:closeMenu()
	api.setCamera(CFrame.lookAt(Vector3.new(0, 150, 150), Vector3.new(0, 0, 0))) say("hub overhead") hold()
	api.setCamera(CFrame.lookAt(Vector3.new(0, 7, 14), Vector3.new(0, 10, -60))) say("hub from dais") hold()
	api.setCamera(CFrame.lookAt(Vector3.new(0, 5, -40), Vector3.new(0, 8, -70))) say("hub gateway") hold()
	api.resetCamera()

	-- Menus
	api.lobby.page = "join" api.lobby:openMenu() say("menu join") hold()
	api.lobby.page = "create" api.lobby:render() say("menu create") hold()
	api.lobby:setRoom(room) api.lobby.page = "room" api.lobby.roomTab = "vote" api.lobby:render() say("menu room") hold()
	api.lobby.roomTab = "players" api.lobby:render() say("menu room players") hold()
	api.lobby.page = "settings" api.lobby:render() say("menu settings") hold()
	api.lobby:closeMenu() api.lobby:setRoom(nil)

	-- Match screens
	api.setInMatch(true)
	api.setOverlay("Gathering your party... 1/4") say("loading") hold()
	api.setOverlay(nil)
	local S = api.screens
	local function phase(kind: string, title: string, instructions: string, payload: any)
		api.mount(S[kind], payload, endsAt())
		api.hud:set(title, instructions, endsAt(), true)
		say(kind) hold()
	end
	phase("premise", "WRITE YOUR PREMISE", "Give your story a title and a one-sentence hook.", { projectIndex = 1 })
	phase("cast", "CREATE THE CAST", "Invent the characters.", { projectIndex = 1, premise = project.premise, count = 2 })
	phase("claim", "CLAIM YOUR ROLES", "Pick the characters you'll voice.", {
		projects = { { index = 1, ownerId = 2, ownerName = "Roblox", title = project.premise.title, logline = project.premise.logline, cast = project.cast } },
		roles = { ["1"] = { Milo = { userId = me.UserId, name = me.DisplayName } } }, maxRoles = 2, shared = false,
	})
	phase("draw", "DRAW!", "Bring the story to life.", { projectIndex = 1, panels = 1, startIndex = 1, premise = project.premise, cast = project.cast, roles = project.roles, lines = {}, ownerName = me.DisplayName })
	-- put sample art on the canvas via the mounted screen if it exposes one; otherwise shown in the dub step
	phase("dub", "WRITE YOUR LINES", "Write what your characters say.", { projects = { (function() local p = table.clone(project) p.myRoles = { "Milo", "Juniper" } return p end)() } })
	api.mount(S.showcase, { modeId = "classic", liveDub = true, lineSeconds = 7, projects = { project } }, nil)
	local cur = api.currentScreen()
	if cur and cur.focus then cur.focus(1, 2, 1, workspace:GetServerTimeNow() + 7) end
	say("showcase") hold()
	api.mount(S.vote, { awards = {
		{ id = "funniest", name = "Funniest", emoji = "😂" }, { id = "best_art", name = "Best Art", emoji = "🎨" },
		{ id = "best_dub", name = "Best Dub", emoji = "🎤" }, { id = "plot_twist", name = "Plot Twist", emoji = "🌀" } },
		projects = { { index = 1, title = project.premise.title, ownerName = "Roblox", actors = { me.DisplayName }, thumbnail = smiley() },
			{ index = 2, title = "Pigeon Court", ownerName = "Builderman", actors = { "Roblox" }, thumbnail = smiley() } },
		mine = {}, endsAt = endsAt() }, endsAt())
	say("vote") hold()
	api.mount(S.results, { board = { { userId = me.UserId, name = me.DisplayName, score = 325 }, { userId = 1, name = "Roblox", score = 200 } },
		winners = { funniest = { projectIndex = 1, votes = 2, title = project.premise.title } },
		awards = { { id = "funniest", name = "Funniest", emoji = "😂" }, { id = "best_art", name = "Best Art", emoji = "🎨" } }, endsAt = endsAt() }, nil)
	say("results") hold()
	api.togglePause() say("pause menu") hold()
	api.togglePause()
	api.unmount()
	api.setInMatch(false)
	say("done")
	task.wait(2)
	label:Destroy()
	print("TOUR: finished")
end

return Tour
