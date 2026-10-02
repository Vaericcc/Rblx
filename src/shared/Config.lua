--!strict
-- Global tuning knobs for StoryDub. Everything time-related is in seconds.

local Config = {
	MIN_PLAYERS = 2,
	MAX_PLAYERS = 12,

	LOBBY_VOTE_SECONDS = 20,
	INTERMISSION_SECONDS = 6,
	SUBMIT_GRACE_SECONDS = 2, -- how long the server waits after a phase timer for late submissions

	SHOWCASE_TITLE_SECONDS = 4,
	SHOWCASE_PANEL_SECONDS = 7,
	SHOWCASE_REVEAL_SECONDS = 5,
	VOTE_SECONDS = 30,
	RESULTS_SECONDS = 15,

	-- Drawing limits (also enforced server-side)
	MAX_STROKES_PER_PANEL = 250,
	MAX_POINTS_PER_STROKE = 400,
	MIN_BRUSH = 2,
	MAX_BRUSH = 40,

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

return Config
