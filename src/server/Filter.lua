--!strict
-- Wraps TextService so every piece of player-written text is filtered before
-- it is broadcast. Roblox requires this for any user generated text.
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")

local Filter = {}

function Filter.forBroadcast(text: string, fromUserId: number): string
	if text == "" then
		return ""
	end
	if RunService:IsStudio() then
		-- No filtering service in Studio test sessions; it can hang or error.
		return text
	end
	local ok, result = pcall(function()
		local obj = TextService:FilterStringAsync(text, fromUserId)
		return obj:GetNonChatStringForBroadcastAsync()
	end)
	if ok and typeof(result) == "string" then
		return result
	end
	-- If filtering fails we must not leak unfiltered text.
	return string.rep("#", #text)
end

return Filter
