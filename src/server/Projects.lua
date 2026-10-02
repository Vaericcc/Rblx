--!strict
--[[
	A Project is one storyboard. One is created per player at the start of a
	round and every phase of the mode adds to it.
]]
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Text = require(Shared.Text)
local Strokes = require(Shared.Strokes)
local Filter = require(script.Parent.Filter)

export type Character = { name: string, trait: string }
export type Panel = { strokes: { Strokes.Stroke }, authorId: number, authorName: string }
export type Line = { panel: number, character: string, text: string, authorId: number, authorName: string, source: string }
export type Caption = { text: string, authorId: number, authorName: string }

export type Project = {
	index: number,
	ownerId: number,
	ownerName: string,
	premise: { title: string, logline: string, authorId: number, authorName: string }?,
	cast: { Character },
	castAuthorName: string?,
	panels: { Panel },
	lines: { Line },
	captions: { [string]: Caption }, -- keyed by tostring(panelIndex): sparse numeric keys don't survive RemoteEvents
	roles: { [string]: { userId: number, name: string } }, -- character name -> voice actor
	dubberName: string?,
	dubberId: number?,
	submittedBy: { [number]: boolean }, -- userIds that contributed anything (for participation points)
}

local Projects = {}

function Projects.new(index: number, owner: Player): Project
	return {
		index = index,
		ownerId = owner.UserId,
		ownerName = owner.DisplayName,
		premise = nil,
		cast = {},
		castAuthorName = nil,
		panels = {},
		lines = {},
		captions = {},
		roles = {},
		dubberName = nil,
		dubberId = nil,
		submittedBy = {},
	}
end

local function nameOf(userId: number): string
	local p = Players:GetPlayerByUserId(userId)
	return if p then p.DisplayName else "Someone"
end

-- Every apply* function takes untrusted client data and stores a sanitized,
-- filtered version. They return true when something usable was stored.

function Projects.applyPremise(project: Project, userId: number, data: any): boolean
	if typeof(data) ~= "table" then return false end
	local title = Text.clean(data.title, Config.MAX_TITLE_LEN)
	local logline = Text.clean(data.logline, Config.MAX_LOGLINE_LEN)
	if title == "" and logline == "" then return false end
	project.premise = {
		title = Filter.forBroadcast(Text.orDefault(title, "Untitled"), userId),
		logline = Filter.forBroadcast(logline, userId),
		authorId = userId,
		authorName = nameOf(userId),
	}
	project.submittedBy[userId] = true
	return true
end

