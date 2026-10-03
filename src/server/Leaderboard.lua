--!strict
--[[
	Hall of Fame: a stone board in the courtyard listing the global top ten by
	points, with the #1 player's avatar standing on a podium beside it.
	Refreshes every minute. Falls back to this server's totals in Studio.
]]
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Points = require(script.Parent.Points)

local Leaderboard = {}

local REFRESH = 60
local TOP_N = 10

local root: Model
local rows: { TextLabel } = {}
local champion: Model? = nil
local championId: number? = nil
local nameplate: TextLabel

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do (p :: any)[k] = v end
	p.Parent = root
	return p
end

local function nameOf(userId: number): string
	local online = Players:GetPlayerByUserId(userId)
	if online then return online.DisplayName end
	local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	return if ok then name else ("Player %d"):format(userId)
end

local function buildBoard(cf: CFrame)
	-- Stone frame and dark slate face
	part({ Name = "BoardFrame", Size = Vector3.new(14, 11, 1.2), CFrame = cf, Color = Color3.fromRGB(160, 162, 166), Material = Enum.Material.Slate })
	local face = part({ Name = "BoardFace", Size = Vector3.new(12.6, 9.6, 0.4), CFrame = cf * CFrame.new(0, 0, 0.5), Color = Color3.fromRGB(28, 26, 32), Material = Enum.Material.Slate })
	part({ Name = "BoardPlinth", Size = Vector3.new(15, 1, 3), CFrame = cf * CFrame.new(0, -6, 0.5), Color = Color3.fromRGB(118, 120, 124), Material = Enum.Material.Slate })
	for side = -1, 1, 2 do
		local torch = part({ Name = "BoardTorch", Size = Vector3.new(0.8, 1.2, 0.8), CFrame = cf * CFrame.new(side * 8, 4, 0.8), Color = Color3.fromRGB(255, 190, 110), Material = Enum.Material.Neon })
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 200, 130)
		l.Range = 14
		l.Brightness = 0.8
		l.Parent = torch
	end

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	gui.Parent = face

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 64)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.Bangers
	title.TextSize = 54
	title.TextColor3 = Color3.fromRGB(255, 196, 61)
	title.Text = "HALL OF FAME"
	title.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, 0, 0, 22)
	sub.Position = UDim2.fromOffset(0, 60)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextSize = 16
	sub.TextColor3 = Color3.fromRGB(170, 170, 190)
	sub.Text = "all-time points"
	sub.Parent = gui

	for i = 1, TOP_N do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, -40, 0, 26)
		row.Position = UDim2.fromOffset(20, 86 + (i - 1) * 27)
		row.BackgroundTransparency = 1
		row.Font = if i == 1 then Enum.Font.GothamBold else Enum.Font.GothamMedium
		row.TextSize = if i == 1 then 22 else 18
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = if i == 1 then Color3.fromRGB(255, 196, 61) else Color3.fromRGB(240, 234, 220)
		row.RichText = true
		row.Text = ""
		row.Parent = gui
		rows[i] = row
	end

	-- Champion podium + nameplate
	local podium = part({ Name = "Podium", Size = Vector3.new(5, 1.2, 5), CFrame = cf * CFrame.new(10.5, -5.4, 2), Color = Color3.fromRGB(196, 196, 198), Material = Enum.Material.Marble })
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(240, 60)
	bb.StudsOffset = Vector3.new(0, 7.5, 0)
	bb.MaxDistance = 90
	bb.Parent = podium
	nameplate = Instance.new("TextLabel")
	nameplate.Size = UDim2.fromScale(1, 1)
	nameplate.BackgroundTransparency = 1
	nameplate.Font = Enum.Font.Bangers
	nameplate.TextScaled = true
	nameplate.RichText = true
	nameplate.TextColor3 = Color3.fromRGB(255, 196, 61)
	nameplate.TextStrokeTransparency = 0.3
	nameplate.Text = ""
	nameplate.Parent = bb
	return podium
end

local function setChampion(userId: number?, podium: Part)
	if userId == championId then return end
	championId = userId
	if champion then champion:Destroy() champion = nil end
	nameplate.Text = ""
	if not userId then return end
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromUserId(userId)
	end)
	if not ok or not model then return end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then d.Anchored = true d.CanCollide = false end
		if d:IsA("BaseScript") then d:Destroy() end
	end
	model.Name = "Champion"
	model:PivotTo(podium.CFrame * CFrame.new(0, 3.6, 0) * CFrame.Angles(0, math.rad(20), 0))
	model.Parent = root
	local hl = Instance.new("Highlight")
	hl.FillTransparency = 1
	hl.OutlineColor = Color3.fromRGB(255, 196, 61)
	hl.OutlineTransparency = 0.2
	hl.Parent = model
	champion = model
	nameplate.Text = ("👑 %s"):format(nameOf(userId))
end

function Leaderboard.init(cf: CFrame)
	root = Instance.new("Model")
	root.Name = "HallOfFame"
	root.Parent = workspace
	local podium = buildBoard(cf)

	task.spawn(function()
		while true do
			local top = Points.top(TOP_N)
			for i = 1, TOP_N do
				local entry = top[i]
				rows[i].Text = if entry
					then ("%d.  %s  <font color=\"#ffc43d\">%d</font>"):format(i, nameOf(entry.userId), entry.points)
					else ("%d.  <font color=\"#55535f\">—</font>"):format(i)
			end
			setChampion(if top[1] then top[1].userId else nil, podium)
			task.wait(REFRESH)
		end
	end)
end

return Leaderboard
