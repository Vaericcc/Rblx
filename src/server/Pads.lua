--!strict
--[[
	Physical matchmaking: platforms in the hub. Stand on one with enough friends
	and a match forms automatically. The server builds the pads so the place file
	needs nothing but a floor.
]]
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Rooms = require(script.Parent.Rooms)

local Pads = {}

local PAD_SIZE = Vector3.new(16, 1, 16)
local PAD_COLORS = {
	Color3.fromRGB(255, 196, 61),
	Color3.fromRGB(94, 200, 255),
	Color3.fromRGB(255, 120, 140),
	Color3.fromRGB(120, 230, 150),
}

type Pad = { index: number, part: Part, label: TextLabel, sub: TextLabel }
local pads: { Pad } = {}

local function buildPad(index: number, position: Vector3): Pad
	local color = PAD_COLORS[((index - 1) % #PAD_COLORS) + 1]
	local part = Instance.new("Part")
	part.Name = ("Pad%d"):format(index)
	part.Anchored = true
	part.Size = PAD_SIZE
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Transparency = 0.15
	part.TopSurface = Enum.SurfaceType.Smooth
	part.Parent = workspace

	-- Soft glow under the pad
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = 22
	glow.Brightness = 0.9
	glow.Parent = part

	-- Corner posts so the pad reads as a stage
	for _, corner in { Vector2.new(1, 1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(-1, -1) } do
		local post = Instance.new("Part")
		post.Anchored = true
		post.Size = Vector3.new(0.6, 3, 0.6)
		post.Position = position + Vector3.new(corner.X * (PAD_SIZE.X / 2 + 0.6), 1.5, corner.Y * (PAD_SIZE.Z / 2 + 0.6))
		post.Color = Color3.fromRGB(40, 40, 52)
		post.Material = Enum.Material.Metal
		post.Parent = part
		local tip = Instance.new("Part")
		tip.Anchored = true
		tip.Size = Vector3.new(0.7, 0.3, 0.7)
		tip.Position = post.Position + Vector3.new(0, 1.65, 0)
		tip.Color = color
		tip.Material = Enum.Material.Neon
		tip.Parent = part
	end

	local rim = Instance.new("Part")
	rim.Name = "Rim"
	rim.Anchored = true
	rim.Size = PAD_SIZE + Vector3.new(2, -0.4, 2)
	rim.Position = position - Vector3.new(0, 0.2, 0)
	rim.Color = Color3.fromRGB(40, 40, 52)
	rim.Material = Enum.Material.Slate
	rim.Parent = part

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(260, 90)
	billboard.StudsOffset = Vector3.new(0, 7, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 120
	billboard.Parent = part

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
	bg.BackgroundTransparency = 0.15
	bg.BorderSizePixel = 0
	bg.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = bg

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -16, 0, 40)
	label.Position = UDim2.fromOffset(8, 8)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 26
	label.TextColor3 = color
	label.Text = ("PLATFORM %d"):format(index)
	label.Parent = bg

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -16, 0, 30)
	sub.Position = UDim2.fromOffset(8, 50)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.Gotham
	sub.TextSize = 18
	sub.TextColor3 = Color3.fromRGB(245, 245, 250)
	sub.Text = "Stand here to play"
	sub.Parent = bg

	return { index = index, part = part, label = label, sub = sub }
end

local function playersOn(pad: Pad): { Player }
	local region = CFrame.new(pad.part.Position + Vector3.new(0, 4, 0))
	local size = Vector3.new(PAD_SIZE.X, 8, PAD_SIZE.Z)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { pad.part }
	local found: { [Player]: boolean } = {}
	for _, part in workspace:GetPartBoundsInBox(region, size, params) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model then
			local player = Players:GetPlayerFromCharacter(model)
			if player and not Rooms.isBusy(player) then
				found[player] = true
			end
		end
	end
	local out = {}
	for p in found do table.insert(out, p) end
	return out
end

local function describe(room: any): string
	if not room then return "Stand here to play" end
	if room.state == "playing" then return "Match in progress" end
	if room.state == "starting" and room.startsAt then
		local left = math.max(0, math.ceil(room.startsAt - workspace:GetServerTimeNow()))
		return ("%d/%d  ·  starting in %ds"):format(#room.members, Config.MAX_PLAYERS, left)
	end
	return ("%d/%d  ·  need %d to start"):format(#room.members, Config.MAX_PLAYERS, Config.MIN_PLAYERS)
end

function Pads.init()
	local radius = 40
	for i = 1, Config.PAD_COUNT do
		local angle = (i - 1) / Config.PAD_COUNT * math.pi * 2
		local pos = Vector3.new(math.cos(angle) * radius, 0.5, math.sin(angle) * radius)
		pads[i] = buildPad(i, pos)
	end

	task.spawn(function()
		while true do
			for _, pad in pads do
				local room = Rooms.syncPad(pad.index, playersOn(pad))
				pad.sub.Text = describe(room)
			end
			task.wait(Config.PAD_SCAN_SECONDS)
		end
	end)
end

return Pads
