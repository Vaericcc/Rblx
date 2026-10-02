--!strict
-- Entry point: builds the hub, routes client messages to Rooms, keeps room lists fresh.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Modes = require(Shared.Modes)
local Net = require(Shared.Net)
local Hub = require(script.Parent.Hub)

-- A reserved server with no owner is one of our private match servers.
local isMatchServer = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
if isMatchServer then
	Hub.build()
	require(script.Parent.MatchServer).init()
	return
end

local Rooms = require(script.Parent.Rooms)
local Pads = require(script.Parent.Pads)
local Points = require(script.Parent.Points)

local function modeList()
	local list = {}
	for _, mode in Modes.list do
		table.insert(list, {
			id = mode.id,
			name = mode.name,
			tagline = mode.tagline,
			description = mode.description,
			minPlayers = Config.playersNeeded(mode.minPlayers),
		})
	end
	return list
end

local LOBBY_INIT = {
	modes = modeList(),
	minPlayers = Config.MIN_PLAYERS,
	liveMinPlayers = if Config.SOLO_TESTING then 2 else Config.MIN_PLAYERS, -- what the published game requires
	maxPlayers = Config.MAX_PLAYERS,
}

local handlers: { [string]: (Player, any) -> () } = {
	[Net.C2S.Hello] = function(player)
		local init = table.clone(LOBBY_INIT)
		init.voiceEnabled = Rooms.hasVoice(player)
		init.voiceMessage = Rooms.VOICE_MESSAGE
		init.proPoints = Config.PRO_POINTS
		Net.remote:FireClient(player, Net.S2C.LobbyInit, init)
		Points.push(player)
		local room = Rooms.roomOf(player)
		if room then
			Net.remote:FireClient(player, Net.S2C.RoomState, Rooms.serialize(room))
		else
			Rooms.pushListTo(player)
		end
	end,
	[Net.C2S.CreateRoom] = function(player, data)
		local visibility = if typeof(data) == "table" then data.visibility else "public"
		Rooms.create(player, tostring(visibility))
	end,
	[Net.C2S.JoinRoom] = function(player, data)
		Rooms.join(player, data)
	end,
	[Net.C2S.LeaveRoom] = function(player)
		Rooms.leave(player)
	end,
	[Net.C2S.StartRoom] = function(player)
		Rooms.requestStart(player)
	end,
	[Net.C2S.VoteMode] = function(player, data)
		Rooms.voteMode(player, data)
	end,
	[Net.C2S.SetTeamMode] = function(player, data)
		Rooms.setTeamMode(player, data)
	end,
	[Net.C2S.PickTeam] = function(player, data)
		Rooms.pickTeam(player, data)
	end,
	[Net.C2S.Submit] = function(player, data)
		Rooms.onSubmit(player, data)
	end,
	[Net.C2S.Claim] = function(player, data)
		Rooms.onRoundAction(player, Net.C2S.Claim, data)
	end,
	[Net.C2S.ShowcaseNext] = function(player, data)
		Rooms.onRoundAction(player, Net.C2S.ShowcaseNext, data)
	end,
	[Net.C2S.SkipStory] = function(player, data)
		Rooms.onRoundAction(player, Net.C2S.SkipStory, data)
	end,
	[Net.C2S.Stroke] = function(player, data)
		Rooms.onRoundAction(player, Net.C2S.Stroke, data)
	end,
	[Net.C2S.KickPlayer] = function(player, data)
		Rooms.kick(player, data)
	end,
	-- Net.C2S.Vote is consumed by the Round during its vote window.
}

Net.remote.OnServerEvent:Connect(function(player, action, data)
	local handler = if typeof(action) == "string" then handlers[action] else nil
	if handler then
		handler(player, data)
	end
end)

Players.PlayerRemoving:Connect(Rooms.onPlayerRemoving)

Hub.build()
Pads.init()

-- Periodic refresh so the room browser never goes stale.
task.spawn(function()
	while true do
		task.wait(Config.ROOM_LIST_REFRESH_SECONDS)
		Rooms.pushListToAll()
	end
end)
