--!strict
--[[
	Match chrome: phase title, instructions, countdown and the submit button.
	Regular: one bar across the top with the button inside it.
	Compact: a slim top bar, and the submit button becomes a full-width bottom bar.
]]
local RunService = game:GetService("RunService")
local Make = require(script.Parent.Make)
local Theme = require(script.Parent.Theme)
local Responsive = require(script.Parent.Responsive)

local Hud = {}
Hud.__index = Hud

export type Hud = typeof(setmetatable({} :: {
	top: Frame,
	bottom: Frame?,
	title: TextLabel,
	instructions: TextLabel,
	timer: TextLabel,
	submit: TextButton,
	players: TextButton,
	endsAt: number?,
	onSubmit: (() -> ())?,
	submitted: boolean,
	conn: RBXScriptConnection?,
}, Hud))

Hud.TOP_HEIGHT_REGULAR = 84
Hud.TOP_HEIGHT_COMPACT = 56
Hud.BOTTOM_HEIGHT_COMPACT = 64

function Hud.new(parent: Instance): Hud
	local self = setmetatable({}, Hud)
	self.endsAt = nil
	self.onSubmit = nil
	self.submitted = false
	local compact = Responsive.isCompact()

	self.title = Make.heading("", if compact then 26 else 34, { Font = Theme.fontDisplay, Size = UDim2.new(1, 0, 0, if compact then 26 else 30), TextTruncate = Enum.TextTruncate.AtEnd })
	self.instructions = Make.label("", if compact then 12 else 15, {
		TextColor3 = Theme.textDim,
		Size = UDim2.new(1, 0, 0, if compact then 16 else 36),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = not compact,
	})
	self.timer = Make.heading("", if compact then 24 else 32, {
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.accent,
		Size = UDim2.new(0, 90, 1, 0),
		Position = UDim2.new(1, -90, 0, 0),
	})
	self.submit = Make.button("Submit", Theme.good, function()
		if self.onSubmit and not self.submitted then self.onSubmit() end
	end, { Visible = false })
	self.players = Make.button("MENU", Theme.panelAlt, function() end, {
		Size = UDim2.fromOffset(64, 42), TextSize = 18, Font = Theme.fontDisplay, TextColor3 = Theme.text,
	})

	self.top = Make("Frame", {
		BackgroundColor3 = Theme.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, if compact then Hud.TOP_HEIGHT_COMPACT else Hud.TOP_HEIGHT_REGULAR),
		Make.corner(),
		Make.pad(if compact then 8 else 12),
		Make("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, if compact then -100 else -300, 1, 0),
			Make.list(nil, 2),
			self.title,
			self.instructions,
		}),
		self.timer,
		Parent = parent,
	})

	if compact then
		self.bottom = Make("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, Hud.BOTTOM_HEIGHT_COMPACT),
			Parent = parent,
		})
		self.submit.Size = UDim2.new(1, -78, 0, 52)
		self.submit.Position = UDim2.new(0, 78, 0, 6)
		self.submit.TextSize = 20
		self.submit.Parent = self.bottom
		self.players.Size = UDim2.fromOffset(70, 52)
		self.players.Position = UDim2.new(0, 0, 0, 6)
		self.players.Parent = self.bottom
	else
		self.bottom = nil
		self.submit.Size = UDim2.new(0, 150, 0, 42)
		self.submit.Position = UDim2.new(1, -250, 0.5, -21)
		self.submit.Parent = self.top
		self.players.Position = UDim2.new(1, -324, 0.5, -21)
		self.players.Parent = self.top
	end

	self.conn = RunService.Heartbeat:Connect(function()
		if self.endsAt then
			local remaining = math.max(0, self.endsAt - workspace:GetServerTimeNow())
			self.timer.Text = ("%d:%02d"):format(remaining // 60, remaining % 60)
			self.timer.TextColor3 = if remaining <= 10 then Theme.danger else Theme.accent
		else
			self.timer.Text = ""
		end
	end)
	return self
end

function Hud.contentInsets(self: Hud): (number, number)
	local top = self.top.Size.Y.Offset + 10
	local bottom = if self.bottom then Hud.BOTTOM_HEIGHT_COMPACT else 0
	return top, bottom
end

function Hud.set(self: Hud, title: string, instructions: string, endsAt: number?, canSubmit: boolean)
	self.title.Text = title
	self.instructions.Text = instructions
	self.endsAt = endsAt
	self.submitted = false
	self.submit.Visible = canSubmit
	self.submit.Text = "SUBMIT"
	self.submit.Font = Theme.fontDisplay
	self.submit.TextSize = 22
	self.submit.BackgroundColor3 = Theme.good
	self.submit.TextColor3 = Theme.bg
end

function Hud.setVisible(self: Hud, visible: boolean)
	self.top.Visible = visible
	if self.bottom then self.bottom.Visible = visible end
end

function Hud.markSubmitted(self: Hud)
	self.submitted = true
	self.submit.Text = "Submitted"
	self.submit.BackgroundColor3 = Theme.panelAlt
end

-- Let players edit after submitting; the server keeps the latest version.
function Hud.unmarkSubmitted(self: Hud)
	if self.submitted then
		self.submitted = false
		self.submit.Text = "UPDATE"
		self.submit.BackgroundColor3 = Theme.accent2
	end
end

function Hud.destroy(self: Hud)
	if self.conn then self.conn:Disconnect() end
	self.top:Destroy()
	if self.bottom then self.bottom:Destroy() end
end

return Hud
