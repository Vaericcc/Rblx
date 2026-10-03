--!strict
-- Global tuning knobs for Dubble Take. Everything time-related is in seconds.

local RunService = game:GetService("RunService")

-- In Studio you can test alone: one player is enough and every mode is unlocked.
-- Swap modes will hand your own work back to you, which is fine for checking screens.
local SOLO_TESTING = RunService:IsStudio()

local Config = {
	SOLO_TESTING = SOLO_TESTING,
	-- Dubble Take is a voice game: players must have voice chat enabled to play.
	-- Studio solo testing is exempt because voice doesn't run there.
	VOICE_REQUIRED = not SOLO_TESTING,
	-- Matches run in their own reserved server (TeleportService). Studio can't
	-- teleport, so there matches run inside the hub server instead.
	PRIVATE_MATCH_SERVERS = not RunService:IsStudio(),
	MATCH_SERVER_GATHER_SECONDS = 25, -- how long a match server waits for the party to arrive

	-- Teams (VS Comic)
	TEAM_MIN = 2,
	TEAM_MAX = 5,
	TEAM_COLORS = {
		{ name = "Red", r = 255, g = 92, b = 92 },
		{ name = "Blue", r = 94, g = 160, b = 255 },
		{ name = "Green", r = 96, g = 220, b = 140 },
		{ name = "Yellow", r = 255, g = 196, b = 61 },
	},

	-- Persistent points and Pro rooms
	POINTS_DATASTORE = "StoryDubPoints_v1",
	PRO_POINTS = 10000, -- points needed to create or join a Pro room
	MIN_PLAYERS = if SOLO_TESTING then 1 else 2,
	MAX_PLAYERS = 10, -- per room

	-- Lobby
	ROOM_LIST_REFRESH_SECONDS = 2,
	PAD_COUNT = 4,
	PAD_COUNTDOWN_SECONDS = 20, -- once a pad has MIN_PLAYERS, the match starts after this
	PAD_SCAN_SECONDS = 0.25,
	INTERMISSION_SECONDS = 5,
	SUBMIT_GRACE_SECONDS = 2, -- how long the server waits after a phase timer for late submissions

	SHOWCASE_TITLE_SECONDS = 4,
	SHOWCASE_PANEL_SECONDS = 4, -- a panel with no lines
	SHOWCASE_LINE_SECONDS = 7, -- time each actor gets per line before auto-advance
	PHASE_BRIEFING_SECONDS = 3,
	SHOWCASE_REVEAL_SECONDS = 5,
	VOTE_SECONDS = 30,
	RESULTS_SECONDS = 15,

	-- Drawing limits (also enforced server-side)
	MAX_STROKES_PER_PANEL = 250,
	MAX_POINTS_PER_STROKE = 400,
	MIN_BRUSH = 2,
	MAX_BRUSH = 120, -- airbrush goes wide

	-- Text limits
	MAX_TITLE_LEN = 40,
	MAX_LOGLINE_LEN = 160,
	MAX_CHAR_NAME_LEN = 20,
	MAX_CHAR_TRAIT_LEN = 40,
	MAX_LINE_LEN = 120,
	MAX_CAPTION_LEN = 120,

	POINTS_PER_VOTE = 100,
	POINTS_FOR_SUBMITTING = 25,
}

-- Players a mode needs, honoring solo testing in Studio.
function Config.playersNeeded(modeMinPlayers: number): number
	return if SOLO_TESTING then 1 else modeMinPlayers
end

return Config
