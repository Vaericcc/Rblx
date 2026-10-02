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

local Round = {}
Round.__index = Round

export type Round = typeof(setmetatable({} :: {
	mode: Modes.Mode,
	players: { Player },
	projects: { Projects.Project },
	scores: { [number]: number },
	phaseIndex: number,
	-- current phase bookkeeping
	assignments: { [number]: number }, -- userId -> project index they're working on
	pending: { [number]: boolean }, -- userId -> still waiting on their submission
	submissions: { [number]: any }, -- userId -> raw data
	connections: { RBXScriptConnection },
}, Round))

local AWARDS = {
	{ id = "funniest", name = "Funniest", emoji = "😂" },
	{ id = "best_art", name = "Best Art", emoji = "🎨" },
	{ id = "best_dub", name = "Best Dub", emoji = "🎤" },
	{ id = "plot_twist", name = "Plot Twist", emoji = "🌀" },
}

local function now(): number
	return workspace:GetServerTimeNow()
end

function Round.new(mode: Modes.Mode, players: { Player }): Round
	local self = setmetatable({}, Round)
	self.mode = mode
	self.players = players
	self.projects = {}
	self.scores = {}
	self.phaseIndex = 0
	self.assignments = {}
	self.pending = {}
	self.submissions = {}
	self.connections = {}
	for i, player in players do
		self.projects[i] = Projects.new(i, player)
		self.scores[player.UserId] = 0
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

-- Drop players who left so assignments only point at people who can submit.
function Round.pruneLeavers(self: Round)
	for i = #self.players, 1, -1 do
		if not self.players[i].Parent then
			table.remove(self.players, i)
		end
	end
end

-- Project i is worked on by the player `offset` seats away from its owner.
function Round.assign(self: Round, offset: number)
	self.assignments = {}
	local n = #self.players
	if n == 0 then return end
	-- Build owner order from projects (projects keep original seats even if someone left).
	local seatOf: { [number]: number } = {}
	for seat, player in self.players do
		seatOf[player.UserId] = seat
	end
	for _, project in self.projects do
		local ownerSeat = seatOf[project.ownerId]
		if not ownerSeat then
			-- owner left: hand their project to whoever sits where they would have
			ownerSeat = ((project.index - 1) % n) + 1
		end
		local workerSeat = ((ownerSeat - 1 + offset) % n) + 1
		local worker = self.players[workerSeat]
		-- If two projects collide on the same worker (because people left), pick the first free player.
		if self.assignments[worker.UserId] then
			for _, candidate in self.players do
				if not self.assignments[candidate.UserId] then
					worker = candidate
					break
				end
			end
		end
		self.assignments[worker.UserId] = project.index
	end
end

