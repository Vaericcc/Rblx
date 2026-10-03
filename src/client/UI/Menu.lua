--!strict
--[[
	The menu system. One look for every menu: a blurred, desaturated world
	behind an ink slash, a huge vertical title down the left edge, slanted
	item bars that cascade in from the left with overshoot, and a paper
	content panel on the right for pages (room list, settings, ...).

	Menu.open({
		title = "PAUSE",
		items = { { id = "resume", label = "RESUME", onClick = fn, accent = false }, ... },
		onClose = fn,
	}) -> menu
	menu:setItems(items)          re-render the item bars (keeps the frame)
	menu:select(id)               highlight an item
	menu:content() -> Frame       the paper panel; fill it with a page
	menu:clearContent()
	menu:close()
]]
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Make = require(script.Parent.Make)
local Theme = require(script.Parent.Theme)
local Responsive = require(script.Parent.Responsive)
local Settings = require(script.Parent.Settings)
local AvatarStage = require(script.Parent.AvatarStage)

local Menu = {}
Menu.__index = Menu

export type Item = { id: string, label: string, onClick: (() -> ())?, accent: boolean?, disabled: boolean? }
export type Opts = { title: string, items: { Item }, onClose: (() -> ())?, parent: Instance, stage: string?, dim: number?, accent: Color3?, header: string? }

export type Menu = typeof(setmetatable({} :: {
	root: Frame,
	slash: Frame,
	titleLabel: TextLabel,
	itemsFrame: Frame,
	paper: Frame,
	paperBody: ScrollingFrame,
	items: { Item },
	bars: { [string]: TextButton },
	selected: string?,
	blur: BlurEffect?,
	color: ColorCorrectionEffect?,
	closed: boolean,
	onClose: (() -> ())?,
	stage: AvatarStage.AvatarStage?,
	accent: Color3,
	headerLabel: TextLabel?,
}, Menu))

local SOUND_OPEN = "open"
local SOUND_SELECT = "select"

local function play(name: string, volume: number)
	local id = (Theme.sounds :: any)[name]
	if not id or id == 0 then return end -- no sound configured yet
	local s = Instance.new("Sound")
	s.SoundId = ("rbxassetid://%d"):format(id)
	s.Volume = volume * Settings.get("masterVolume")
	s.Parent = SoundService
	s:Play()
	s.Ended:Once(function() s:Destroy() end)
	task.delay(3, function() if s.Parent then s:Destroy() end end)
end

local function motion(): boolean
	return not Settings.get("reduceMotion")
end

local function tween(obj: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	if not motion() then
		for k, v in props do (obj :: any)[k] = v end
		return
	end
	TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props):Play()
end

