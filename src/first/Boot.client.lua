--!strict
--[[
	First thing on screen. ReplicatedFirst runs before the rest of the game has
	replicated, so this is up while Roblox is still streaming the place in.
	It is a static copy of the join screen's chrome (no shared modules: they may
	not exist yet); Main.client replaces it with the real join screen.
]]
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local v = if camera then camera.ViewportSize else Vector2.new(1280, 720)
local compact = v.X < 820 or v.Y < 480

local gui = Instance.new("ScreenGui")
gui.Name = "DubbleTakeBoot"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.ResetOnSpawn = false
gui.Parent = playerGui

local root = Instance.new("Frame")
root.BackgroundColor3 = Color3.fromRGB(18, 16, 20)
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui

local slash = Instance.new("Frame")
slash.BackgroundColor3 = Color3.fromRGB(44, 40, 48)
slash.BorderSizePixel = 0
slash.AnchorPoint = Vector2.new(0.5, 0.5)
slash.Position = UDim2.fromScale(-0.6, 0.5)
slash.Size = UDim2.new(0.42, 0, 2.6, 0)
slash.Rotation = if compact then 0 else 14
slash.Parent = root
TweenService:Create(slash, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.22, 0.5) }):Play()

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Font = Enum.Font.Bangers
title.Text = "DUBBLE TAKE"
title.TextColor3 = Color3.fromRGB(240, 234, 220)
title.TextSize = if compact then 40 else 84
title.TextXAlignment = if compact then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
title.Rotation = if compact then 0 else -90
title.AnchorPoint = if compact then Vector2.new(0, 0) else Vector2.new(0.5, 0.5)
title.Position = if compact then UDim2.new(0, 24, 0, 46) else UDim2.fromScale(0.07, 0.5)
title.Size = if compact then UDim2.new(0.5, 0, 0, 48) else UDim2.fromOffset(math.floor(v.Y * 0.86), 120)
title.TextTransparency = 1
title.Parent = root
TweenService:Create(title, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()

local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamMedium
label.Text = "Loading"
label.TextColor3 = Color3.fromRGB(240, 234, 220)
label.TextSize = if compact then 17 else 20
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.Position = if compact then UDim2.new(0, 26, 0, 102) else UDim2.fromScale(0.18, 0.42)
label.Size = UDim2.new(0.45, 0, 0, 24)
label.Parent = root

task.spawn(function()
	local n = 0
	while gui.Parent do
		n = (n % 3) + 1
		label.Text = "Loading" .. string.rep(".", n)
		task.wait(0.5)
	end
end)

-- Safety net: never block the game if the main client never shows up.
task.delay(20, function()
	if gui.Parent then gui:Destroy() end
end)
