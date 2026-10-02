--!strict
-- Entry point: builds the hub, routes client messages to Rooms, keeps room lists fresh.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Modes = require(Shared.Modes)
local Net = require(Shared.Net)
local Rooms = require(script.Parent.Rooms)
local Pads = require(script.Parent.Pads)

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
	maxPlayers = Config.MAX_PLAYERS,
}

local handlers: { [string]: (Player, any) -> () } = {
	[Net.C2S.Hello] = function(player)
		Net.remote:FireClient(player, Net.S2C.LobbyInit, LOBBY_INIT)
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
	[Net.C2S.Submit] = function(player, data)
		Rooms.onSubmit(player, data)
	end,
	[Net.C2S.Claim] = function(player, data)
		Rooms.onRoundAction(player, Net.C2S.Claim, data)
	end,
	[Net.C2S.ShowcaseNext] = function(player, data)
		Rooms.onRoundAction(player, Net.C2S.ShowcaseNext, data)
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

Pads.init()

-- Periodic refresh so the room browser never goes stale.
task.spawn(function()
	while true do
		task.wait(Config.ROOM_LIST_REFRESH_SECONDS)
		Rooms.pushListToAll()
	end
end)