function Menu.open(opts: Opts): Menu
	local self = setmetatable({}, Menu)
	self.items = opts.items
	self.bars = {}
	self.selected = nil
	self.closed = false
	self.onClose = opts.onClose
	self.accent = opts.accent or Theme.cream
	self.headerLabel = nil
	local compact = Responsive.isCompact()

	-- World treatment: blur + desaturate (local Lighting effects, removed on close)
	self.blur = Instance.new("BlurEffect")
	self.blur.Size = 0
	self.blur.Name = "StoryDubMenuBlur"
	self.blur.Parent = Lighting
	self.color = Instance.new("ColorCorrectionEffect")
	self.color.Name = "StoryDubMenuColor"
	self.color.Saturation = 0
	self.color.Parent = Lighting
	tween(self.blur, 0.35, { Size = 18 })
	tween(self.color, 0.35, { Saturation = -0.7, Contrast = 0.15, Brightness = -0.08 })

	self.root = Make("Frame", {
		BackgroundColor3 = Theme.ink,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 300,
		Active = true,
		Parent = opts.parent,
	})
	tween(self.root, 0.3, { BackgroundTransparency = opts.dim or 0.45 })

	-- Your avatar behind the menu (isolated viewport, slow orbit)
	self.stage = nil
	if opts.stage == "solo" then
		local holder = Make("Frame", {
			BackgroundTransparency = 1,
			Position = if compact then UDim2.fromScale(0.5, 0.45) else UDim2.fromScale(0.3, 0.86),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = if compact then UDim2.fromScale(1, 0.6) else UDim2.fromScale(0.42, 0.8),
			ZIndex = 300,
			Parent = self.root,
		})
		self.stage = AvatarStage.new(holder, { mode = "solo" })
		holder.ZIndex = 300
	end

	-- Diagonal ink slash: a tall rotated bar swept across the screen
	self.slash = Make("Frame", {
		BackgroundColor3 = Theme.ink,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(-0.6, 0.5),
		Size = UDim2.new(0.42, 0, 2.6, 0),
		Rotation = if compact then 0 else 14,
		ZIndex = 301,
		Parent = self.root,
	})
	Make("UIGradient", {
		Color = ColorSequence.new(Theme.ink, Theme.inkSoft),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.85, 0), NumberSequenceKeypoint.new(1, 1) }),
		Rotation = 0,
		Parent = self.slash,
	})
	tween(self.slash, 0.45, { Position = UDim2.fromScale(if compact then 0.5 else 0.2, 0.5) }, Enum.EasingStyle.Back)
	-- rough torn edge: a few ink shards along the slash
	for i = 1, 9 do
		Make("Frame", {
			BackgroundColor3 = Theme.ink,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.985, 0.05 + i * 0.1),
			Size = UDim2.fromOffset(14 + (i % 3) * 16, 22 + (i % 2) * 18),
			Rotation = (i % 2 == 0) and 6 or -5,
			ZIndex = 301,
			Parent = self.slash,
		})
	end

	-- Vertical title down the left edge (Bangers, huge)
	self.titleLabel = Make.label(opts.title, if compact then 42 else 96, {
		Font = Theme.fontDisplay,
		TextColor3 = Theme.cream,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = if compact then 0 else -90,
		Position = if compact then UDim2.new(0.5, 0, 0, 64) else UDim2.fromScale(0.07, 0.5),
		Size = if compact then UDim2.new(1, -32, 0, 50) else UDim2.fromOffset(math.floor(Responsive.viewport().Y * 0.86), 120),
		TextWrapped = false,
		TextScaled = false,
		ZIndex = 302,
		TextTransparency = 1,
		Parent = self.root,
	})
	self.titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	self.titleLabel.TextColor3 = self.accent
	tween(self.titleLabel, 0.5, { TextTransparency = 0 })

	if opts.header then
		self.headerLabel = Make.label(opts.header, if compact then 16 else 20, {
			Font = Theme.fontDisplay, TextColor3 = Theme.ink, BackgroundColor3 = self.accent,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = if compact then UDim2.new(0, 16, 0, 70) else UDim2.fromScale(0.16, 0.11),
			Size = if compact then UDim2.new(1, -32, 0, 30) else UDim2.new(0.3, 0, 0, 36),
			Rotation = if compact then 0 else -2,
			ZIndex = 303,
			Make.corner(UDim.new(0, 4)), Make("UIPadding", { PaddingLeft = UDim.new(0, 14) }),
			Make("UIStroke", { Color = Theme.ink, Thickness = 3 }),
			Parent = self.root,
		})
	end

	-- Item bars
	self.itemsFrame = Make("Frame", {
		BackgroundTransparency = 1,
		Position = if compact then UDim2.new(0, 16, 0, 108) else UDim2.fromScale(0.16, 0.2),
		Size = if compact then UDim2.new(1, -32, 0, 0) else UDim2.fromScale(0.34, 0.7),
		AutomaticSize = if compact then Enum.AutomaticSize.Y else Enum.AutomaticSize.None,
		ZIndex = 303,
		Make("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, if compact then 6 else 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Left }),
		Parent = self.root,
	})

	-- Paper content panel
	self.paper = Make("Frame", {
		BackgroundColor3 = Theme.cream,
		Position = if compact then UDim2.new(0, 12, 0, 0) else UDim2.fromScale(0.58, 0.08),
		Size = if compact then UDim2.new(1, -24, 0, 200) else UDim2.new(0.39, 0, 0, 200),
		Rotation = if compact then 0 else -1.2,
		ZIndex = 304,
		Visible = false,
		Make.corner(UDim.new(0, 4)),
		Make("UIStroke", { Color = Theme.ink, Thickness = 4 }),
		Make.pad(if compact then 12 else 20),
		Parent = self.root,
	})
	self.paperBody = Make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ClipsDescendants = true,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.ink,
		ZIndex = 305,
		Make.list(nil, 10),
		Make("UIPadding", { PaddingRight = UDim.new(0, 12) }),
		Parent = self.paper,
	})

	-- Paper grows with its content up to most of the screen, then scrolls.
	self.paperBody:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
		local pad = if compact then 24 else 40
		local maxH = Responsive.viewport().Y * (if compact then 0.7 else 0.8)
		local h = math.clamp(self.paperBody.AbsoluteCanvasSize.Y / math.max(self.paper.AbsoluteSize.X / self.paper.Size.X.Offset, 1) + pad, 120, maxH)
		-- AbsoluteCanvasSize is in screen pixels; convert back through the UI scale
		local scale = 1
		local gui = self.root:FindFirstAncestorOfClass("ScreenGui")
		local uiScale = gui and gui:FindFirstChildOfClass("UIScale")
		if uiScale then scale = uiScale.Scale end
		h = math.clamp(self.paperBody.AbsoluteCanvasSize.Y / scale + pad, 120, maxH)
		self.paper.Size = UDim2.new(self.paper.Size.X.Scale, self.paper.Size.X.Offset, 0, h)
	end)

	self:setItems(opts.items)
	play(SOUND_OPEN, 0.5)
	return self
