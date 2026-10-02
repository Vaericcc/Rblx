--!strict
-- Client router: receives server actions, mounts the right screen, handles submission.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local UI = script.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Hud = require(UI.Hud)
local Screens = script.Parent.Screens
local Lobby = require(Screens.Lobby)
local TextPhases = require(Screens.TextPhases)
local Draw = require(Screens.Draw)
local Dub = require(Screens.Dub)
local Showcase = require(Screens.Showcase)
local Vote = require(Screens.Vote)
local Results = require(Screens.Results)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Make("ScreenGui", {
	Name = "StoryDub",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})
local backdrop = Make("Frame", {
	BackgroundColor3 = Theme.bg,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	Make.pad(16),
	Parent = gui,
})
local hud = Hud.new(backdrop)
local content = Make("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 1, -96),
	Position = UDim2.new(0, 0, 0, 96),
	Parent = backdrop,
})
local toast = Make.label("", 16, {
	BackgroundColor3 = Theme.panelAlt,
	BackgroundTransparency = 1,
	TextTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -20),
	Size = UDim2.new(0, 520, 0, 40),
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 100,
	Make.corner(),
	Parent = gui,
})

local current: any = nil
local autoSubmitThread: thread? = nil

local ctx = {
	hud = hud,
	lobbyVote = nil :: string?,
	markDirty = function() hud:unmarkSubmitted() end,
}

local function showToast(text: string)
	toast.Text = text
	toast.BackgroundTransparency = 0
	toast.TextTransparency = 0
	task.delay(4, function()
		if toast.Text == text then
			toast.BackgroundTransparency = 1
			toast.TextTransparency = 1
		end
	end)
end

local function unmount()
	if autoSubmitThread then task.cancel(autoSubmitThread) autoSubmitThread = nil end
	if current then
		current.destroy()
		current = nil
	end
	hud.onSubmit = nil
end

local function submitCurrent()
	if not current or not current.collect then return end
	local data = current.collect()
	Net.remote:FireServer(current.submitAction or Net.C2S.Submit, data)
	hud:markSubmitted()
end

local function mount(screenFn: (Frame, any, any) -> any, data: any, endsAt: number?)
	unmount()
	current = screenFn(content, data, ctx)
	if current.collect then
		hud.onSubmit = submitCurrent
		if endsAt then
			-- Auto-submit just before the server stops listening so nobody loses work.
			local delay = math.max(0, endsAt - workspace:GetServerTimeNow() - 0.5)
			autoSubmitThread = task.delay(delay, function()
				if current and not hud.submitted then submitCurrent() end
			end)
		end
	end
end

local PHASE_SCREENS: { [string]: (Frame, any, any) -> any } = {
	premise = TextPhases.premise,
	cast = TextPhases.cast,
	script = TextPhases.script,
	caption = TextPhases.caption,
	draw = Draw.show,
	dub = Dub.show,
}

Net.remote.OnClientEvent:Connect(function(action: string, data: any)
	if action == Net.S2C.Lobby then
		-- Lobby re-broadcasts every second; only rebuild when it isn't already up.
		if current and current.isLobby then
			current.destroy()
			current = Lobby.show(content, data, ctx)
			current.isLobby = true
		else
			mount(Lobby.show, data, nil)
			current.isLobby = true
		end
	elseif action == Net.S2C.Phase then
		local screen = PHASE_SCREENS[data.kind]
		if screen then
			mount(screen, data.payload, data.endsAt)
			hud:set(data.title, data.instructions, data.endsAt, true)
		end
	elseif action == Net.S2C.Showcase then
		mount(Showcase.show, data, nil)
	elseif action == Net.S2C.ShowcaseFocus then
		if current and current.focus then
			current.focus(data.projectIndex, data.frameIndex)
		end
	elseif action == Net.S2C.Vote then
		mount(Vote.show, data, data.endsAt)
	elseif action == Net.S2C.Results then
		mount(Results.show, data, nil)
	elseif action == Net.S2C.Toast then
		showToast(tostring(data))
	elseif action == Net.S2C.SubmitAck then
		hud:markSubmitted()
	end
end)
