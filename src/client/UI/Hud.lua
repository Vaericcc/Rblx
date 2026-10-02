--!strict
-- Top bar: phase title, instructions, countdown, submit button.
local Make = require(script.Parent.Make)
local Theme = require(script.Parent.Theme)

local Hud = {}
Hud.__index = Hud

export type Hud = typeof(setmetatable({} :: {
	frame: Frame,
	title: TextLabel,
	instructions: TextLabel,
	timer: TextLabel,
	submit: TextButton,
	endsAt: number?,
	onSubmit: (() -> ())?,
	submitted: boolean,
	conn: RBXScriptConnection?,
}, Hud))

function Hud.new(parent: Instance): Hud
	local self = setmetatable({}, Hud)
	self.endsAt = nil
	self.onSubmit = nil
	self.submitted = false

	self.title = Make.heading("", 26, { Size = UDim2.new(1, 0, 0, 30) })
	self.instructions = Make.label("", 15, { TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 36) })
	self.timer = Make.heading("", 32, {
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.accent,
		Size = UDim2.new(0, 110, 1, 0),
		Position = UDim2.new(1, -110, 0, 0),
	})
	self.submit = Make.button("Submit", Theme.good, function()
		if self.onSubmit and not self.submitted then
			self.onSubmit()
		end
	end, { Size = UDim2.new(0, 150, 0, 42), Position = UDim2.new(1, -270, 0.5, -21), Visible = false })

	self.frame = Make("Frame", {
		BackgroundColor3 = Theme.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 84),
		Make.corner(),
		Make.pad(12),
		Make("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -300, 1, 0),
			Make.list(nil, 2),
			self.title,
			self.instructions,
		}),
		self.timer,
		self.submit,
		Parent = parent,
	})

	self.conn = game:GetService("RunService").Heartbeat:Connect(function()
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

function Hud.set(self: Hud, title: string, instructions: string, endsAt: number?, canSubmit: boolean)
	self.title.Text = title
	self.instructions.Text = instructions
	self.endsAt = endsAt
	self.submitted = false
	self.submit.Visible = canSubmit
	self.submit.Text = "Submit"
	self.submit.BackgroundColor3 = Theme.good
end

function Hud.markSubmitted(self: Hud)
	self.submitted = true
	self.submit.Text = "Submitted ✓"
	self.submit.BackgroundColor3 = Theme.panelAlt
end

-- Let players edit after submitting; server keeps the latest.
function Hud.unmarkSubmitted(self: Hud)
	if self.submitted then
		self.submitted = false
		self.submit.Text = "Update"
		self.submit.BackgroundColor3 = Theme.accent2
	end
end

return Hud