end

function Menu.setChrome(self: Menu, title: string, accent: Color3, header: string?)
	self.accent = accent
	self.titleLabel.Text = title
	self.titleLabel.TextColor3 = accent
	if self.headerLabel then self.headerLabel:Destroy() self.headerLabel = nil end
	if header then
		local compact = Responsive.isCompact()
		self.headerLabel = Make.label(header, if compact then 16 else 20, {
			Font = Theme.fontDisplay, TextColor3 = Theme.ink, BackgroundColor3 = accent,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = if compact then UDim2.new(0, 16, 0, 70) else UDim2.fromScale(0.16, 0.11),
			Size = if compact then UDim2.new(1, -32, 0, 30) else UDim2.new(0.3, 0, 0, 36),
			Rotation = if compact then 0 else -2,
			ZIndex = 303,
			Make.corner(UDim.new(0, 4)), Make("UIPadding", { PaddingLeft = UDim.new(0, 14) }),
			Make("UIStroke", { Color = Theme.ink, Thickness = 3 }),
			Parent = self.root,
		})
	end
end

function Menu.setItems(self: Menu, items: { Item })
	self.items = items
	for _, b in self.bars do b:Destroy() end
	self.bars = {}
	local compact = Responsive.isCompact()
	local h = if compact then 46 else 58
	for i, item in items do
		local bar = Make("TextButton", {
			Text = "   " .. item.label,
			Font = Theme.fontDisplay,
			TextSize = if compact then 24 else 32,
			TextColor3 = if item.disabled then Theme.creamDark else Theme.cream,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = Theme.inkSoft,
			BackgroundTransparency = if item.disabled then 0.5 else 0,
			AutoButtonColor = false,
			Size = UDim2.new(if compact then 1 else 0.78, 0, 0, h),
			Position = UDim2.fromOffset(-500, 0),
			Rotation = if compact then 0 else -3,
			LayoutOrder = i,
			ZIndex = 303,
			Make("UIStroke", { Color = Theme.cream, Thickness = 1.5, Transparency = 0.55 }),
			Parent = self.itemsFrame,
		})
		-- Cascade in with overshoot
		local restX = if compact then 0 else (i - 1) * 26
		if motion() then
			task.delay(0.05 * i, function()
				if bar.Parent then
					TweenService:Create(bar, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(restX, 0) }):Play()
				end
			end)
		else
			bar.Position = UDim2.fromOffset(restX, 0)
		end
		bar.MouseEnter:Connect(function()
			if item.disabled or self.selected == item.id then return end
			tween(bar, 0.12, { Size = UDim2.new(if compact then 1 else 0.84, 0, 0, h), BackgroundColor3 = Color3.fromRGB(64, 58, 70) })
		end)
		bar.MouseLeave:Connect(function()
			if item.disabled or self.selected == item.id then return end
			tween(bar, 0.15, { Size = UDim2.new(if compact then 1 else 0.78, 0, 0, h), BackgroundColor3 = Theme.inkSoft })
		end)
		bar.Activated:Connect(function()
			if item.disabled then return end
			play(SOUND_SELECT, 0.6)
			self:select(item.id)
			if item.onClick then item.onClick() end
		end)
		self.bars[item.id] = bar
	end
	if self.selected then self:select(self.selected) end
