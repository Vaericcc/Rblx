--!strict
--[[
	Rooms are the unit of matchmaking. A room is either:
		kind = "ui"   created from the matchmaking panel; host picks Public or Friends Only
		kind = "pad"  one per physical platform in the hub; membership is "standing on it"
	Every room runs its own Round, so many matches run at the same time.
]]
local Players = game:GetService("Players")
local VoiceChatService = game:GetService("VoiceChatService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Modes = require(Shared.Modes)
local Net = require(Shared.Net)
local Round = require(script.Parent.Round)
local Studios = require(script.Parent.Studios)
local VoiceIsolation = require(script.Parent.VoiceIsolation)

export type Room = {
	id: string,
	kind: string, -- "ui" | "pad"
	hostId: number,
	hostName: string,
	visibility: string, -- "public" | "friends"
	members: { Player },
	modeVotes: { [number]: string },
	state: string, -- "waiting" | "starting" | "playing"
	startsAt: number?,
	round: Round.Round?,
	padIndex: number?,
	banned: { [number]: boolean },
}

local Rooms = {}

local rooms: { [string]: Room } = {}
local roomOf: { [number]: Room } = {} -- userId -> room
local nextId = 0

-- Player:IsFriendsWith hits the web; cache per pair for the session.
local friendCache: { [string]: boolean } = {}
local function isFriend(a: Player, b: Player): boolean
	if a == b then return true end
	local key = ("%d:%d"):format(math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId))
	local cached = friendCache[key]
	if cached ~= nil then return cached end
	local ok, result = pcall(function() return a:IsFriendsWith(b.UserId) end)
	local value = ok and result == true
	friendCache[key] = value
	return value
end

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Voice chat eligibility, cached per player for the session.
local voiceCache: { [number]: boolean } = {}
local voiceWarnedAt: { [number]: number } = {}
function Rooms.hasVoice(player: Player): boolean
	if not Config.VOICE_REQUIRED then return true end
	local cached = voiceCache[player.UserId]
	if cached ~= nil then return cached end
	local ok, result = pcall(function()
		return VoiceChatService:IsVoiceEnabledForUserIdAsync(player.UserId)
	end)
	local value = ok and result == true
	voiceCache[player.UserId] = value
	return value
end

Rooms.VOICE_MESSAGE = "StoryDub is played with voice chat. Turn on voice chat in your Roblox settings, then rejoin."

local function warnNoVoice(player: Player)
	local last = voiceWarnedAt[player.UserId] or 0
	if now() - last < 10 then return end
	voiceWarnedAt[player.UserId] = now()
	if player.Parent then
		Net.remote:FireClient(player, Net.S2C.Toast, Rooms.VOICE_MESSAGE)
	end
end

local function fire(player: Player, action: string, data: any)
	if player.Parent then
		Net.remote:FireClient(player, action, data)
	end
end

----------------------------------------------------------------------------
-- Serialization

local function tallyVotes(room: Room): { [string]: number }
	local counts = {}
	for _, modeId in room.modeVotes do
		counts[modeId] = (counts[modeId] or 0) + 1
	end
	return counts
end

function Rooms.pickMode(room: Room): Modes.Mode
	local counts = tallyVotes(room)
	local best: Modes.Mode? = nil
	local bestCount = -1
	for _, mode in Modes.list do
		if #room.members < Config.playersNeeded(mode.minPlayers) then continue end
		local c = counts[mode.id] or 0
		if c > bestCount then
			best, bestCount = mode, c
		end
	end
	return best or Modes.list[1]
end

function Rooms.serialize(room: Room)
	local members = {}
	for _, p in room.members do
		table.insert(members, { userId = p.UserId, name = p.DisplayName, vote = room.modeVotes[p.UserId] })
	end
	local likely = Rooms.pickMode(room)
	return {
		id = room.id,
		kind = room.kind,
		padIndex = room.padIndex,
		hostId = room.hostId,
		hostName = room.hostName,
		visibility = room.visibility,
		members = members,
		votes = tallyVotes(room),
		likelyModeId = likely.id,
		state = room.state,
		startsAt = room.startsAt,
		minPlayers = Config.MIN_PLAYERS,
		maxPlayers = Config.MAX_PLAYERS,
	}
