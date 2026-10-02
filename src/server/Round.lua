--!strict
--[[
	Runs one full round of a mode: every phase, then showcase, voting, results.
	All state lives on the Round object so a crash in one round can't poison the next.
]]
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Modes = require(Shared.Modes)
local Net = require(Shared.Net)
local Projects = require(script.Parent.Projects)
local Points = require(script.Parent.Points)
local Strokes = require(Shared.Strokes)

local Round = {}
Round.__index = Round

type Worker = { player: Player, projectIndex: number?, panelSlot: number? } -- projectIndex nil = works across projects (claim / role dub); panelSlot = co-op panel

export type Round = typeof(setmetatable({} :: {
	mode: Modes.Mode,
	players: { Player },
	projects: { Projects.Project },
	scores: { [number]: number },
	phase: Modes.Phase?,
	workers: { [number]: Worker }, -- userId -> worker
	pending: { [number]: boolean }, -- userId -> still waiting on their submission
	submissions: { [number]: any }, -- userId -> raw data
	connections: { RBXScriptConnection },
	-- showcase
	currentActorId: number?,
	skipRequested: boolean,
	showingProject: number?,
	skipStoryVotes: { [number]: boolean },
	skipStory: boolean,
	skipped: { [number]: boolean }, -- projectIndex -> was skipped in the showcase
	live: { [number]: { [number]: { Strokes.Stroke } } }, -- userId -> panelOffset -> strokes drawn so far this phase
	spectators: { Player },
	teamOf: { [number]: number }, -- userId -> team index (VS Comic); empty otherwise
}, Round))

local AWARDS = {
	{ id = "funniest", name = "Funniest", emoji = "😂" },
	{ id = "best_art", name = "Best Art", emoji = "🎨" },
	{ id = "best_dub", name = "Best Dub", emoji = "🎤" },
	{ id = "plot_twist", name = "Plot Twist", emoji = "🌀" },
}

