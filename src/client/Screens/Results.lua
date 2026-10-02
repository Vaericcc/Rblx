--!strict
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)

local Results = {}

function Results.show(container: Frame, data: any, ctx: any)
	ctx.hud:set("Results", "Next round starts soon.", data.endsAt, false)
	local root = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })

	local awards = Make.card({ Size = UDim2.new(0.5, -8, 1, 0), Make.list(nil, 10), Parent = root })
	Make.heading("Awards", 24, { Parent = awards })
	for _, award in data.awards do
		local w = data.winners[award.id]
		local text = if w
			then ("%s <b>%s</b>  <font color=\"#aaaabe\">“%s” · %d vote%s</font>"):format(award.emoji, award.name, w.title, w.votes, if w.votes == 1 then "" else "s")
			else ("%s <b>%s</b>  <font color=\"#aaaabe\">no votes</font>"):format(award.emoji, award.name)
		Make.label(text, 17, { RichText = true, Size = UDim2.new(1, 0, 0, 30), Parent = awards })
	end

	local board = Make.card({ Size = UDim2.new(0.5, -8, 1, 0), Position = UDim2.new(0.5, 8, 0, 0), Make.list(nil, 6), Parent = root })
	Make.heading("Leaderboard", 24, { Parent = board })
	for i, entry in data.board do
		local medal = ({ "🥇", "🥈", "🥉" })[i] or ("%d."):format(i)
		Make.label(("%s  <b>%s</b>  <font color=\"#ffc43d\">%d</font>"):format(medal, entry.name, entry.score), 18, {
			RichText = true, Size = UDim2.new(1, 0, 0, 28), Parent = board,
		})
	end

	return { collect = nil, destroy = function() root:Destroy() end }
end

return Results