end

local function listEntry(room: Room, viewer: Player)
	return {
		id = room.id,
		hostName = room.hostName,
		visibility = room.visibility,
		memberCount = #room.members,
		maxPlayers = Config.MAX_PLAYERS,
		state = room.state,
		isFriend = room.hostId ~= viewer.UserId and room.visibility == "friends",
	}
end

----------------------------------------------------------------------------
-- Broadcasting

function Rooms.pushRoom(room: Room)
	local data = Rooms.serialize(room)
	for _, p in room.members do
		fire(p, Net.S2C.RoomState, data)
	end
end

-- Which UI rooms can this player see? Public ones, plus friends-only ones hosted by a friend.
function Rooms.visibleTo(viewer: Player): { any }
	local out = {}
	for _, room in rooms do
		if room.kind ~= "ui" then continue end
		local host = Players:GetPlayerByUserId(room.hostId)
		if not host then continue end
		if room.visibility == "public" or isFriend(viewer, host) then
			table.insert(out, listEntry(room, viewer))
		end
	end
	table.sort(out, function(a, b)
		if a.state ~= b.state then return a.state == "waiting" end
		return a.memberCount > b.memberCount
	end)
	return out
end

function Rooms.pushListTo(player: Player)
	fire(player, Net.S2C.RoomList, { rooms = Rooms.visibleTo(player) })
end

function Rooms.pushListToAll()
	for _, p in Players:GetPlayers() do
		if not roomOf[p.UserId] then
			Rooms.pushListTo(p)
		end
	end
end

----------------------------------------------------------------------------
-- Membership

function Rooms.roomOf(player: Player): Room?
	return roomOf[player.UserId]
end

local function newRoom(kind: string, host: Player, visibility: string): Room
	nextId += 1
	local room: Room = {
		id = ("%s_%d"):format(kind, nextId),
		kind = kind,
		hostId = host.UserId,
		hostName = host.DisplayName,
		visibility = visibility,
		members = {},
		modeVotes = {},
		state = "waiting",
		startsAt = nil,
		round = nil,
		padIndex = nil,
		banned = {},
	}
	rooms[room.id] = room
	return room
end

local function addMember(room: Room, player: Player)
	if roomOf[player.UserId] then return end
	table.insert(room.members, player)
	roomOf[player.UserId] = room
end

local function removeMember(room: Room, player: Player)
	local i = table.find(room.members, player)
	if i then table.remove(room.members, i) end
	room.modeVotes[player.UserId] = nil
	if roomOf[player.UserId] == room then
		roomOf[player.UserId] = nil
	end
end

local function destroyRoom(room: Room)
	for _, p in table.clone(room.members) do
		removeMember(room, p)
		fire(p, Net.S2C.RoomState, nil)
	end
	rooms[room.id] = nil
end

function Rooms.create(host: Player, visibility: string): Room?
	if not Rooms.hasVoice(host) then
		warnNoVoice(host)
		return nil
	end
	if roomOf[host.UserId] then
		fire(host, Net.S2C.Toast, "Leave your current room first.")
		return nil
	end
	if visibility ~= "friends" then visibility = "public" end
	local room = newRoom("ui", host, visibility)
	addMember(room, host)
	Rooms.pushRoom(room)
	Rooms.pushListToAll()
	return room
end

function Rooms.join(player: Player, roomId: any)
	local room = rooms[tostring(roomId)]
	if not room or room.kind ~= "ui" then
		fire(player, Net.S2C.Toast, "That room no longer exists.")
		return
	end
	if not Rooms.hasVoice(player) then
		warnNoVoice(player)
		return
	end
	if roomOf[player.UserId] then
		fire(player, Net.S2C.Toast, "Leave your current room first.")
		return
	end
	if room.state ~= "waiting" then
		fire(player, Net.S2C.Toast, "That room is already playing.")
		return
	end
	if #room.members >= Config.MAX_PLAYERS then
		fire(player, Net.S2C.Toast, "That room is full.")
		return
	end
	local host = Players:GetPlayerByUserId(room.hostId)
	if room.visibility == "friends" and (not host or not isFriend(player, host)) then
		fire(player, Net.S2C.Toast, "That room is friends only.")
		return
	end
	if room.banned[player.UserId] then
		fire(player, Net.S2C.Toast, "The host removed you from that room.")
		return
	end
	addMember(room, player)
	Rooms.pushRoom(room)
	Rooms.pushListToAll()
