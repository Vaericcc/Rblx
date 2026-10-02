--!strict
--[[
	Game modes are pure data: an ordered list of phases.

	Every player owns one "project" (a storyboard). Each phase assigns a worker
	to each project using `offset`:
		offset 0 -> you work on your own project
		offset 1 -> you work on the project of the player "to your left"
		offset 2 -> two seats over, and so on
	That single number is what turns a mode into a "swap" mode.

	Phase kinds:
		premise  write a title + one-line logline
		cast     invent `count` characters (name + defining trait)
		script   write dialogue for `panels` panels before anything is drawn
		draw     draw `panels` panels (appended to whatever the project already has)
		claim    everyone picks which character they will voice, before drawing starts
		dub      write lines for every existing panel. With `roles = true` you write
		         only for the characters you claimed; otherwise one dubber per project.
		caption  describe the latest panel in one sentence (telephone-style)
]]

export type Phase = {
	kind: string,
	offset: number,
	duration: number,
	count: number?,
	panels: number?,
	blind: boolean?,
	roles: boolean?,
}

export type Mode = {
	id: string,
	name: string,
	tagline: string,
	description: string,
	minPlayers: number,
	phases: { Phase },
	liveDub: boolean, -- during the showcase, call the dubber up to voice their lines over voice chat
}

local Modes: { Mode } = {
	{
		id = "classic",
		name = "CLASSIC",
		tagline = "One panel. One punchline.",
		description = "Write a premise, create a cast, and draw your story in a single panel. Friends claim the roles and voice them live.",
		minPlayers = 2,
		liveDub = true,
		phases = {
			{ kind = "premise", offset = 0, duration = 45 },
			{ kind = "cast", offset = 0, duration = 60, count = 2 },
			{ kind = "claim", offset = 0, duration = 30 },
			{ kind = "draw", offset = 0, duration = 90, panels = 1 },
			{ kind = "dub", offset = 0, duration = 60, roles = true },
		},
	},
	{
		id = "comic",
		name = "COMIC",
		tagline = "Four panels, one story.",
		description = "Write a premise, create a cast, and draw a 4-panel comic. Friends claim the roles and voice every panel.",
		minPlayers = 2,
		liveDub = true,
		phases = {
			{ kind = "premise", offset = 0, duration = 45 },
			{ kind = "cast", offset = 0, duration = 60, count = 3 },
			{ kind = "claim", offset = 0, duration = 30 },
			{ kind = "draw", offset = 0, duration = 180, panels = 4 },
			{ kind = "dub", offset = 0, duration = 90, roles = true },
		},
	},
	{
		id = "story_swap",
		name = "STORY SWAP",
		tagline = "Your idea. Their hands.",
		description = "Write a premise and a cast, then swap: you draw your friend's story while they draw yours. Claimed roles voice the result.",
		minPlayers = 3,
		liveDub = true,
		phases = {
			{ kind = "premise", offset = 0, duration = 45 },
			{ kind = "cast", offset = 0, duration = 60, count = 3 },
			{ kind = "claim", offset = 0, duration = 30 },
			{ kind = "draw", offset = 1, duration = 150, panels = 3 },
			{ kind = "dub", offset = 0, duration = 75, roles = true },
		},
	},
	{
		id = "script_swap",
		name = "SCRIPT SWAP",
		tagline = "The words come first.",
		description = "Create a cast and write a 3-panel script. Swap with a friend and draw to THEIR script. Everyone performs the role they claimed.",
		minPlayers = 2,
		liveDub = true,
		phases = {
			{ kind = "cast", offset = 0, duration = 60, count = 3 },
			{ kind = "claim", offset = 0, duration = 30 },
			{ kind = "script", offset = 0, duration = 120, panels = 3 },
			{ kind = "draw", offset = 1, duration = 150, panels = 3 },
		},
	},
	{
		id = "blind_dub",
		name = "BLIND DUB",
		tagline = "You never saw the script.",
		description = "Draw a comic from your own premise. The dubber sees ONLY the pictures and must invent what everyone is saying. The real premise is revealed at the end.",
		minPlayers = 2,
		liveDub = true,
		phases = {
			{ kind = "premise", offset = 0, duration = 45 },
			{ kind = "cast", offset = 0, duration = 60, count = 2 },
			{ kind = "draw", offset = 0, duration = 150, panels = 3 },
			{ kind = "dub", offset = 1, duration = 75, blind = true },
		},
	},
	{
		id = "telephone",
		name = "BROKEN TELEPHONE",
		tagline = "Draw it. Describe it. Repeat.",
		description = "Write a premise. The next player draws it. The next describes the drawing without seeing the premise. Then it gets drawn again. Watch the story mutate.",
		minPlayers = 3,
		liveDub = false,
		phases = {
			{ kind = "premise", offset = 0, duration = 40 },
			{ kind = "draw", offset = 1, duration = 75, panels = 1 },
			{ kind = "caption", offset = 2, duration = 35 },
			{ kind = "draw", offset = 3, duration = 75, panels = 1 },
			{ kind = "caption", offset = 4, duration = 35 },
		},
	},
}

local byId: { [string]: Mode } = {}
for _, mode in Modes do
	byId[mode.id] = mode
end

return {
	list = Modes,
	byId = byId,
}