-- Build what each worker needs to see for this phase.
function Round.payloadFor(self: Round, phase: Modes.Phase, project: Projects.Project)
	local kind = phase.kind
	if kind == "premise" then
		return { projectIndex = project.index }
	elseif kind == "cast" then
		return { projectIndex = project.index, premise = project.premise, count = phase.count or 3 }
	elseif kind == "script" then
		return { projectIndex = project.index, premise = project.premise, cast = project.cast, panels = phase.panels or 3 }
	elseif kind == "draw" then
		local isChain = next(project.captions) ~= nil or (phase.offset > 1 and self.mode.id == "telephone")
		return {
			projectIndex = project.index,
			panels = phase.panels or 1,
			startIndex = #project.panels + 1,
			-- Telephone drawers see only the latest caption, nobody else's work.
			prompt = if isChain then Projects.latestPrompt(project) else nil,
			premise = if isChain then nil else project.premise,
			cast = if isChain then {} else project.cast,
			lines = if isChain then {} else project.lines,
			ownerName = project.ownerName,
		}
	elseif kind == "dub" then
		return {
			projectIndex = project.index,
			blind = phase.blind == true,
			project = Projects.serialize(project, phase.blind == true),
		}
	elseif kind == "caption" then
		local lastPanel = project.panels[#project.panels]
		return {
			projectIndex = project.index,
			panel = lastPanel,
			panelIndex = #project.panels,
		}
	end
	return { projectIndex = project.index }
end

local PHASE_TEXT = {
	premise = { "Write your premise", "Give your story a title and a one-sentence hook." },
	cast = { "Create the cast", "Invent the characters. Name them and give each one a defining trait." },
	script = { "Write the script", "Write what each character says, panel by panel. Someone else will draw it." },
	draw = { "Draw!", "Bring the story to life. Fill every panel." },
	dub = { "Dub it", "Put words in their mouths. During the showcase you'll perform these lines." },
	caption = { "Describe what you see", "You only get the drawing. In one sentence, what is happening?" },
}

function Round.runPhase(self: Round, phase: Modes.Phase)
	self:pruneLeavers()
	if #self.players == 0 then return end
	self:assign(phase.offset)
	self.pending = {}
	self.submissions = {}

	local endsAt = now() + phase.duration
	local text = PHASE_TEXT[phase.kind] or { phase.kind, "" }

	for _, player in self.players do
		local projectIndex = self.assignments[player.UserId]
		if not projectIndex then continue end
		self.pending[player.UserId] = true
		local project = self.projects[projectIndex]
		Net.remote:FireClient(player, Net.S2C.Phase, {
			kind = phase.kind,
			modeId = self.mode.id,
			title = text[1],
			instructions = text[2],
			endsAt = endsAt,
			payload = self:payloadFor(phase, project),
		})
	end

	-- Collect submissions until everyone is in or the timer (plus grace) runs out.
	local deadline = endsAt + Config.SUBMIT_GRACE_SECONDS
	while now() < deadline and next(self.pending) ~= nil do
		-- Players who leave mid-phase stop blocking.
		for userId in self.pending do
			if not Players:GetPlayerByUserId(userId) then
				self.pending[userId] = nil
			end
		end
		task.wait(0.25)
	end

	-- Apply whatever arrived.
	for userId, projectIndex in self.assignments do
		local project = self.projects[projectIndex]
		local data = self.submissions[userId]
		local ok = false
		if phase.kind == "premise" then
			ok = Projects.applyPremise(project, userId, data)
		elseif phase.kind == "cast" then
			ok = Projects.applyCast(project, userId, data, phase.count or 3)
		elseif phase.kind == "script" then
			ok = Projects.applyLines(project, userId, data, "script", phase.panels or 3)
		elseif phase.kind == "draw" then
			local before = #project.panels
			ok = Projects.applyPanels(project, userId, data, phase.panels or 1)
			if #project.panels == before then
				-- Nothing arrived from this drawer; keep panel numbering consistent.
				Projects.applyBlankPanels(project, phase.panels or 1)
			end
		elseif phase.kind == "dub" then
			ok = Projects.applyLines(project, userId, data, "dub", #project.panels)
		elseif phase.kind == "caption" then
			ok = Projects.applyCaption(project, userId, data)
		end
		if ok then
			self.scores[userId] = (self.scores[userId] or 0) + Config.POINTS_FOR_SUBMITTING
		end
	end
end

-- Called by Main when a client submits. Stored raw; applied at phase end so
-- a player can re-submit (e.g. edit) until the timer runs out.
function Round.onSubmit(self: Round, player: Player, data: any)
	if self.assignments[player.UserId] == nil then return end
	self.submissions[player.UserId] = data
	self.pending[player.UserId] = nil
	Net.remote:FireClient(player, Net.S2C.SubmitAck, true)
end

-- Fill holes so the showcase never shows a broken project.
function Round.finalize(self: Round)
	for _, project in self.projects do
		if not project.premise then
			project.premise = {
				title = "Untitled",
				logline = "",
				authorId = project.ownerId,
				authorName = project.ownerName,
			}
		end
		if #project.cast == 0 then
			project.cast = { { name = "Mystery Guest", trait = "no one knows who they are" } }
		end
		if #project.panels == 0 then
			Projects.applyBlankPanels(project, 1)
		end
	end
end

-- Build the ordered list of showcase frames for one project.
local function framesFor(mode: Modes.Mode, project: Projects.Project)
	local frames = {}
	local isBlind = false
	for _, phase in mode.phases do
		if phase.kind == "dub" and phase.blind then isBlind = true end
	end
	table.insert(frames, { kind = "title", blind = isBlind, seconds = Config.SHOWCASE_TITLE_SECONDS })
	for i = 1, #project.panels do
		table.insert(frames, { kind = "panel", panel = i, seconds = Config.SHOWCASE_PANEL_SECONDS })
	end
	if isBlind then
		table.insert(frames, { kind = "reveal", seconds = Config.SHOWCASE_REVEAL_SECONDS })
	end
	return frames
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
		projects = serialized,
	})
	task.wait(1.5)
	for projectIndex, project in self.projects do
		for frameIndex, frame in serialized[projectIndex].frames do
			self:broadcast(Net.S2C.ShowcaseFocus, {
				projectIndex = projectIndex,
				frameIndex = frameIndex,
				endsAt = now() + frame.seconds,
			})
			task.wait(frame.seconds)
		end
	end
end

function Round.vote(self: Round)
	self:pruneLeavers()
	local endsAt = now() + Config.VOTE_SECONDS
	local summaries = {}
	for i, project in self.projects do
		summaries[i] = {
			index = i,
			title = if project.premise then project.premise.title else "Untitled",
			ownerName = project.ownerName,
			dubberName = project.dubberName,
			thumbnail = project.panels[1] and project.panels[1].strokes or {},
		}
	end
	self:broadcast(Net.S2C.Vote, { awards = AWARDS, projects = summaries, endsAt = endsAt })

	local votes: { [number]: { [string]: number } } = {} -- userId -> awardId -> projectIndex
	local conn = Net.remote.OnServerEvent:Connect(function(player, action, data)
		if action ~= Net.C2S.Vote or typeof(data) ~= "table" then return end
		if not table.find(self.players, player) then return end
		local ballot: { [string]: number } = {}
		for _, award in AWARDS do
			local idx = tonumber(data[award.id])
			if idx and self.projects[idx] and self.projects[idx].ownerId ~= player.UserId then
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

	-- Tally
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
			-- Points: owner always; dubber for Best Dub; every contributor for the rest.
			local recipients: { [number]: boolean } = {}
			if award.id == "best_dub" and project.dubberId then
				recipients[project.dubberId] = true
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
	self:broadcast(Net.S2C.Results, {
		board = board,
		winners = winners,
		awards = AWARDS,
		endsAt = now() + Config.RESULTS_SECONDS,
	})
	task.wait(Config.RESULTS_SECONDS)
end

function Round.destroy(self: Round)
	for _, c in self.connections do c:Disconnect() end
	table.clear(self.connections)
end

return Round
