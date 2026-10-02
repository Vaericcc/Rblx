--!strict
-- Turns character movement and the mobile thumbstick/jump button off during a match.
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")

local Controls = {}

local controlsModule: any = nil
local function getControls(): any
	if controlsModule then return controlsModule end
	local ok, result = pcall(function()
		local scripts = Players.LocalPlayer:WaitForChild("PlayerScripts", 5)
		local pm = scripts and scripts:WaitForChild("PlayerModule", 5)
		return pm and require(pm):GetControls()
	end)
	if ok then controlsModule = result end
	return controlsModule
end

function Controls.setGameplayEnabled(enabled: boolean)
	local controls = getControls()
	if controls then
		if enabled then controls:Enable() else controls:Disable() end
	end
	pcall(function()
		GuiService.TouchControlsEnabled = enabled
	end)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, enabled)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, enabled)
	end)
	-- Freeze the character so it can't be shoved off a pad mid-match.
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = if enabled then 16 else 0
		humanoid.JumpHeight = if enabled then 7.2 else 0
	end
end

return Controls
