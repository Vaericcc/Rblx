--!strict
-- Grid (or list, on compact) of mode cards with vote counts. Used in room views.
local Make = require(script.Parent.Make)
local Theme = require(script.Parent.Theme)
local Responsive = require(script.Parent.Responsive)

local ModeGrid = {}

export type Opts = {
	modes: { any },
	votes: { [string]: number },
	myVote: string?,
	playerCount: number,
	likelyModeId: string?,
	onVote: (string) -> (),
}

function ModeGrid.build(parent: Instance, opts: Opts): Frame
	local compact = Responsive.isCompact()
	local CARD_H, GAP = 140, 12
	local rows = math.ceil(#opts.modes / 2)
	local grid = Make("Frame", {
		BackgroundTransparency = 1,
		-- UIGridLayout does not drive AutomaticSize reliably, so size the grid explicitly.
		Size = UDim2.new(1, 0, 0, if compact then 0 else rows * CARD_H + (rows - 1) * GAP),
		AutomaticSize = if compact then Enum.AutomaticSize.Y else Enum.AutomaticSize.None,
		Parent = parent,
	})
	if compact then
		Make.list(nil, 8).Parent = grid
	else
		Make("UIGridLayout", {
			CellSize = UDim2.new(0.5, -8, 0, CARD_H),
			CellPadding = UDim2.new(0, 16, 0, GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})
	end

	for i, mode in opts.modes do
		local votes = opts.votes[mode.id] or 0
		local locked = opts.playerCount < mode.minPlayers
		local selected = opts.myVote == mode.id
		local likely = opts.likelyModeId == mode.id
		-- The card itself is the button so every pixel of it is clickable.
		local card = Make("TextButton", {
			Text = "",
			AutoButtonColor = not locked,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, if compact then 0 else CARD_H),
			AutomaticSize = if compact then Enum.AutomaticSize.Y else Enum.AutomaticSize.None,
			BackgroundColor3 = if selected then Theme.panelAlt else Theme.panel,
			BackgroundTransparency = if locked then 0.4 else 0,
			BorderSizePixel = 0,
			Make.corner(),
			Make.pad(14),
			Make.list(nil, 3),
			Make("UIStroke", { Color = if selected then Theme.accent else Theme.accent2, Thickness = if selected then 2 elseif likely then 1 else 0 }),
			Parent = grid,
		})
		card.Activated:Connect(function()
			if not locked then opts.onVote(mode.id) end
		end)
		local header = ("%s%s"):format(mode.name, if votes > 0 then ("  <font color=\"#ffc43d\">· %d</font>"):format(votes) else "")
		if likely and not selected then
			header ..= "  <font color=\"#5ec8ff\" size=\"12\">LEADING</font>"
		end
		Make.heading(header, 18, { RichText = true, Size = UDim2.new(1, 0, 0, 22), Parent = card })
		Make.label(mode.tagline, 13, { TextColor3 = Theme.accent2, Size = UDim2.new(1, 0, 0, 16), Parent = card })
		Make.label(mode.description, 12, { TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, if compact then 0 else 48), AutomaticSize = if compact then Enum.AutomaticSize.Y else Enum.AutomaticSize.None, Parent = card })
		if locked then
			Make.label(("Needs %d players"):format(mode.minPlayers), 12, { TextColor3 = Theme.danger, Size = UDim2.new(1, 0, 0, 14), Parent = card })
		end
	end
	return grid
end

return ModeGrid
