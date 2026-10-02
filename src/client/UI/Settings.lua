--!strict
-- Client settings store. Values persist per device via a small JSON blob in
-- PlayerGui attributes for the session; apply() pushes them into the game.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local Settings = {}

export type Values = {
	masterVolume: number,
	musicVolume: number,
	voiceVolume: number,
	autoUnmute: boolean,
	uiScale: number,
	colorBlind: boolean,
	reduceMotion: boolean,
}

local defaults: Values = {
	masterVolume = 0.8,
	musicVolume = 0.6,
	voiceVolume = 1,
	autoUnmute = true,
	uiScale = 1,
	colorBlind = false,
	reduceMotion = false,
}

Settings.values = table.clone(defaults) :: Values
Settings.changed = Instance.new("BindableEvent")

-- The settings page lists these in order. kind: "slider" (0..1 or min/max) | "toggle"
Settings.schema = {
	{ key = "masterVolume", label = "Master volume", kind = "slider", min = 0, max = 1 },
	{ key = "musicVolume", label = "Music", kind = "slider", min = 0, max = 1 },
	{ key = "voiceVolume", label = "Voice chat volume", kind = "slider", min = 0, max = 1.5 },
	{ key = "autoUnmute", label = "Auto-unmute when it's my line", kind = "toggle" },
	{ key = "uiScale", label = "UI size", kind = "slider", min = 0.8, max = 1.3 },
	{ key = "colorBlind", label = "Colour-blind palette", kind = "toggle" },
	{ key = "reduceMotion", label = "Reduce motion", kind = "toggle" },
}

local function load()
	local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local raw = gui and gui:GetAttribute("StoryDubSettings")
	if typeof(raw) == "string" then
		local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and typeof(data) == "table" then
			for k, v in defaults do
				if typeof(data[k]) == typeof(v) then (Settings.values :: any)[k] = data[k] end
			end
		end
	end
end

local function save()
	local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if gui then
		gui:SetAttribute("StoryDubSettings", HttpService:JSONEncode(Settings.values))
	end
end

function Settings.apply()
	local v = Settings.values
	pcall(function()
		local group = SoundService:FindFirstChild("StoryDubMaster") :: SoundGroup?
		if not group then
			group = Instance.new("SoundGroup")
			group.Name = "StoryDubMaster"
			group.Parent = SoundService
		end
		group.Volume = v.masterVolume
	end)
	Settings.changed:Fire()
end

function Settings.set(key: string, value: any)
	(Settings.values :: any)[key] = value
	save()
	Settings.apply()
end

function Settings.get(key: string): any
	return (Settings.values :: any)[key]
end

load()
return Settings