local PHASE_TEXT = {
	premise = { "Write your premise", "Give your story a title and a one-sentence hook." },
	cast = { "Create the cast", "Invent the characters. Name them and give each one a defining trait." },
	claim = { "Claim your roles", "Pick the characters you'll voice. Tap a name to claim it. Unclaimed roles get handed out." },
	script = { "Write the script", "Write what each character says, panel by panel. Someone else will draw it." },
	draw = { "Draw!", "Bring the story to life. Fill every panel." },
	dub = { "Write your lines", "Write what your characters say in each panel. You'll perform them live in the showcase." },
	caption = { "Describe what you see", "You only get the drawing. In one sentence, what is happening?" },
	scenes = { "Direct the comic", "You're the director. Describe what happens in each panel. One player will draw each scene." },
}

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Deal players into balanced teams at random.
function Round.randomTeams(players: { Player }): { [number]: number }
	local n = #players
	local teamCount = math.max(1, math.min(math.ceil(n / Config.TEAM_MAX), math.max(1, n // Config.TEAM_MIN)))
	if n >= Config.TEAM_MIN * 2 then teamCount = math.max(2, teamCount) end
	teamCount = math.min(teamCount, #Config.TEAM_COLORS)
	local order = table.clone(players)
	local rng = Random.new()
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local out = {}
	for i, p in order do
		out[p.UserId] = ((i - 1) % teamCount) + 1
	end
	return out
end

function Round.teamMembers(self: Round, team: number): { Player }
	local out = {}
	for _, p in self.players do
		if self.teamOf[p.UserId] == team then table.insert(out, p) end
	end
	return out
end

function Round.teamName(team: number): string
	local c = Config.TEAM_COLORS[team]
	return if c then ("Team %s"):format(c.name) else ("Team %d"):format(team)
end

function Round.new(mode: Modes.Mode, players: { Player }, teams: { [number]: number }?): Round
	local self = setmetatable({}, Round)
	self.mode = mode
	self.players = players
	self.projects = {}
	self.scores = {}
	self.phase = nil
	self.workers = {}
	self.pending = {}
	self.submissions = {}
	self.connections = {}
	self.currentActorId = nil
	self.skipRequested = false
	self.showingProject = nil
	self.skipStoryVotes = {}
	self.skipStory = false
	self.skipped = {}
	self.live = {}
	self.spectators = {}
	self.teamOf = {}
	if mode.teams then
		-- VS Comic: one storyboard per team, directed by its first member.
		self.teamOf = teams or Round.randomTeams(players)
		for _, player in players do
			if not self.teamOf[player.UserId] then self.teamOf[player.UserId] = 1 end
			self.scores[player.UserId] = 0
		end
		local maxTeam = 1
		for _, t in self.teamOf do maxTeam = math.max(maxTeam, t) end
		for t = 1, maxTeam do
			local members = self:teamMembers(t)
			if #members > 0 then
				local project = Projects.new(t, members[1])
				project.ownerName = Round.teamName(t)
				self.projects[t] = project
			end
		end
	else
		for i, player in players do
			self.projects[i] = Projects.new(i, player)
			self.scores[player.UserId] = 0
		end
	end
	return self
end

function Round.broadcast(self: Round, action: string, data: any)
	for _, player in self.players do
		if player.Parent then
			Net.remote:FireClient(player, action, data)
		end
	end
end

function Round.pruneLeavers(self: Round)
	for i = #self.players, 1, -1 do
		if not self.players[i].Parent then
			table.remove(self.players, i)
		end
	end
end

----------------------------------------------------------------------------
-- Assignment

-- Project i is worked on by the player `offset` seats away from its owner.
function Round.assignByOffset(self: Round, offset: number)
	self.workers = {}
	local n = #self.players
	if n == 0 then return end
	local seatOf: { [number]: number } = {}
	for seat, player in self.players do
		seatOf[player.UserId] = seat
	end
	for _, project in self.projects do
		local ownerSeat = seatOf[project.ownerId] or (((project.index - 1) % n) + 1)
		local workerSeat = ((ownerSeat - 1 + offset) % n) + 1
		local worker = self.players[workerSeat]
		if self.workers[worker.UserId] then
			-- collision (someone left): first free player takes it
			for _, candidate in self.players do
				if not self.workers[candidate.UserId] then
					worker = candidate
					break
				end
			end
		end
		self.workers[worker.UserId] = { player = worker, projectIndex = project.index }
	end
end

-- VS Comic: directors alone for writing phases; every teammate draws one panel of their team's story.
function Round.assignTeams(self: Round, phase: Modes.Phase)
	self.workers = {}
	for t, project in self.projects do
		local members = self:teamMembers(t)
		if #members == 0 then continue end
		if phase.kind == "draw" then
			for slot, player in members do
				self.workers[player.UserId] = { player = player, projectIndex = t, panelSlot = slot }
			end
		else
			local director = Players:GetPlayerByUserId(project.ownerId) or members[1]
			self.workers[director.UserId] = { player = director, projectIndex = t }
		end
	end
end

function Round.assignEveryone(self: Round)
	self.workers = {}
	for _, player in self.players do
		self.workers[player.UserId] = { player = player, projectIndex = nil }
	end
end

-- Players who hold at least one role anywhere.
function Round.assignRoleHolders(self: Round)
	self.workers = {}
	for _, player in self.players do
		for _, project in self.projects do
			if #Projects.rolesOf(project, player.UserId) > 0 then
				self.workers[player.UserId] = { player = player, projectIndex = nil }
				break
			end
		end
	end
end

----------------------------------------------------------------------------
-- Payloads

function Round.rolesSnapshot(self: Round)
	local roles = {}
	for i, project in self.projects do
		roles[tostring(i)] = project.roles
	end
	return roles
end

function Round.payloadFor(self: Round, phase: Modes.Phase, worker: Worker)
	local kind = phase.kind
	local project = if worker.projectIndex then self.projects[worker.projectIndex] else nil

	if kind == "claim" then
		local list = {}
		local myTeam = self.teamOf[worker.player.UserId]
		for i, p in self.projects do
			if self.mode.teams and myTeam ~= i then continue end
			table.insert(list, {
				index = i,
				ownerId = p.ownerId,
				ownerName = p.ownerName,
				title = p.premise and p.premise.title or "Untitled",
				logline = p.premise and p.premise.logline or "",
				cast = p.cast,
			})
		end
		return { projects = list, roles = self:rolesSnapshot(), maxRoles = 2, shared = self.mode.teams == true, teamName = if myTeam then Round.teamName(myTeam) else nil }
	elseif kind == "dub" and phase.roles then
		local list = {}
		for _, p in self.projects do
			local mine = Projects.rolesOf(p, worker.player.UserId)
			if #mine > 0 then
				local ser = Projects.serialize(p, false)
				ser.myRoles = mine
				table.insert(list, ser)
			end
		end
		return { projects = list }
	end

	assert(project, "per-project phase without a project")
	if kind == "scenes" then
		local count = if self.mode.teams then #self:teamMembers(project.index) else #self.players
		return { projectIndex = project.index, premise = project.premise, cast = project.cast, count = count }
	elseif kind == "draw" and worker.panelSlot then
		return {
			projectIndex = project.index,
			panels = 1,
			startIndex = worker.panelSlot,
			premise = project.premise,
			cast = project.cast,
			roles = project.roles,
			lines = {},
			scene = project.scenes[worker.panelSlot],
			ownerName = project.ownerName,
			totalPanels = if self.mode.teams then #self:teamMembers(project.index) else #self.players,
		}
	end
	if kind == "premise" then
		return { projectIndex = project.index }
	elseif kind == "cast" then
		return { projectIndex = project.index, premise = project.premise, count = phase.count or 3 }
	elseif kind == "script" then
		return { projectIndex = project.index, premise = project.premise, cast = project.cast, roles = project.roles, panels = phase.panels or 3 }
	elseif kind == "draw" then
		local isChain = next(project.captions) ~= nil or (phase.offset > 1 and self.mode.id == "telephone")
		return {
			projectIndex = project.index,
			panels = phase.panels or 1,
			startIndex = #project.panels + 1,
			prompt = if isChain then Projects.latestPrompt(project) else nil,
			premise = if isChain then nil else project.premise,
			cast = if isChain then {} else project.cast,
			roles = if isChain then {} else project.roles,
			lines = if isChain then {} else project.lines,
			ownerName = project.ownerName,
		}
	elseif kind == "dub" then
		local ser = Projects.serialize(project, phase.blind == true)
		return { projects = { ser }, blind = phase.blind == true }
	elseif kind == "caption" then
		return { projectIndex = project.index, panel = project.panels[#project.panels], panelIndex = #project.panels }
	end
	return {}
end

----------------------------------------------------------------------------
-- Phase runner

function Round.runPhase(self: Round, phase: Modes.Phase)
	self:pruneLeavers()
	if #self.players == 0 then return end
	self.phase = phase
	self.pending = {}
	self.submissions = {}

	if phase.kind == "claim" then
		self:assignEveryone()
	elseif phase.kind == "dub" and phase.roles then
		self:assignRoleHolders()
		if next(self.workers) == nil then return end
	elseif self.mode.teams then
		self:assignTeams(phase)
	else
		self:assignByOffset(phase.offset)
	end
	self.live = {}
	self.spectators = {}

	local endsAt = now() + phase.duration
	local text = PHASE_TEXT[phase.kind] or { phase.kind, "" }
	for userId, worker in self.workers do
		self.pending[userId] = true
		Net.remote:FireClient(worker.player, Net.S2C.Phase, {
			kind = phase.kind,
			modeId = self.mode.id,
			title = text[1],
			instructions = text[2],
			endsAt = endsAt,
			payload = self:payloadFor(phase, worker),
		})
	end
	-- Players with nothing to do this phase wait, and can watch the artists live.
	local artists = {}
	if phase.kind == "draw" then
		for _, worker in self.workers do
			table.insert(artists, { userId = worker.player.UserId, name = worker.player.DisplayName, panels = phase.panels or 1 })
		end
	end
	for _, player in self.players do
		if not self.workers[player.UserId] then
			table.insert(self.spectators, player)
			Net.remote:FireClient(player, Net.S2C.Phase, {
				kind = "wait",
				title = if phase.kind == "draw" then "Watch the artists" else "Hang tight",
				instructions = if phase.kind == "draw" then "Nothing to draw this round. Watch everyone else work live." else "Others are busy. Your turn comes soon.",
				endsAt = endsAt,
				payload = { artists = artists, phaseKind = phase.kind },
			})
		end
	end

	local deadline = endsAt + Config.SUBMIT_GRACE_SECONDS
	while now() < deadline and next(self.pending) ~= nil do
		for userId in self.pending do
			if not Players:GetPlayerByUserId(userId) then
				self.pending[userId] = nil
			end
		end
		task.wait(0.25)
	end

	self:applyPhase(phase)
	self.phase = nil
end

function Round.applyPhase(self: Round, phase: Modes.Phase)
	if phase.kind == "claim" then
		-- Hand out whatever is still unclaimed.
		local roleCount: { [number]: number } = {}
		for _, project in self.projects do
			for _, r in project.roles do
				roleCount[r.userId] = (roleCount[r.userId] or 0) + 1
			end
		end
		for t, project in self.projects do
			local pool = if self.mode.teams then self:teamMembers(t) else self.players
			Projects.fillRoles(project, pool, roleCount)
		end
		for userId in self.workers do
			self.scores[userId] = (self.scores[userId] or 0) + Config.POINTS_FOR_SUBMITTING
		end
		return
	end

	for userId, worker in self.workers do
		local data = self.submissions[userId]
		local ok = false
		if phase.kind == "dub" and phase.roles then
			-- data: array of { projectIndex, panel, character, text }
			if typeof(data) == "table" then
				local byProject: { [number]: { any } } = {}
				for _, l in data do
					if typeof(l) == "table" then
						local idx = math.floor(tonumber(l.projectIndex) or 0)
						if self.projects[idx] then
							byProject[idx] = byProject[idx] or {}
							table.insert(byProject[idx], l)
						end
					end
				end
				for idx, lines in byProject do
					local project = self.projects[idx]
					local allowed: { [string]: boolean } = {}
					for _, name in Projects.rolesOf(project, userId) do allowed[name] = true end
					if Projects.applyLines(project, userId, lines, "dub", #project.panels, allowed) then ok = true end
				end
			end
		else
			local project = self.projects[worker.projectIndex :: number]
			if phase.kind == "premise" then
				ok = Projects.applyPremise(project, userId, data)
			elseif phase.kind == "cast" then
				ok = Projects.applyCast(project, userId, data, phase.count or 3)
			elseif phase.kind == "script" then
				ok = Projects.applyLines(project, userId, data, "script", phase.panels or 3)
			elseif phase.kind == "scenes" then
				local count = if self.mode.teams then #self:teamMembers(project.index) else #self.players
				ok = Projects.applyScenes(project, userId, data, count)
			elseif phase.kind == "draw" then
				-- Prefer the explicit submission; fall back to what streamed in live.
				if typeof(data) ~= "table" then
					data = self:liveAsSubmission(userId, phase.panels or 1)
				end
				if worker.panelSlot then
					local strokes = Strokes.sanitize(if typeof(data) == "table" then data[1] else nil) or {}
					Projects.setPanel(project, worker.panelSlot, userId, strokes)
					ok = #strokes > 0
				else
					local before = #project.panels
					ok = Projects.applyPanels(project, userId, data, phase.panels or 1)
					if #project.panels == before then
						Projects.applyBlankPanels(project, phase.panels or 1)
					end
				end
			elseif phase.kind == "dub" then
				ok = Projects.applyLines(project, userId, data, "dub", #project.panels)
			elseif phase.kind == "caption" then
				ok = Projects.applyCaption(project, userId, data)
			end
		end
		if ok then
			self.scores[userId] = (self.scores[userId] or 0) + Config.POINTS_FOR_SUBMITTING
		end
	end
end

----------------------------------------------------------------------------
-- Client messages

-- Stored raw; applied at phase end so players can re-submit until the timer runs out.
function Round.onSubmit(self: Round, player: Player, data: any)
	if not self.workers[player.UserId] then return end
	self.submissions[player.UserId] = data
	self.pending[player.UserId] = nil
	Net.remote:FireClient(player, Net.S2C.SubmitAck, true)
end

function Round.onAction(self: Round, player: Player, action: string, data: any)
	if action == Net.C2S.Claim then
		local phase = self.phase
		if not phase or phase.kind ~= "claim" or typeof(data) ~= "table" then return end
		local project = self.projects[math.floor(tonumber(data.projectIndex) or 0)]
		if not project or typeof(data.character) ~= "string" then return end
		if self.mode.teams then
			-- Only your own team's comic.
			if self.teamOf[player.UserId] ~= project.index then return end
		elseif project.ownerId == player.UserId and #self.players > 1 then
			-- Don't voice your own story if anyone else is around.
			return
		end
		-- Cap how many roles one person holds in a single project.
		local mine = Projects.rolesOf(project, player.UserId)
		local holding = table.find(mine, data.character) ~= nil
		if not holding and #mine >= 2 then return end
		if Projects.toggleRole(project, player.UserId, player.DisplayName, data.character) then
			self:broadcast(Net.S2C.ClaimState, { roles = self:rolesSnapshot() })
		end
	elseif action == Net.C2S.Stroke then
		self:onStroke(player, data)
	elseif action == Net.C2S.ShowcaseNext then
		if self.currentActorId == player.UserId then
			self.skipRequested = true
		end
	elseif action == Net.C2S.SkipStory then
		if not self.showingProject then return end
		self.skipStoryVotes[player.UserId] = true
		self:checkSkipStory()
	end
end

----------------------------------------------------------------------------
-- Live drawing: every stroke is mirrored to the server as it happens so a
-- disconnect loses nothing, and spectators can watch.

function Round.onStroke(self: Round, player: Player, data: any)
	local phase = self.phase
	local worker = self.workers[player.UserId]
	if not phase or phase.kind ~= "draw" or not worker or typeof(data) ~= "table" then return end
	local panel = math.floor(tonumber(data.panel) or 0)
	if panel < 1 or panel > (phase.panels or 1) then return end
	local buffers = self.live[player.UserId] or {}
	self.live[player.UserId] = buffers
	local list = buffers[panel] or {}
	buffers[panel] = list

	local op = data.op
	local out: any = { artistId = player.UserId, artistName = player.DisplayName, panel = panel, op = op }
	if op == "add" then
		local stroke = Strokes.sanitizeOne(data.stroke)
		if not stroke or #list >= Config.MAX_STROKES_PER_PANEL then return end
		table.insert(list, stroke)
		out.stroke = stroke
	elseif op == "undo" then
		table.remove(list)
	elseif op == "clear" then
		buffers[panel] = {}
	elseif op == "set" then
		-- Transform tools rewrite the whole panel.
		buffers[panel] = Strokes.sanitize(data.strokes) or {}
		out.strokes = buffers[panel]
	else
		return
	end
	for _, spectator in self.spectators do
		if spectator.Parent then
			Net.remote:FireClient(spectator, Net.S2C.LiveStroke, out)
		end
	end
end

function Round.liveAsSubmission(self: Round, userId: number, panels: number): any
	local buffers = self.live[userId]
	if not buffers then return nil end
	local out = {}
	for i = 1, panels do out[i] = buffers[i] or {} end
	return out
end

function Round.skipNeeded(self: Round): number
	return math.max(1, math.floor(#self.players / 2) + 1)
end

function Round.checkSkipStory(self: Round)
	local votes = 0
	for userId in self.skipStoryVotes do
		if Players:GetPlayerByUserId(userId) then votes += 1 end
	end
	local needed = self:skipNeeded()
	self:broadcast(Net.S2C.SkipState, { projectIndex = self.showingProject, votes = votes, needed = needed })
	if votes >= needed then
		self.skipStory = true
		self.skipRequested = true
	end
end

-- Host kicked someone (or they left): stop waiting on them.
function Round.removePlayer(self: Round, player: Player)
	local i = table.find(self.players, player)
	if i then table.remove(self.players, i) end
	self.workers[player.UserId] = nil
	self.pending[player.UserId] = nil
	self.skipStoryVotes[player.UserId] = nil
	if self.currentActorId == player.UserId then
		self.skipRequested = true
	end
	if self.showingProject then self:checkSkipStory() end
end

----------------------------------------------------------------------------
-- Showcase

function Round.finalize(self: Round)
	for _, project in self.projects do
		if not project.premise then
			project.premise = { title = "Untitled", logline = "", authorId = project.ownerId, authorName = project.ownerName }
		end
		if #project.cast == 0 then
			project.cast = { { name = "Mystery Guest", trait = "no one knows who they are" } }
		end
		if #project.panels == 0 then
			Projects.applyBlankPanels(project, 1)
		end
	end
end

-- Lines to perform on a panel: dub lines if any, else script lines. Each carries its actor.
local function linesFor(project: Projects.Project, panelIndex: number)
	local dub, script = {}, {}
	for _, l in project.lines do
		if l.panel == panelIndex then
			table.insert(if l.source == "dub" then dub else script, l)
		end
	end
	local chosen = if #dub > 0 then dub else script
	local out = {}
	for _, l in chosen do
		local role = project.roles[l.character]
		local actorId = if role then role.userId elseif l.source == "dub" then l.authorId else nil
		local actorName = if role then role.name elseif l.source == "dub" then l.authorName else nil
		table.insert(out, { character = l.character, text = l.text, actorId = actorId, actorName = actorName })
	end
	return out
end

local function framesFor(mode: Modes.Mode, project: Projects.Project)
	local isBlind = false
	for _, phase in mode.phases do
		if phase.kind == "dub" and phase.blind then isBlind = true end
	end
	local frames = {}
	table.insert(frames, { kind = "title", blind = isBlind, seconds = Config.SHOWCASE_TITLE_SECONDS })
	for i = 1, #project.panels do
		local lines = linesFor(project, i)
		table.insert(frames, {
			kind = "panel",
			panel = i,
			lines = lines,
			seconds = if #lines == 0 then Config.SHOWCASE_PANEL_SECONDS else 1.5 + #lines * Config.SHOWCASE_LINE_SECONDS,
		})
	end
	if isBlind then
		table.insert(frames, { kind = "reveal", seconds = Config.SHOWCASE_REVEAL_SECONDS })
	end
	return frames
end

-- Wait up to `seconds`, returning early if the current actor presses Next.
function Round.waitOrSkip(self: Round, seconds: number)
	local deadline = now() + seconds
	self.skipRequested = false
	while now() < deadline do
		if self.skipRequested then break end
		task.wait(0.1)
	end
	self.skipRequested = false
end

function Round.showcase(self: Round)
	self:pruneLeavers()
	self:finalize()
	local serialized = {}
	for i, project in self.projects do
		serialized[i] = Projects.serialize(project, false)
		serialized[i].frames = framesFor(self.mode, project)
	end
	self:broadcast(Net.S2C.Showcase, {
		modeId = self.mode.id,
		liveDub = self.mode.liveDub,
		lineSeconds = Config.SHOWCASE_LINE_SECONDS,
		projects = serialized,
	})
	task.wait(1.5)

	for projectIndex in self.projects do
		self.showingProject = projectIndex
		self.skipStoryVotes = {}
		self.skipStory = false
		self:broadcast(Net.S2C.SkipState, { projectIndex = projectIndex, votes = 0, needed = self:skipNeeded() })
		for frameIndex, frame in serialized[projectIndex].frames do
			if self.skipStory then break end
			if frame.kind == "panel" and #frame.lines > 0 then
				-- Settle on the picture first, then one line at a time.
				self.currentActorId = nil
				self:broadcast(Net.S2C.ShowcaseFocus, { projectIndex = projectIndex, frameIndex = frameIndex, lineIndex = 0, endsAt = now() + 1.5 })
				task.wait(1.5)
				for lineIndex, line in frame.lines do
					if self.skipStory then break end
					self.currentActorId = line.actorId
					self:broadcast(Net.S2C.ShowcaseFocus, {
						projectIndex = projectIndex,
						frameIndex = frameIndex,
						lineIndex = lineIndex,
						endsAt = now() + Config.SHOWCASE_LINE_SECONDS,
					})
					self:waitOrSkip(Config.SHOWCASE_LINE_SECONDS)
				end
				self.currentActorId = nil
			else
				self.currentActorId = nil
				self:broadcast(Net.S2C.ShowcaseFocus, { projectIndex = projectIndex, frameIndex = frameIndex, lineIndex = 0, endsAt = now() + frame.seconds })
				self:waitOrSkip(frame.seconds)
			end
		end
		if self.skipStory then
			self.skipped[projectIndex] = true
			self:broadcast(Net.S2C.Toast, "Story skipped.")
			task.wait(0.8)
		end
	end
	self.showingProject = nil
end

----------------------------------------------------------------------------
-- Voting and results

-- Stories that actually played and can be voted on.
function Round.voteCandidates(self: Round): { number }
	local out = {}
	for i in self.projects do
		if not self.skipped[i] then table.insert(out, i) end
	end
	return out
end

-- Can this player vote for this project? Not their own story / their own team's comic.
function Round.canVoteFor(self: Round, player: Player, projectIndex: number): boolean
	local project = self.projects[projectIndex]
	if not project or self.skipped[projectIndex] then return false end
	if self.mode.teams then
		return self.teamOf[player.UserId] ~= projectIndex
	end
	return project.ownerId ~= player.UserId
end

function Round.vote(self: Round)
	self:pruneLeavers()
	local candidates = self:voteCandidates()
	-- Nothing to choose between: one story, or nobody else to vote for yours.
	if #candidates < 2 or #self.players < 2 then
		return {}
	end
	local endsAt = now() + Config.VOTE_SECONDS
	local summaries = {}
	for _, i in candidates do
		local project = self.projects[i]
		local actors = {}
		for _, r in project.roles do
			if not table.find(actors, r.name) then table.insert(actors, r.name) end
		end
		table.insert(summaries, {
			index = i,
			title = if project.premise then project.premise.title else "Untitled",
			ownerName = project.ownerName,
			mine = false, -- filled per client below
			teamColor = if self.mode.teams and Config.TEAM_COLORS[i] then Config.TEAM_COLORS[i] else nil,
			actors = actors,
			thumbnail = project.panels[1] and project.panels[1].strokes or {},
		})
	end
	for _, player in self.players do
		if not player.Parent then continue end
		local mine = {}
		for _, sm in summaries do
			mine[tostring(sm.index)] = not self:canVoteFor(player, sm.index)
		end
		Net.remote:FireClient(player, Net.S2C.Vote, { awards = AWARDS, projects = summaries, mine = mine, endsAt = endsAt })
	end

	local votes: { [number]: { [string]: number } } = {}
	local conn = Net.remote.OnServerEvent:Connect(function(player, action, data)
		if action ~= Net.C2S.Vote or typeof(data) ~= "table" then return end
		if not table.find(self.players, player) then return end
		local ballot: { [string]: number } = {}
		for _, award in AWARDS do
			local idx = tonumber(data[award.id])
			if idx and self:canVoteFor(player, idx) then
				ballot[award.id] = idx
			end
		end
		votes[player.UserId] = ballot
	end)
	table.insert(self.connections, conn)

	local deadline = endsAt + 1
	while now() < deadline do
		local allIn = true
		for _, p in self.players do
			if p.Parent and not votes[p.UserId] then allIn = false break end
		end
		if allIn then break end
		task.wait(0.25)
	end
	conn:Disconnect()

	local tally: { [string]: { [number]: number } } = {}
	for _, award in AWARDS do tally[award.id] = {} end
	for _, ballot in votes do
		for awardId, idx in ballot do
			tally[awardId][idx] = (tally[awardId][idx] or 0) + 1
		end
	end
	local winners = {}
	for _, award in AWARDS do
		local bestIdx, bestCount = nil, 0
		for idx, count in tally[award.id] do
			if count > bestCount then bestIdx, bestCount = idx, count end
		end
		if bestIdx then
			local project = self.projects[bestIdx]
			winners[award.id] = { projectIndex = bestIdx, votes = bestCount, title = project.premise and project.premise.title or "Untitled" }
			local recipients: { [number]: boolean } = {}
			if self.mode.teams then
				for _, p in self:teamMembers(bestIdx) do recipients[p.UserId] = true end
			elseif award.id == "best_dub" then
				for _, r in project.roles do recipients[r.userId] = true end
				if project.dubberId then recipients[project.dubberId] = true end
			else
				for userId in project.submittedBy do recipients[userId] = true end
				recipients[project.ownerId] = true
			end
			for userId in recipients do
				self.scores[userId] = (self.scores[userId] or 0) + Config.POINTS_PER_VOTE * bestCount
			end
		end
	end
	return winners
end

function Round.results(self: Round, winners: any)
	local board = {}
	for userId, score in self.scores do
		local player = Players:GetPlayerByUserId(userId)
		table.insert(board, { userId = userId, name = if player then player.DisplayName else "Left", score = score })
	end
	table.sort(board, function(a, b) return a.score > b.score end)
	Points.awardRound(self.scores)
	self:broadcast(Net.S2C.Results, { board = board, winners = winners, awards = AWARDS, endsAt = now() + Config.RESULTS_SECONDS })
	task.wait(Config.RESULTS_SECONDS)
end

function Round.destroy(self: Round)
	for _, c in self.connections do c:Disconnect() end
	table.clear(self.connections)
end

return Round
