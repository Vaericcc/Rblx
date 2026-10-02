--!strict
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Layout = require(UI.Layout)

local Results = {}

function Results.show(container: Frame, data: any, ctx: any)
	ctx.hud:set("Results", "Back to the hub in a moment.", data.endsAt, false)
	local root = Layout.form(container)

	local awards = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 8), Parent = root })
	Make.heading("Awards", 22, { Parent = awards })
	if next(data.winners) == nil then
		Make.label("No awards this round: you need at least two stories and two players to vote.", 14, {
			TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = awards,
		})
	end
	for _, award in data.awards do
		local w = data.winners[award.id]
		if next(data.winners) == nil then continue end
		local text = if w
			then ("%s <b>%s</b>  <font color=\"#aaaabe\">“%s” · %d vote%s</font>"):format(award.emoji, award.name, w.title, w.votes, if w.votes == 1 then "" else "s")
			else ("%s <b>%s</b>  <font color=\"#aaaabe\">no votes</font>"):format(award.emoji, award.name)
		Make.label(text, 16, { RichText = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = awards })
	end

	local board = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 6), Parent = root })
	Make.heading("Leaderboard", 22, { Parent = board })
	for i, entry in data.board do
		local medal = ({ "🥇", "🥈", "🥉" })[i] or ("%d."):format(i)
		Make.label(("%s  <b>%s</b>  <font color=\"#ffc43d\">%d</font>"):format(medal, entry.name, entry.score), 17, {
			RichText = true, Size = UDim2.new(1, 0, 0, 26), Parent = board,
		})
	end

	return { collect = nil, destroy = function() container:ClearAllChildren() end }
end

return Results
