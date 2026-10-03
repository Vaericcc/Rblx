--!strict
-- Persistent points per player. Totals gate Pro rooms.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local Points = {}

local store = nil
local ordered = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.POINTS_DATASTORE)
	ordered = DataStoreService:GetOrderedDataStore(Config.POINTS_DATASTORE .. "_ordered")
end)

local cache: { [number]: number } = {}

local function key(userId: number): string
	return ("u_%d"):format(userId)
end

function Points.get(player: Player): number
	local cached = cache[player.UserId]
	if cached then return cached end
	local value = 0
	if store then
		local ok, result = pcall(function() return store:GetAsync(key(player.UserId)) end)
		if ok and typeof(result) == "number" then value = result end
	end
	cache[player.UserId] = value
	return value
end

function Points.push(player: Player)
	if player.Parent then
		Net.remote:FireClient(player, Net.S2C.Points, { total = Points.get(player), pro = Config.PRO_POINTS })
	end
end

function Points.add(player: Player, amount: number)
	if amount <= 0 then return end
	cache[player.UserId] = Points.get(player) + amount
	Points.push(player)
	if store then
		task.spawn(function()
			local total = nil
			pcall(function()
				total = store:UpdateAsync(key(player.UserId), function(old)
					return (tonumber(old) or 0) + amount
				end)
			end)
			if ordered and typeof(total) == "number" then
				pcall(function() ordered:SetAsync(tostring(player.UserId), math.floor(total)) end)
			end
		end)
	end
end

-- Global top N as { { userId, points } }. Falls back to this server's session
-- totals when the DataStore is unavailable (e.g. Studio without API access).
function Points.top(n: number): { { userId: number, points: number } }
	local out = {}
	if ordered then
		local ok, pages = pcall(function() return ordered:GetSortedAsync(false, n) end)
		if ok and pages then
			local ok2, page = pcall(function() return pages:GetCurrentPage() end)
			if ok2 and page then
				for _, entry in page do
					local id = tonumber(entry.key)
					if id then table.insert(out, { userId = id, points = entry.value }) end
				end
			end
		end
	end
	if #out == 0 then
		for userId, pts in cache do
			if pts > 0 then table.insert(out, { userId = userId, points = pts }) end
		end
		table.sort(out, function(a, b) return a.points > b.points end)
		while #out > n do table.remove(out) end
	end
	return out
end

-- Award a finished round's scores: { [userId] = score }.
function Points.awardRound(scores: { [number]: number })
	for userId, score in scores do
		local player = Players:GetPlayerByUserId(userId)
		if player then Points.add(player, score) end
	end
end

function Points.isPro(player: Player): boolean
	return Points.get(player) >= Config.PRO_POINTS
end

Players.PlayerRemoving:Connect(function(player)
	cache[player.UserId] = nil
end)

return Points
