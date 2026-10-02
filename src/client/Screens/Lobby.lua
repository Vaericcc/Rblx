--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)

local Lobby = {}

function Lobby.show(container: Frame, data: any, ctx: any)
	local myVote: string? = ctx.lobbyVote
	local statusText = if data.status == "voting"
		then "Vote for a mode! Round starts when the timer ends."
		else ("Waiting for players... (%d/%d)"):format(data.players, data.minPlayers)
	ctx.hud:set("StoryDub", statusText, data.endsAt, false)

	local grid = Make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Make("UIGridLayout", {
			CellSize = UDim2.new(0.5, -8, 0, 150),
			CellPadding = UDim2.new(0, 12, 0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Parent = container,
	})

	for i, mode in data.modes do
		local votes = data.votes[mode.id] or 0
		local locked = data.players < mode.minPlayers
		local selected = myVote == mode.id
		local card = Make.card({
			LayoutOrder = i,
			BackgroundColor3 = if selected then Theme.panelAlt else Theme.panel,
			Make.list(nil, 4),
			Make("UIStroke", { Color = Theme.accent, Thickness = if selected then 2 else 0 }),
			Parent = grid,
		})
		Make.heading(("%s  <font color=\"#ffc43d\">%s</font>"):format(mode.name, if votes > 0 then ("· %d"):format(votes) else ""), 20, { RichText = true, Parent = card })
		Make.label(mode.tagline, 14, { TextColor3 = Theme.accent2, Parent = card })
		Make.label(mode.description, 13, { TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 50), Parent = card })
		if locked then
			Make.label(("Needs %d players"):format(mode.minPlayers), 12, { TextColor3 = Theme.danger, Parent = card })
		end
		local btn = Make("TextButton", {
			BackgroundTransparency = 1,
			Text = "",
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(-14, -14),
			ZIndex = 5,
			Parent = card,
		})
		btn.Activated:Connect(function()
			if locked then return end
			ctx.lobbyVote = mode.id
			Net.remote:FireServer(Net.C2S.VoteMode, mode.id)
			-- Re-render immediately for feedback
			for _, child in grid:GetChildren() do
				if child:IsA("Frame") then
					local stroke = child:FindFirstChildOfClass("UIStroke")
					if stroke then stroke.Thickness = 0 end
					child.BackgroundColor3 = Theme.panel
				end
			end
			card.BackgroundColor3 = Theme.panelAlt
			local stroke = card:FindFirstChildOfClass("UIStroke")
			if stroke then stroke.Thickness = 2 end
		end)
	end

	return { collect = nil, destroy = function() grid:Destroy() end }
end

return Lobby
