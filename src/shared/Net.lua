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

-- Server -> client actions
Net.S2C = {
	Lobby = "Lobby",
	Phase = "Phase",
	Showcase = "Showcase",
	ShowcaseFocus = "ShowcaseFocus",
	Vote = "Vote",
	Results = "Results",
	Toast = "Toast",
	SubmitAck = "SubmitAck",
}

-- Client -> server actions
Net.C2S = {
	VoteMode = "VoteMode",
	Submit = "Submit",
	Vote = "Vote",
}

return Net