end

function Menu.select(self: Menu, id: string?)
	self.selected = id
	local compact = Responsive.isCompact()
	local h = if compact then 46 else 58
	for itemId, bar in self.bars do
		local on = itemId == id
		local item: Item? = nil
		for _, it in self.items do if it.id == itemId then item = it end end
		local accent = if item and item.accent then Theme.pop else self.accent
		tween(bar, 0.18, {
			Size = UDim2.new(if compact then 1 else (if on then 0.9 else 0.78), 0, 0, h),
			BackgroundColor3 = if on then accent else Theme.inkSoft,
			BackgroundTransparency = 0,
			TextColor3 = if on then Theme.ink else (if item and item.disabled then Theme.creamDark else Theme.cream),
		}, Enum.EasingStyle.Back)
	end
end

function Menu.content(self: Menu): ScrollingFrame
	if not self.paper.Visible then
		self.paper.Visible = true
		if motion() then
			local target = self.paper.Position
			self.paper.Position = target + UDim2.fromOffset(0, 40)
			self.paper.BackgroundTransparency = 1
			tween(self.paper, 0.35, { Position = target, BackgroundTransparency = 0 }, Enum.EasingStyle.Back)
		end
	end
	return self.paperBody
end

function Menu.clearContent(self: Menu)
	for _, c in self.paperBody:GetChildren() do
		if c:IsA("GuiObject") then c:Destroy() end
	end
end

function Menu.hideContent(self: Menu)
	self:clearContent()
	self.paper.Visible = false
end

