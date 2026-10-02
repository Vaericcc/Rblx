--!strict
--[[
	Runs on a reserved server that a hub created for one party.
	Players arrive carrying TeleportData { modeId, memberIds }. We wait for the
	party, run one round, then send everyone back to a public hub server.
	Being alone on the server is what makes the match private: no studios or
	access lists are needed here.
]]
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Modes = require(Shared.Modes)
local Net = require(Shared.Net)
local Round = require(script.Parent.Round)
local Points = require(script.Parent.Points)

local MatchServer = {}

local round: Round.Round? = nil
local expected: { [number]: boolean } = {}
local modeId: string? = nil
local started = false

local function teleportData(player: Player): any
	local ok, data = pcall(function()
		local join = player:GetJoinData()
		return join and join.TeleportData
	end)
	return if ok then data else nil
end

local function arrivedCount(): number
	local n = 0
	for _, p in Players:GetPlayers() do
		if expected[p.UserId] then n += 1 end
	end
	return n
end

local function expectedCount(): number
	local n = 0
	for _ in expected do n += 1 end
	return n
end

local function broadcast(action: string, data: any)
	for _, p in Players:GetPlayers() do
		Net.remote:FireClient(p, action, data)
	end
end

local function sendHome(players: { Player })
	if #players == 0 then return end
	pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, players)
	end)
end

local function run()
	if started then return end
	started = true
	local players = Players:GetPlayers()
	local mode = (modeId and Modes.byId[modeId]) or Modes.list[1]
	if #players < 1 then return end

	broadcast(Net.S2C.Teleporting, nil) -- clears the gathering screen
	local r = Round.new(mode, players)
	round = r
	local ok, err = pcall(function()
		r:broadcast(Net.S2C.Toast, ("%s - %s"):format(mode.name, mode.tagline))
		task.wait(Config.INTERMISSION_SECONDS)
		for _, phase in mode.phases do
			r:runPhase(phase)
			if #r.players == 0 then return end
		end
		r:showcase()
		local winners = r:vote()
		r:results(winners)
	end)
	if not ok then
		warn("[StoryDub] match server round crashed:", err)
	end
	r:destroy()
	round = nil
	broadcast(Net.S2C.MatchEnd, nil)
	broadcast(Net.S2C.Teleporting, { message = "Heading back to the hub..." })
	task.wait(1)
	sendHome(Players:GetPlayers())
end

local handlers: { [string]: (Player, any) -> () } = {
	[Net.C2S.Hello] = function(player)
		Net.remote:FireClient(player, Net.S2C.LobbyInit, {
			isMatchServer = true,
			modes = {},
			minPlayers = Config.MIN_PLAYERS,
			maxPlayers = Config.MAX_PLAYERS,
		})
		Net.remote:FireClient(player, Net.S2C.Teleporting, {
			message = ("Gathering your party... %d/%d"):format(arrivedCount(), math.max(expectedCount(), 1)),
		})
		Points.push(player)
	end,
	[Net.C2S.Submit] = function(player, data)
		if round then round:onSubmit(player, data) end
	end,
}
for _, action in { Net.C2S.Claim, Net.C2S.ShowcaseNext, Net.C2S.SkipStory, Net.C2S.Stroke } do
	handlers[action] = function(player, data)
		if round then round:onAction(player, action, data) end
	end
end

function MatchServer.init()
	Net.remote.OnServerEvent:Connect(function(player, action, data)
		local handler = if typeof(action) == "string" then handlers[action] else nil
		if handler then handler(player, data) end
	end)

	local function onPlayer(player: Player)
		local data = teleportData(player)
		if typeof(data) == "table" then
			modeId = modeId or data.modeId
			if typeof(data.memberIds) == "table" then
				for _, id in data.memberIds do
					if typeof(id) == "number" then expected[id] = true end
				end
			end
		end
		expected[player.UserId] = true
		broadcast(Net.S2C.Teleporting, {
			message = ("Gathering your party... %d/%d"):format(arrivedCount(), math.max(expectedCount(), 1)),
		})
		if not started and arrivedCount() >= expectedCount() and expectedCount() > 0 then
			task.delay(2, run)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do onPlayer(p) end

	-- Don't wait forever for stragglers.
	task.delay(Config.MATCH_SERVER_GATHER_SECONDS, function()
		if not started then
			if #Players:GetPlayers() >= 1 then
				run()
			end
		end
	end)

	-- If everyone leaves mid-match, the server simply empties and closes.
	Players.PlayerRemoving:Connect(function(player)
		if round then round:removePlayer(player) end
	end)
end

return MatchServer
