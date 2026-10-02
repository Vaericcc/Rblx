--!strict
--[[
	Icon registry. Fill `ids` with the asset IDs of the uploaded 256x256 white
	PNGs (e.g. brush = 1234567890). Anything without an ID falls back to a
	short text label, so the UI never shows an empty box.
]]
local Icons = {}

local ids: { [string]: number } = {
	-- drawing tools
	-- brush = 0, eraser = 0, rect = 0, circle = 0, fill = 0, transform = 0, lasso = 0,
	-- mirror = 0, shape_filled = 0, shape_outline = 0, undo = 0, clear = 0,
	-- size_small = 0, size_medium = 0, size_large = 0, size_huge = 0,
	-- transform submenu
	-- flip_h = 0, flip_v = 0, rotate_left = 0, rotate_right = 0, warp = 0, duplicate = 0, delete = 0,
	-- menu
	-- play = 0, close = 0, join = 0, create = 0, platform = 0, room = 0, settings = 0,
	-- mic_on = 0, mic_off = 0, skip = 0, kick = 0, crown = 0, lock = 0, globe = 0, star = 0, points = 0,
	-- mode emblems (512x512)
	-- mode_classic = 0, mode_comic = 0, mode_story_swap = 0, mode_script_swap = 0,
	-- mode_versus = 0, mode_blind_dub = 0, mode_telephone = 0,
}

-- Text shown when no image is available. Keep these short; they sit in 40px squares.
local labels: { [string]: string } = {
	brush = "Brush", eraser = "Erase", rect = "Rect", circle = "Circle", fill = "Fill",
	transform = "Move", lasso = "Lasso", mirror = "Mirror", shape_filled = "Solid", shape_outline = "Line",
	undo = "Undo", clear = "Clear",
	size_small = "S", size_medium = "M", size_large = "L", size_huge = "XL",
	flip_h = "Flip H", flip_v = "Flip V", rotate_left = "Rot L", rotate_right = "Rot R",
	warp = "Warp", duplicate = "Copy", delete = "Delete",
	play = "PLAY", close = "X", join = "JOIN", create = "CREATE", platform = "PLATFORM", room = "ROOM",
	settings = "SETTINGS", mic_on = "MIC ON", mic_off = "MUTED", skip = "SKIP", kick = "REMOVE",
	crown = "HOST", lock = "FRIENDS", globe = "PUBLIC", star = "PRO", points = "PTS",
	mode_classic = "", mode_comic = "", mode_story_swap = "", mode_script_swap = "",
	mode_versus = "", mode_blind_dub = "", mode_telephone = "",
}

Icons.ids = ids
Icons.labels = labels

function Icons.has(name: string): boolean
	local id = ids[name]
	return id ~= nil and id > 0
end

function Icons.image(name: string): string
	local id = ids[name]
	return if id and id > 0 then ("rbxassetid://%d"):format(id) else ""
end

function Icons.label(name: string): string
	return labels[name] or name
end

return Icons
