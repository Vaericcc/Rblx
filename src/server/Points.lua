--!strict
-- Persistent points per player. Totals gate Pro rooms.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local Points = {}

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.POINTS_DATASTORE)
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
			pcall(function()
				store:UpdateAsync(key(player.UserId), function(old)
					return (tonumber(old) or 0) + amount
				end)
			end)
		end)
	end
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
