--!strict
-- Entry point: lobby -> mode vote -> round -> repeat forever.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Modes = require(Shared.Modes)
local Net = require(Shared.Net)
local Round = require(script.Parent.Round)

local currentRound: Round.Round? = nil
local modeVotes: { [number]: string } = {} -- userId -> modeId

local function now(): number
	return workspace:GetServerTimeNow()
end

local function modeList()
	local list = {}
	for _, mode in Modes.list do
		table.insert(list, {
			id = mode.id,
			name = mode.name,
			tagline = mode.tagline,
			description = mode.description,
			minPlayers = mode.minPlayers,
		})
	end
	return list
end

local function tallyModes(): { [string]: number }
	local counts = {}
	for _, modeId in modeVotes do
		counts[modeId] = (counts[modeId] or 0) + 1
	end
	return counts
end

local function broadcastLobby(endsAt: number?, status: string)
	Net.remote:FireAllClients(Net.S2C.Lobby, {
		players = #Players:GetPlayers(),
		minPlayers = Config.MIN_PLAYERS,
		modes = modeList(),
		votes = tallyModes(),
		endsAt = endsAt,
		status = status,
	})
end

-- Route client messages
Net.remote.OnServerEvent:Connect(function(player, action, data)
	if action == Net.C2S.VoteMode then
		if typeof(data) == "string" and Modes.byId[data] then
			modeVotes[player.UserId] = data
		end
	elseif action == Net.C2S.Submit then
		if currentRound then
			currentRound:onSubmit(player, data)
		end
	end
	-- Net.C2S.Vote is handled by the round during the vote window.
end)

Players.PlayerRemoving:Connect(function(player)
	modeVotes[player.UserId] = nil
end)

Players.PlayerAdded:Connect(function(player)
	-- Late joiners get a lobby screen immediately; they're folded into the next round.
	task.wait(1)
	if not currentRound then
		Net.remote:FireClient(player, Net.S2C.Lobby, {
			players = #Players:GetPlayers(),
			minPlayers = Config.MIN_PLAYERS,
			modes = modeList(),
			votes = tallyModes(),
			endsAt = nil,
			status = "waiting",
		})
	else
		Net.remote:FireClient(player, Net.S2C.Toast, "A round is in progress. You'll join the next one!")
	end
end)

local function pickMode(players: { Player }): Modes.Mode
	local counts = tallyModes()
	local best: Modes.Mode? = nil
	local bestCount = -1
	-- Only modes the current player count can run.
	for _, mode in Modes.list do
		if #players < mode.minPlayers then continue end
		local c = counts[mode.id] or 0
		if c > bestCount or (c == bestCount and best and math.random() < 0.5) then
			best = mode
			bestCount = c
		end
	end
	return best or Modes.list[1]
end

while true do
	-- Wait for enough players
	while #Players:GetPlayers() < Config.MIN_PLAYERS do
		broadcastLobby(nil, "waiting")
		task.wait(2)
	end

	-- Mode vote
	modeVotes = {}
	local voteEnds = now() + Config.LOBBY_VOTE_SECONDS
	while now() < voteEnds do
		broadcastLobby(voteEnds, "voting")
		task.wait(1)
		if #Players:GetPlayers() < Config.MIN_PLAYERS then break end
	end
	if #Players:GetPlayers() < Config.MIN_PLAYERS then continue end

	local players = Players:GetPlayers()
	if #players > Config.MAX_PLAYERS then
		players = { table.unpack(players, 1, Config.MAX_PLAYERS) }
	end
	local mode = pickMode(players)

	local round = Round.new(mode, players)
	currentRound = round
	local ok, err = pcall(function()
		round:broadcast(Net.S2C.Toast, ("Mode: %s - %s"):format(mode.name, mode.tagline))
		task.wait(Config.INTERMISSION_SECONDS)
		for _, phase in mode.phases do
			round:runPhase(phase)
			if #round.players == 0 then return end
		end
		round:showcase()
		local winners = round:vote()
		round:results(winners)
	end)
	if not ok then
		warn("[StoryDub] round crashed:", err)
	end
	round:destroy()
	currentRound = nil
end
