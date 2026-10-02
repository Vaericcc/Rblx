--!strict
--[[
	Live-dub helper. Roblox does not let experiences record the microphone, so
	dubbing is performed live over voice chat. This panel gives the actor:
		- a big Unmute/Mute toggle for their own voice input (new audio API)
		- a level meter so they can see they're being heard
		- a clear fallback message when voice chat isn't available
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VoiceChatService = game:GetService("VoiceChatService")

local Make = require(script.Parent.Make)
local Theme = require(script.Parent.Theme)

local Mic = {}
Mic.__index = Mic

export type Mic = typeof(setmetatable({} :: {
	frame: Frame,
	button: TextButton,
	meter: Frame,
	status: TextLabel,
	input: AudioDeviceInput?,
	analyzer: AudioAnalyzer?,
	wire: Wire?,
	conn: RBXScriptConnection?,
}, Mic))

local function findInput(): AudioDeviceInput?
	local player = Players.LocalPlayer
	local input = player:FindFirstChildOfClass("AudioDeviceInput")
	if input then return input end
	-- Some setups parent it elsewhere; look one level into the character.
	if player.Character then
		return player.Character:FindFirstChildOfClass("AudioDeviceInput")
	end
	return nil
end

local function voiceEnabled(): boolean
	local ok, result = pcall(function()
		return VoiceChatService:IsVoiceEnabledForUserIdAsync(Players.LocalPlayer.UserId)
	end)
	return ok and result == true
end

function Mic.new(parent: Instance): Mic
	local self = setmetatable({}, Mic)
	self.frame = Make("Frame", {
		BackgroundColor3 = Theme.panelAlt,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Make.corner(),
		Make.pad(10),
		Make.list(nil, 8),
		Parent = parent,
	})
	self.status = Make.label("", 13, { TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = self.frame })
	self.button = Make.button("🎤  Unmute", Theme.good, function() self:toggle() end, { Size = UDim2.new(1, 0, 0, 44), Parent = self.frame })
	local meterBg = Make("Frame", { BackgroundColor3 = Theme.bg, Size = UDim2.new(1, 0, 0, 10), Make.corner(UDim.new(0.5, 0)), Parent = self.frame })
	self.meter = Make("Frame", { BackgroundColor3 = Theme.good, Size = UDim2.new(0, 0, 1, 0), Make.corner(UDim.new(0.5, 0)), Parent = meterBg })

	self.input = findInput()
	self.analyzer = nil
	self.wire = nil

	if not self.input then
		self.button.Visible = false
		meterBg.Visible = false
		if voiceEnabled() then
			self.status.Text = "Use the microphone icon in the Roblox top bar to unmute, then read your line out loud."
		else
			self.status.Text = "Voice chat is off for you. Turn it on in Roblox settings to perform; your line is shown as text meanwhile."
		end
		return self
	end

	-- Level meter via AudioAnalyzer wired from our own input (local only).
	pcall(function()
		local analyzer = Instance.new("AudioAnalyzer")
		analyzer.Parent = self.frame
		local wire = Instance.new("Wire")
		wire.SourceInstance = self.input
		wire.TargetInstance = analyzer
		wire.Parent = analyzer
		self.analyzer = analyzer
		self.wire = wire
	end)

	self.conn = RunService.Heartbeat:Connect(function()
		local input = self.input
		if not input then return end
		local muted = input.Muted
		self.button.Text = if muted then "🎤  Unmute to speak" else "🔴  You're live. Tap to mute"
		self.button.BackgroundColor3 = if muted then Theme.good else Theme.danger
		local level = 0
		if self.analyzer and not muted then
			level = math.clamp(self.analyzer.RmsLevel * 4, 0, 1)
		end
		self.meter.Size = UDim2.new(level, 0, 1, 0)
	end)
	self.status.Text = "Read your line out loud. Everyone in the match hears you."
	return self
end

function Mic.toggle(self: Mic)
	local input = self.input
	if not input then return end
	pcall(function()
		input.Muted = not input.Muted
	end)
end

function Mic.setMuted(self: Mic, muted: boolean)
	local input = self.input
	if input then
		pcall(function() input.Muted = muted end)
	end
end

function Mic.destroy(self: Mic)
	if self.conn then self.conn:Disconnect() end
	if self.wire then self.wire:Destroy() end
	if self.analyzer then self.analyzer:Destroy() end
	self.frame:Destroy()
end

return Mic
