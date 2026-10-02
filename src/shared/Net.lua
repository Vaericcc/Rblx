--!strict
-- Single RemoteEvent for everything. First argument is always an action string.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local REMOTE_NAME = "StoryDubNet"

local function getRemote(): RemoteEvent
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = REMOTE_NAME
		remote.Parent = ReplicatedStorage
		return remote
	else
		return ReplicatedStorage:WaitForChild(REMOTE_NAME) :: RemoteEvent
	end
end

Net.remote = getRemote()

-- Server -> client
Net.S2C = {
	-- lobby
	LobbyInit = "LobbyInit", -- { modes, minPlayers, maxPlayers }
	RoomList = "RoomList", -- { rooms = {...} } rooms visible to this player
	RoomState = "RoomState", -- the room you're in, or nil when you're in none
	PadState = "PadState", -- the pad you're standing on, or nil
	-- match
	Phase = "Phase",
	Showcase = "Showcase",
	ShowcaseFocus = "ShowcaseFocus", -- { projectIndex, frameIndex, lineIndex, endsAt }
	ClaimState = "ClaimState",
	SkipState = "SkipState", -- { projectIndex, votes, needed }
	RoomMembers = "RoomMembers",
	LiveStroke = "LiveStroke", -- spectators: { artistId, artistName, panel, op = "add"|"undo"|"clear"|"set", stroke?, strokes? }
	Points = "Points", -- your persistent points total
	Teleporting = "Teleporting", -- { message } shown while the party is moved to its match server -- { hostId, members = { { userId, name } } } for the in-match players menu -- { roles = { [projectIndex] = { [character] = { userId, name } } } }
	Vote = "Vote",
	Results = "Results",
	MatchEnd = "MatchEnd",
	SubmitAck = "SubmitAck",
	Toast = "Toast",
}

-- Client -> server
Net.C2S = {
	Hello = "Hello", -- client is ready to receive lobby data
	CreateRoom = "CreateRoom", -- { visibility = "public" | "friends" }
	JoinRoom = "JoinRoom", -- roomId
	LeaveRoom = "LeaveRoom",
	StartRoom = "StartRoom", -- host only
	VoteMode = "VoteMode", -- modeId (applies to your current room or pad)
	SetTeamMode = "SetTeamMode", -- host: "random" | "pick" | "assign"
	PickTeam = "PickTeam", -- teamIndex (pick mode: yourself; assign mode: host sends { userId, team })
	Submit = "Submit",
	Vote = "Vote",
	Claim = "Claim", -- { projectIndex, character } toggles a role claim during the claim phase
	ShowcaseNext = "ShowcaseNext", -- the current line's actor is done speaking
	SkipStory = "SkipStory", -- vote to skip the story currently showing
	KickPlayer = "KickPlayer", -- host only: userId to remove from the room
	Stroke = "Stroke", -- live drawing: { panel, op = "add"|"undo"|"clear"|"set", stroke?, strokes? }
}

return Net