end

function Rooms.leave(player: Player)
	local room = roomOf[player.UserId]
	if not room then return end
	if room.state == "playing" then
		removeMember(room, player)
		if room.round then
			room.round:removePlayer(player)
			VoiceIsolation.release({ player })
			VoiceIsolation.isolate(room.round.players)
		end
		fire(player, Net.S2C.RoomState, nil)
		Rooms.pushMembers(room)
		return
	end
	removeMember(room, player)
	fire(player, Net.S2C.RoomState, nil)
	if room.kind == "ui" then
		if #room.members == 0 then
			destroyRoom(room)
		else
			-- Host migration
			if room.hostId == player.UserId then
				room.hostId = room.members[1].UserId
				room.hostName = room.members[1].DisplayName
			end
			Rooms.pushRoom(room)
		end
	else
		Rooms.pushRoom(room)
	end
	Rooms.pushListToAll()
	Rooms.pushListTo(player)
end

function Rooms.voteMode(player: Player, modeId: any)
	local room = roomOf[player.UserId]
	if not room or room.state == "playing" then return end
	if typeof(modeId) == "string" and Modes.byId[modeId] then
		room.modeVotes[player.UserId] = modeId
		Rooms.pushRoom(room)
	end
end

----------------------------------------------------------------------------
-- Pads: one room per physical platform, membership managed by Pads.lua

function Rooms.getOrCreatePadRoom(padIndex: number, firstPlayer: Player): Room
	for _, room in rooms do
		if room.kind == "pad" and room.padIndex == padIndex then
			return room
		end
	end
	local room = newRoom("pad", firstPlayer, "public")
	room.hostName = ("Platform %d"):format(padIndex)
	room.padIndex = padIndex
	return room
end

-- Called by the pad scanner with everyone currently standing on pad `padIndex`.
-- Returns the room (or nil if nobody is on it and none exists).
function Rooms.syncPad(padIndex: number, standing: { Player }): Room?
	local room: Room? = nil
	for _, r in rooms do
		if r.kind == "pad" and r.padIndex == padIndex then room = r end
	end
	if not room then
		if #standing == 0 then return nil end
		room = Rooms.getOrCreatePadRoom(padIndex, standing[1])
	end
	assert(room)
	if room.state == "playing" then
		return room
	end

	local changed = false
	-- Add newcomers who aren't in any room (and have voice chat)
	for _, p in standing do
		if not roomOf[p.UserId] and not Rooms.hasVoice(p) then
			warnNoVoice(p)
			continue
		end
		if not roomOf[p.UserId] and #room.members < Config.MAX_PLAYERS then
			addMember(room, p)
			changed = true
		end
	end
	-- Remove members who stepped off
	for _, p in table.clone(room.members) do
		if not table.find(standing, p) or not p.Parent then
			removeMember(room, p)
			fire(p, Net.S2C.RoomState, nil)
			fire(p, Net.S2C.PadState, nil)
			changed = true
		end
	end

	-- Countdown management
	if #room.members >= Config.MIN_PLAYERS then
		if room.state == "waiting" then
			room.state = "starting"
			room.startsAt = now() + Config.PAD_COUNTDOWN_SECONDS
			changed = true
		elseif room.startsAt and now() >= room.startsAt then
			Rooms.startMatch(room)
			return room
		end
	elseif room.state == "starting" then
		room.state = "waiting"
		room.startsAt = nil
		changed = true
	end

	if #room.members == 0 and room.state ~= "playing" then
		rooms[room.id] = nil
		return nil
	end
	if changed then
		local data = Rooms.serialize(room)
		for _, p in room.members do
			fire(p, Net.S2C.PadState, data)
		end
	end
	return room
end

----------------------------------------------------------------------------
-- Starting and running a match