function Projects.applyCast(project: Project, userId: number, data: any, maxCount: number): boolean
	if typeof(data) ~= "table" then return false end
	local cast: { Character } = {}
	for i = 1, math.min(#data, maxCount) do
		local c = data[i]
		if typeof(c) ~= "table" then continue end
		local name = Text.clean(c.name, Config.MAX_CHAR_NAME_LEN)
		local trait = Text.clean(c.trait, Config.MAX_CHAR_TRAIT_LEN)
		if name == "" then continue end
		table.insert(cast, {
			name = Filter.forBroadcast(name, userId),
			trait = Filter.forBroadcast(trait, userId),
		})
	end
	if #cast == 0 then return false end
	project.cast = cast
	project.castAuthorName = nameOf(userId)
	project.submittedBy[userId] = true
	return true
end

-- data: { [panelOffset] = strokes } where panelOffset is 1..N for this phase
function Projects.applyPanels(project: Project, userId: number, data: any, count: number): boolean
	if typeof(data) ~= "table" then return false end
	local any = false
	for i = 1, count do
		local strokes = Strokes.sanitize(data[i]) or {}
		if #strokes > 0 then any = true end
		table.insert(project.panels, {
			strokes = strokes,
			authorId = userId,
			authorName = nameOf(userId),
		})
	end
	if any then
		project.submittedBy[userId] = true
	end
	return any
end

-- Called when a drawer never submitted: keep panel numbering consistent.
function Projects.applyBlankPanels(project: Project, count: number)
	for _ = 1, count do
		table.insert(project.panels, { strokes = {}, authorId = 0, authorName = "nobody" })
	end
end

-- data: array of { panel = n, character = "Name", text = "..." }
-- `allowed` restricts which characters this author may write for (role-based dubbing).
function Projects.applyLines(project: Project, userId: number, data: any, source: string, maxPanel: number, allowed: { [string]: boolean }?): boolean
	if typeof(data) ~= "table" then return false end
	local castNames: { [string]: boolean } = {}
	for _, c in project.cast do
		castNames[c.name] = true
	end
	local added = 0
	for i = 1, math.min(#data, maxPanel * 8) do
		local l = data[i]
		if typeof(l) ~= "table" then continue end
		local panel = math.floor(tonumber(l.panel) or 0)
		if panel < 1 or panel > maxPanel then continue end
		local text = Text.clean(l.text, Config.MAX_LINE_LEN)
		if text == "" then continue end
		local character = Text.clean(l.character, Config.MAX_CHAR_NAME_LEN)
		if allowed then
			if not allowed[character] then continue end
		elseif not castNames[character] then
			-- Blind dubbers may invent character names; everyone else must use the cast.
			character = Filter.forBroadcast(Text.orDefault(character, "???"), userId)
		end
		table.insert(project.lines, {
			panel = panel,
			character = character,
			text = Filter.forBroadcast(text, userId),
			authorId = userId,
			authorName = nameOf(userId),
			source = source,
		})
		added += 1
	end
	if added > 0 then
		project.submittedBy[userId] = true
		if source == "dub" then
			project.dubberId = userId
			project.dubberName = nameOf(userId)
		end
	end
	return added > 0
end

function Projects.applyCaption(project: Project, userId: number, data: any): boolean
	if typeof(data) ~= "table" then return false end
	local text = Text.clean(data.text, Config.MAX_CAPTION_LEN)
	if text == "" then return false end
	local panelIndex = #project.panels
	if panelIndex == 0 then return false end
	project.captions[tostring(panelIndex)] = {
		text = Filter.forBroadcast(text, userId),
		authorId = userId,
		authorName = nameOf(userId),
	}
	project.submittedBy[userId] = true
	return true
end

-- Toggle a role claim. Returns true if the state changed.
function Projects.toggleRole(project: Project, userId: number, name: string, character: string): boolean
	local valid = false
	for _, c in project.cast do
		if c.name == character then valid = true end
	end
	if not valid then return false end
	local current = project.roles[character]
	if current and current.userId == userId then
		project.roles[character] = nil
		return true
	end
	if current then return false end -- someone else holds it
	project.roles[character] = { userId = userId, name = name }
	return true
end

-- Characters this player voices in this project.
function Projects.rolesOf(project: Project, userId: number): { string }
	local out = {}
	for _, c in project.cast do
		local r = project.roles[c.name]
		if r and r.userId == userId then table.insert(out, c.name) end
	end
	return out
end

-- Give every unclaimed character to someone. Prefers people who aren't the owner
-- and have the fewest roles so far.
function Projects.fillRoles(project: Project, players: { Player }, roleCount: { [number]: number })
	for _, c in project.cast do
		if project.roles[c.name] then continue end
		local best: Player? = nil
		local bestScore = math.huge
		for _, p in players do
			local score = (roleCount[p.UserId] or 0) + (if p.UserId == project.ownerId and #players > 1 then 100 else 0)
			if score < bestScore then best, bestScore = p, score end
		end
		if best then
			project.roles[c.name] = { userId = best.UserId, name = best.DisplayName }
			roleCount[best.UserId] = (roleCount[best.UserId] or 0) + 1
		end
	end
end

-- What the latest caption (or the premise if none) says. Used for telephone draws.
function Projects.latestPrompt(project: Project): string
	local caption = project.captions[tostring(#project.panels)]
	if caption then
		return caption.text
	end
	if project.premise then
		return project.premise.title .. " - " .. project.premise.logline
	end
	return "Draw anything!"
end

-- A serializable view of the project for the showcase. `blind` hides the
-- premise/cast (used while the dubber is working on a Blind Dub).
function Projects.serialize(project: Project, blind: boolean?)
	return {
		index = project.index,
		ownerName = project.ownerName,
		premise = if blind then nil else project.premise,
		cast = if blind then {} else project.cast,
		castAuthorName = project.castAuthorName,
		panels = project.panels,
		lines = project.lines,
		captions = project.captions,
		roles = if blind then {} else project.roles,
		dubberName = project.dubberName,
	}
end

return Projects
