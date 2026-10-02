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
	comic: boolean?, -- cream paper cards with ink borders (lobby)
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
		local comic = opts.comic == true
		local bg = if comic then (if selected then Theme.accent else Theme.cream) else (if selected then Theme.panelAlt else Theme.panel)
		local fg = if comic then Theme.ink else Theme.text
		local dim = if comic then "#6b6050" else "#aaaabe"
		local card = Make("TextButton", {
			Text = "",
			AutoButtonColor = not locked,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, if compact then 0 else CARD_H),
			AutomaticSize = if compact then Enum.AutomaticSize.Y else Enum.AutomaticSize.None,
			BackgroundColor3 = bg,
			BackgroundTransparency = if locked then 0.4 else 0,
			BorderSizePixel = 0,
			Make.corner(UDim.new(0, if comic then 6 else 12)),
			Make.pad(14),
			Make.list(nil, 3),
			Make("UIStroke", {
				Color = if comic then Theme.ink else (if selected then Theme.accent else Theme.accent2),
				Thickness = if comic then (if selected then 4 else 3) else (if selected then 2 elseif likely then 1 else 0),
			}),
			Parent = grid,
		})
		if comic then
			-- big faded issue number in the corner
			Make.label(("%02d"):format(i), 44, {
				Font = Theme.fontDisplay, TextColor3 = Theme.ink, TextTransparency = 0.88,
				AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 6), Size = UDim2.fromOffset(80, 50),
				TextXAlignment = Enum.TextXAlignment.Right, Parent = card,
			})
		end
		card.Activated:Connect(function()
			if not locked then opts.onVote(mode.id) end
		end)
		local voteColor = if comic then "#ff5678" else "#ffc43d"
		local header = ("%s%s"):format(mode.name, if votes > 0 then ("  <font color=\"%s\">· %d</font>"):format(voteColor, votes) else "")
		if likely and not selected then
			header ..= ("  <font color=\"%s\" size=\"12\">LEADING</font>"):format(if comic then "#1f8a4c" else "#5ec8ff")
		end
		Make.heading(header, 18, { RichText = true, Font = if comic then Theme.fontDisplay else Theme.font, TextColor3 = fg, Size = UDim2.new(1, 0, 0, 22), Parent = card })
		Make.label(mode.tagline, 13, { TextColor3 = if comic then Theme.pop else Theme.accent2, Font = Theme.font, Size = UDim2.new(1, 0, 0, 16), Parent = card })
		Make.label(("<font color=\"%s\">%s</font>"):format(dim, mode.description), 12, { RichText = true, Size = UDim2.new(1, -40, 0, if compact then 0 else 48), AutomaticSize = if compact then Enum.AutomaticSize.Y else Enum.AutomaticSize.None, Parent = card })
		if locked then
			Make.label(("Needs %d players"):format(mode.minPlayers), 12, { TextColor3 = if comic then Theme.pop else Theme.danger, Size = UDim2.new(1, 0, 0, 14), Parent = card })
		end
	end
	return grid
end

return ModeGrid
