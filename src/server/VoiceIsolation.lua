--!strict
--[[
	Hard audio isolation for matches.

	Every player's AudioDeviceInput (their microphone) has a server-controlled
	access list. During a match we set each member's list to "only the people
	in this match", so nobody outside hears them and they hear nobody outside,
	no matter where anyone stands or how many players share the server.
	Afterwards the list is cleared and normal proximity voice resumes in the hub.

	Requires VoiceChatService.UseAudioApi = Enabled (set in default.project.json).
]]
local Players = game:GetService("Players")

local VoiceIsolation = {}

local function inputOf(player: Player): AudioDeviceInput?
	local input = player:FindFirstChildOfClass("AudioDeviceInput")
	if input then return input end
	-- The device can arrive slightly after the player; wait briefly.
	local found = player:WaitForChild("AudioDeviceInput", 2)
	return if found and found:IsA("AudioDeviceInput") then found else nil
end

-- Only `members` can hear each other.
function VoiceIsolation.isolate(members: { Player })
	local ids = {}
	for _, p in members do table.insert(ids, p.UserId) end
	for _, p in members do
		local input = inputOf(p)
		if not input then continue end
		pcall(function()
			input.AccessType = Enum.AccessModifierType.Allow
			input:SetUserIdAccessList(ids)
		end)
	end
end

-- Back to hub rules: everyone nearby can hear you.
function VoiceIsolation.release(members: { Player })
	for _, p in members do
		if not p.Parent then continue end
		local input = p:FindFirstChildOfClass("AudioDeviceInput")
		if not input then continue end
		pcall(function()
			input.AccessType = Enum.AccessModifierType.Deny
			input:SetUserIdAccessList({})
		end)
	end
end

-- Keep a player's list current if their device is recreated mid-match (respawn).
function VoiceIsolation.watch(members: { Player }): { RBXScriptConnection }
	local ids = {}
	for _, p in members do table.insert(ids, p.UserId) end
	local conns = {}
	for _, p in members do
		table.insert(conns, p.ChildAdded:Connect(function(child)
			if child:IsA("AudioDeviceInput") then
				pcall(function()
					child.AccessType = Enum.AccessModifierType.Allow
					child:SetUserIdAccessList(ids)
				end)
			end
		end))
	end
	return conns
end

return VoiceIsolation
