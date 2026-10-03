--!strict
--[[
	Match chrome: phase title, instructions, countdown and the submit button.
	Regular: one bar across the top with a round check button inside it.
	Compact: a slim top bar (title, timer, MENU) and a floating round check button
	bottom-right, so the content, above all the drawing canvas, gets the height.
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
Hud.TOP_HEIGHT_COMPACT = 48
Hud.BOTTOM_HEIGHT_COMPACT = 0
Hud.CHECK_SIZE_COMPACT = 60

function Hud.new(parent: Instance): Hud
	local self = setmetatable({}, Hud)
	self.endsAt = nil
	self.onSubmit = nil
	self.submitted = false
	local compact = Responsive.isCompact()

	self.title = Make.heading("", if compact then 22 else 34, { Font = Theme.fontDisplay, Size = UDim2.new(1, 0, 0, if compact then 20 else 30), TextTruncate = Enum.TextTruncate.AtEnd })
	self.instructions = Make.label("", if compact then 12 else 15, {
		TextColor3 = Theme.textDim,
		Size = UDim2.new(1, 0, 0, if compact then 14 else 36),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = not compact,
	})
	self.timer = Make.heading("", if compact then 24 else 32, {
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.accent,
		Size = UDim2.new(0, 90, 1, 0),
		Position = UDim2.new(1, -90, 0, 0),
	})
	self.submit = Make.button("✓", Theme.good, function()
		if self.onSubmit and not self.submitted then self.onSubmit() end
	end, { Visible = false, Font = Enum.Font.GothamBlack, TextSize = 30, TextColor3 = Theme.bg, Make.corner(UDim.new(0.5, 0)) })
	self.players = Make.button("MENU", Theme.panelAlt, function() end, {
		Size = UDim2.fromOffset(64, 42), TextSize = 18, Font = Theme.fontDisplay, TextColor3 = Theme.text,
	})

	self.top = Make("Frame", {
		BackgroundColor3 = Theme.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, if compact then Hud.TOP_HEIGHT_COMPACT else Hud.TOP_HEIGHT_REGULAR),
		Make.corner(),
		Make.pad(if compact then 6 else 12),
		Make("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, if compact then -170 else -300, 1, 0),
			Make.list(nil, 2),
			self.title,
			self.instructions,
		}),
		self.timer,
		Parent = parent,
	})

	self.bottom = nil
	if compact then
		-- MENU sits in the top bar left of the timer; the check floats bottom-right
		self.timer.Size = UDim2.new(0, 70, 1, 0)
		self.timer.Position = UDim2.new(1, -70, 0, 0)
		self.players.Size = UDim2.fromOffset(60, 34)
		self.players.TextSize = 15
		self.players.Position = UDim2.new(1, -140, 0.5, -17)
		self.players.Parent = self.top
		local s = Hud.CHECK_SIZE_COMPACT
		self.submit.Size = UDim2.fromOffset(s, s)
		self.submit.AnchorPoint = Vector2.new(1, 1)
		self.submit.Position = UDim2.new(1, -10, 1, -10)
		self.submit.ZIndex = 50
		Make("UIStroke", { Color = Theme.bg, Thickness = 3, Parent = self.submit })
		self.submit.Parent = parent
	else
		self.submit.Size = UDim2.fromOffset(46, 46)
		self.submit.Position = UDim2.new(1, -160, 0.5, -23)
		self.submit.Parent = self.top
		self.players.Position = UDim2.new(1, -240, 0.5, -21)
		self.players.Parent = self.top
	end

	self.conn = RunService.Heartbeat:Connect(function()
		if self.endsAt then
			local remaining = self.endsAt - workspace:GetServerTimeNow()
			if remaining < -4 then
				self.timer.Text = "..."
				self.instructions.Text = "Waiting for the server to move on"
				self.timer.TextColor3 = Theme.textDim
			else
				remaining = math.max(0, remaining)
				self.timer.Text = ("%d:%02d"):format(remaining // 60, remaining % 60)
				self.timer.TextColor3 = if remaining <= 10 then Theme.danger else Theme.accent
			end
		else
			self.timer.Text = ""
		end
	end)
	return self
end

function Hud.contentInsets(self: Hud): (number, number)
	local top = self.top.Size.Y.Offset + 10
	return top, 0
end

function Hud.set(self: Hud, title: string, instructions: string, endsAt: number?, canSubmit: boolean)
	self.title.Text = title
	self.instructions.Text = instructions
	self.endsAt = endsAt
	self.submitted = false
	self.submit.Visible = canSubmit
	self.submit.Text = "✓"
	self.submit.BackgroundColor3 = Theme.good
	self.submit.TextColor3 = Theme.bg
end

function Hud.setVisible(self: Hud, visible: boolean)
	self.top.Visible = visible
	if self.bottom then self.bottom.Visible = visible end
end

function Hud.markSubmitted(self: Hud)
	self.submitted = true
	self.submit.Text = "✓"
	self.submit.BackgroundColor3 = Theme.panelAlt
	self.submit.TextColor3 = Theme.textDim
end

-- Let players edit after submitting; the server keeps the latest version.
function Hud.unmarkSubmitted(self: Hud)
	if self.submitted then
		self.submitted = false
		self.submit.Text = "✓"
		self.submit.BackgroundColor3 = Theme.accent2
		self.submit.TextColor3 = Theme.bg
	end
end

function Hud.destroy(self: Hud)
	if self.conn then self.conn:Disconnect() end
	self.top:Destroy()
	self.submit:Destroy()
end

return Hud