function Rooms.requestStart(player: Player)
	local room = roomOf[player.UserId]
	if not room or room.kind ~= "ui" then return end
	if room.hostId ~= player.UserId then
		fire(player, Net.S2C.Toast, "Only the host can start.")
		return
	end
	if room.state ~= "waiting" then return end
	if #room.members < Config.MIN_PLAYERS then
		fire(player, Net.S2C.Toast, ("You need at least %d players."):format(Config.MIN_PLAYERS))
		return
	end
	Rooms.startMatch(room)
end

function Rooms.startMatch(room: Room)
	if room.state == "playing" then return end
	room.state = "playing"
	room.startsAt = nil
	local mode = Rooms.pickMode(room)
	local players = table.clone(room.members)
	Rooms.pushRoom(room)
	Rooms.pushListToAll()

	task.spawn(function()
		-- Private studio: only this group hears each other over proximity voice.
		local studio = Studios.acquire()
		Studios.enter(studio, players)
		local respawnConns = Studios.watchRespawns(studio, players)
		VoiceIsolation.isolate(players)
		for _, c in VoiceIsolation.watch(players) do table.insert(respawnConns, c) end

		local round = Round.new(mode, players)
		room.round = round
		Rooms.pushMembers(room)
		local ok, err = pcall(function()
			round:broadcast(Net.S2C.Toast, ("%s - %s"):format(mode.name, mode.tagline))
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
		room.round = nil
		for _, c in respawnConns do c:Disconnect() end
		VoiceIsolation.release(players)
		Studios.leave(players)
		Studios.release(studio)
		Rooms.endMatch(room)
	end)
end

function Rooms.endMatch(room: Room)
	room.state = "waiting"
	room.startsAt = nil
	room.modeVotes = {}
	for _, p in table.clone(room.members) do
		fire(p, Net.S2C.MatchEnd, nil)
		if room.kind == "pad" then
			fire(p, Net.S2C.PadState, nil)
		end
	end
	if room.kind == "pad" then
		-- Pad rooms dissolve; standing on the pad again re-forms one.
		destroyRoom(room)
	else
		if #room.members == 0 then
			destroyRoom(room)
		else
			Rooms.pushRoom(room)
		end
	end
	Rooms.pushListToAll()
end

function Rooms.onSubmit(player: Player, data: any)
	local room = roomOf[player.UserId]
	if room and room.round then
		room.round:onSubmit(player, data)
	end
end

-- Members list for the in-match players menu.
function Rooms.pushMembers(room: Room)
	local members = {}
	for _, p in room.members do
		table.insert(members, { userId = p.UserId, name = p.DisplayName })
	end
	for _, p in room.members do
		fire(p, Net.S2C.RoomMembers, { hostId = if room.kind == "ui" then room.hostId else nil, members = members })
	end
end

function Rooms.kick(host: Player, targetId: any)
	local room = roomOf[host.UserId]
	if not room or room.kind ~= "ui" or room.hostId ~= host.UserId then return end
	local id = tonumber(targetId)
	if not id or id == host.UserId then return end
	local target = Players:GetPlayerByUserId(id)
	if not target or roomOf[id] ~= room then return end

	room.banned[id] = true
	removeMember(room, target)
	if room.round then
		room.round:removePlayer(target)
		Studios.leave({ target })
		VoiceIsolation.release({ target })
		VoiceIsolation.isolate(room.round.players)
		fire(target, Net.S2C.MatchEnd, nil)
	end
	fire(target, Net.S2C.RoomState, nil)
	fire(target, Net.S2C.Toast, "The host removed you from the room.")
	Rooms.pushListTo(target)
	Rooms.pushRoom(room)
	Rooms.pushMembers(room)
	Rooms.pushListToAll()
end

function Rooms.onRoundAction(player: Player, action: string, data: any)
	local room = roomOf[player.UserId]
	if room and room.round then
		room.round:onAction(player, action, data)
	end
end

function Rooms.onPlayerRemoving(player: Player)
	Rooms.leave(player)
end

-- Members of playing rooms must not be grabbed by pads.
function Rooms.isBusy(player: Player): boolean
	local room = roomOf[player.UserId]
	return room ~= nil and room.kind == "ui"
end

return Rooms