function Menu.close(self: Menu)
	if self.closed then return end
	self.closed = true
	if self.blur then tween(self.blur, 0.25, { Size = 0 }) end
	if self.color then tween(self.color, 0.25, { Saturation = 0, Contrast = 0, Brightness = 0 }) end
	tween(self.root, 0.22, { BackgroundTransparency = 1 })
	tween(self.slash, 0.25, { Position = UDim2.fromScale(1.6, 0.5) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	for _, bar in self.bars do
		tween(bar, 0.2, { Position = UDim2.fromOffset(600, 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	end
	tween(self.titleLabel, 0.2, { TextTransparency = 1 })
	tween(self.paper, 0.2, { BackgroundTransparency = 1 })
	task.delay(if motion() then 0.3 else 0, function()
		if self.blur then self.blur:Destroy() end
		if self.color then self.color:Destroy() end
		if self.stage then self.stage:destroy() end
		self.root:Destroy()
	end)
	if self.onClose then self.onClose() end
end

----------------------------------------------------------------------------
-- Paper page helpers (ink on cream)

function Menu.heading(parent: Instance, text: string, size: number?)
	return Make.label(text, size or 26, { Font = Theme.fontDisplay, TextColor3 = Theme.ink, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 306, Parent = parent })
end

function Menu.text(parent: Instance, text: string, size: number?, dim: boolean?)
	return Make.label(text, size or 14, { Font = Theme.fontBody, TextColor3 = Theme.ink, TextTransparency = if dim then 0.4 else 0, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, RichText = true, ZIndex = 306, Parent = parent })
end

function Menu.button(parent: Instance, text: string, fill: Color3, onClick: () -> (), props: { [any]: any }?)
	local p = {
		Font = Theme.fontDisplay,
		TextSize = 20,
		TextColor3 = if fill == Theme.ink or fill == Theme.pop then Theme.cream else Theme.ink,
		Size = UDim2.new(1, 0, 0, Responsive.touchSize()),
		Rotation = -0.6,
		ZIndex = 306,
		Make("UIStroke", { Color = Theme.ink, Thickness = 2.5 }),
	}
	if props then for k, v in props do if typeof(k) == "number" then table.insert(p, v) else p[k] = v end end end
	p.Parent = parent
	local b = Make.button(text, fill, function()
		play(SOUND_SELECT, 0.5)
		onClick()
	end, p)
	b.TextColor3 = p.TextColor3
	return b
end

-- A paper card with an ink border inside the content panel.
function Menu.card(parent: Instance, props: { [any]: any }?)
	local p = {
		BackgroundColor3 = Theme.creamDark,
		BackgroundTransparency = 0.5,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 306,
		Make.corner(UDim.new(0, 4)),
		Make.pad(12),
		Make.list(nil, 6),
		Make("UIStroke", { Color = Theme.ink, Thickness = 2 }),
	}
	if props then for k, v in props do if typeof(k) == "number" then table.insert(p, v) else p[k] = v end end end
	p.Parent = parent
	return Make("Frame", p)
end

-- Horizontal slider 0..1 mapped to min..max.
function Menu.slider(parent: Instance, label: string, value: number, min: number, max: number, onChange: (number) -> ())
	local UserInputService = game:GetService("UserInputService")
	local row = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), ZIndex = 306, Parent = parent })
	local lbl = Make.label(("%s  <b>%d%%</b>"):format(label, math.floor((value - min) / (max - min) * 100 + 0.5)), 14, { RichText = true, Font = Theme.fontBody, TextColor3 = Theme.ink, Size = UDim2.new(1, 0, 0, 20), ZIndex = 306, Parent = row })
	local track = Make("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.creamDark, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 30), ZIndex = 306,
		Make.corner(UDim.new(0.5, 0)), Make("UIStroke", { Color = Theme.ink, Thickness = 2 }), Parent = row,
	})
	local fill = Make("Frame", { BackgroundColor3 = Theme.pop, Size = UDim2.new((value - min) / (max - min), 0, 1, 0), ZIndex = 307, Make.corner(UDim.new(0.5, 0)), Parent = track })
	local dragging = false
	local function setFromX(x: number)
		local a = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		fill.Size = UDim2.new(a, 0, 1, 0)
		local v = min + (max - min) * a
		lbl.Text = ("%s  <b>%d%%</b>"):format(label, math.floor(a * 100 + 0.5))
		onChange(v)
	end
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	return row
end

function Menu.toggle(parent: Instance, label: string, value: boolean, onChange: (boolean) -> ())
	local row = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, Responsive.touchSize()), ZIndex = 306, Parent = parent })
	Make.label(label, 14, { Font = Theme.fontBody, TextColor3 = Theme.ink, Size = UDim2.new(1, -90, 1, 0), TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 306, Parent = row })
	local state = value
	local btn = Make.button(if state then "ON" else "OFF", if state then Theme.pop else Theme.creamDark, function() end, {
		Font = Theme.fontDisplay, TextSize = 18, TextColor3 = if state then Theme.cream else Theme.ink,
		Size = UDim2.fromOffset(80, Responsive.touchSize() - 8), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), ZIndex = 306,
		Make("UIStroke", { Color = Theme.ink, Thickness = 2 }), Parent = row,
	})
	btn.Activated:Connect(function()
		state = not state
		btn.Text = if state then "ON" else "OFF"
		btn.BackgroundColor3 = if state then Theme.pop else Theme.creamDark
		btn.TextColor3 = if state then Theme.cream else Theme.ink
		play(SOUND_SELECT, 0.4)
		onChange(state)
	end)
	return row
end

-- The Settings page, built from Settings.schema. Shared by lobby and pause.
function Menu.settingsPage(self: Menu, onUiScale: ((number) -> ())?)
	self:clearContent()
	local body = self:content()
	Menu.heading(body, "SETTINGS")
	Menu.text(body, "Changes apply immediately.", 13, true)
	for _, def in Settings.schema do
		if def.kind == "slider" then
			Menu.slider(body, def.label, Settings.get(def.key), def.min, def.max, function(v)
				Settings.set(def.key, v)
				if def.key == "uiScale" and onUiScale then onUiScale(v) end
			end)
		else
			Menu.toggle(body, def.label, Settings.get(def.key), function(v)
				Settings.set(def.key, v)
			end)
		end
	end
end

return Menu
