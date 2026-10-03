--!strict
--[[
	Characters behind menus and waiting screens, rendered in an isolated
	ViewportFrame so walls and other players never get in the way.
		AvatarStage.new(parent, { mode = "solo" | "party" | "lean" })
		stage:addPlayer(player)   -- party mode: pops in with a glow
		stage:destroy()
	Solo: your avatar, slow orbit, idle animation. Party: lineup, static hero camera.
	Lean: your avatar waiting against a wall (join screen), posed by hand with a
	slow breathing sway, since there is no uploaded lean animation yet.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Make = require(script.Parent.Make)
local Theme = require(script.Parent.Theme)

local AvatarStage = {}
AvatarStage.__index = AvatarStage

export type AvatarStage = typeof(setmetatable({} :: {
	frame: ViewportFrame,
	world: WorldModel,
	camera: Camera,
	mode: string,
	clones: { [number]: Model },
	order: { number },
	angle: number,
	conn: RBXScriptConnection?,
	leanJoints: { { joint: Motor6D, c0: CFrame } }?,
	leanRoot: CFrame?,
}, AvatarStage))

local IDLE_ANIM = "rbxassetid://507766666"

local function cloneCharacter(player: Player): Model?
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return nil end
	local wasArchivable = character.Archivable
	character.Archivable = true
	local clone = character:Clone()
	character.Archivable = wasArchivable
	if not clone then return nil end
	for _, d in clone:GetDescendants() do
		if d:IsA("BaseScript") then d:Destroy() end
	end
	return clone
end

local function playIdle(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local anim = Instance.new("Animation")
	anim.AnimationId = IDLE_ANIM
	pcall(function()
		local track = animator:LoadAnimation(anim)
		track.Looped = true
		track:Play()
	end)
end

-- Hand-posed "waiting against a wall": weight on the back leg, front foot crossed
-- over, arms folded, head turned a little toward the camera. Works on R15; an R6
-- rig just gets the body tilt. Returns the joints touched so update() can breathe.
local function poseLean(model: Model): { { joint: Motor6D, c0: CFrame } }
	local touched = {}
	local function bend(partName: string, jointName: string, rot: CFrame)
		local part = model:FindFirstChild(partName)
		local joint = part and part:FindFirstChild(jointName)
		if joint and joint:IsA("Motor6D") then
			table.insert(touched, { joint = joint, c0 = joint.C0 })
			joint.C0 = joint.C0 * rot
		end
	end
	local d = math.rad
	-- torso: shoulders back into the wall, hips pushed slightly forward
	bend("LowerTorso", "Root", CFrame.Angles(d(-6), 0, d(8)))
	bend("UpperTorso", "Waist", CFrame.Angles(d(-4), d(-10), d(4)))
	bend("Head", "Neck", CFrame.Angles(d(6), d(24), d(-6)))
	-- arms folded across the chest
	bend("LeftUpperArm", "LeftShoulder", CFrame.Angles(d(50), d(-25), d(-70)))
	bend("LeftLowerArm", "LeftElbow", CFrame.Angles(d(95), 0, 0))
	bend("RightUpperArm", "RightShoulder", CFrame.Angles(d(40), d(30), d(75)))
	bend("RightLowerArm", "RightElbow", CFrame.Angles(d(105), 0, 0))
	-- back leg straight and planted, front leg crossed over at the ankle
	bend("LeftUpperLeg", "LeftHip", CFrame.Angles(d(4), 0, d(-10)))
	bend("RightUpperLeg", "RightHip", CFrame.Angles(d(-6), d(10), d(22)))
	bend("RightLowerLeg", "RightKnee", CFrame.Angles(d(-12), 0, 0))
	return touched
end

function AvatarStage.new(parent: Instance, opts: { mode: string }): AvatarStage
	local self = setmetatable({}, AvatarStage)
	self.mode = opts.mode
	self.clones = {}
	self.order = {}
	self.angle = 0
	self.frame = Make("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(90, 90, 110),
		LightColor = Color3.fromRGB(255, 240, 220),
		LightDirection = Vector3.new(-1, -1, -0.5),
		ZIndex = 1,
		Parent = parent,
	})
	self.world = Instance.new("WorldModel")
	self.world.Parent = self.frame
	self.camera = Instance.new("Camera")
	self.camera.FieldOfView = 40
	self.camera.Parent = self.frame
	self.frame.CurrentCamera = self.camera

	-- A dark stage floor so feet have something to stand on
	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.Size = Vector3.new(60, 1, 60)
	floor.Position = Vector3.new(0, -0.5, 0)
	floor.Color = Theme.ink
	floor.Material = Enum.Material.SmoothPlastic
	floor.Parent = self.world

	if self.mode == "lean" then
		-- The wall stands BEHIND the avatar (negative z; the camera sits on +z and
		-- the avatar faces it), angled a little so the lit face reads as a corner.
		self.frame.Ambient = Color3.fromRGB(150, 146, 156)
		self.frame.LightColor = Color3.fromRGB(255, 244, 228)
		self.frame.LightDirection = Vector3.new(-0.6, -1, -1)
		local wallCF = CFrame.new(-2.5, 8, -1.6) * CFrame.Angles(0, math.rad(18), 0)
		local wall = Instance.new("Part")
		wall.Anchored = true
		wall.Size = Vector3.new(18, 16, 1.2)
		wall.CFrame = wallCF
		wall.Color = Theme.creamDark
		wall.Material = Enum.Material.Concrete
		wall.Parent = self.world
		local stripe = Instance.new("Part")
		stripe.Anchored = true
		stripe.Size = Vector3.new(1.8, 16.2, 0.1)
		stripe.CFrame = wallCF * CFrame.new(-4.5, 0, 0.66) * CFrame.Angles(0, 0, math.rad(12))
		stripe.Color = Theme.pop
		stripe.Material = Enum.Material.SmoothPlastic
		stripe.Parent = self.world
		local skirting = Instance.new("Part")
		skirting.Anchored = true
		skirting.Size = Vector3.new(18, 0.9, 1.4)
		skirting.CFrame = wallCF * CFrame.new(0, -7.55, 0)
		skirting.Color = Theme.ink
		skirting.Material = Enum.Material.SmoothPlastic
		skirting.Parent = self.world
		floor.Color = Theme.inkSoft
	end
	if self.mode == "solo" or self.mode == "lean" then
		self:addPlayer(Players.LocalPlayer)
	end
	self.conn = RunService.RenderStepped:Connect(function(dt)
		self:update(dt)
	end)
	return self
end

function AvatarStage.slotCFrame(self: AvatarStage, index: number, total: number): CFrame
	if self.mode == "solo" then
		return CFrame.new(0, 3, 0) * CFrame.Angles(0, math.pi, 0)
	end
	if self.mode == "lean" then
		-- facing the camera (+z), turned so the left shoulder rests on the wall
		-- behind, upper body tilted back into it, feet a little forward
		return CFrame.new(0, 2.85, 0.4) * CFrame.Angles(0, math.pi - math.rad(20), 0) * CFrame.Angles(math.rad(8), 0, math.rad(7))
	end
	local spacing = 4.5
	local x = (index - (total + 1) / 2) * spacing
	local z = math.abs(index - (total + 1) / 2) * 0.8 -- gentle arc, middle forward
	return CFrame.new(x, 3, -z) * CFrame.Angles(0, math.pi, 0)
end

function AvatarStage.relayout(self: AvatarStage)
	local total = #self.order
	for i, userId in self.order do
		local model = self.clones[userId]
		if model then model:PivotTo(self:slotCFrame(i, total)) end
	end
end

function AvatarStage.addPlayer(self: AvatarStage, player: Player)
	if self.clones[player.UserId] then return end
	local model = cloneCharacter(player)
	if not model then
		-- character not loaded yet: try again shortly
		task.delay(1, function()
			if self.frame.Parent then self:addPlayer(player) end
		end)
		return
	end
	model.Parent = self.world
	self.clones[player.UserId] = model
	table.insert(self.order, player.UserId)
	self:relayout()
	if self.mode == "lean" then
		self.leanJoints = poseLean(model)
		self.leanRoot = model:GetPivot()
	else
		playIdle(model)
	end

	-- Pop in with a glow
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Theme.accent
	highlight.OutlineColor = Theme.cream
	highlight.FillTransparency = 0.2
	highlight.OutlineTransparency = 0
	highlight.Parent = model
	local tween = TweenService:Create(highlight, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FillTransparency = 1, OutlineTransparency = 1 })
	tween:Play()
	tween.Completed:Once(function() highlight:Destroy() end)
	local root = model:FindFirstChild("HumanoidRootPart")
	if self.mode ~= "lean" and root and root:IsA("BasePart") then
		local target = root.CFrame
		model:PivotTo(target * CFrame.new(0, 3, 0))
		local proxy = Instance.new("NumberValue")
		proxy.Value = 0
		proxy.Changed:Connect(function(v) model:PivotTo(target * CFrame.new(0, 3 * (1 - v), 0)) end)
		TweenService:Create(proxy, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 }):Play()
	end
end

function AvatarStage.removePlayer(self: AvatarStage, userId: number)
	local model = self.clones[userId]
	if model then model:Destroy() end
	self.clones[userId] = nil
	local i = table.find(self.order, userId)
	if i then table.remove(self.order, i) end
	self:relayout()
end

function AvatarStage.update(self: AvatarStage, dt: number)
	if self.mode == "lean" then
		-- camera parked front-right, slightly low, with a barely-there drift
		self.angle += dt * 0.35
		local sway = math.sin(self.angle) * 0.25
		local eye = Vector3.new(5.5 + sway, 3.6, 10.5)
		self.camera.CFrame = CFrame.lookAt(eye, Vector3.new(-0.3, 2.9, 0))
		self.camera.FieldOfView = 38
		-- breathing: chest rises, head nods a touch
		local model = self.clones[Players.LocalPlayer.UserId]
		if model and self.leanRoot and self.leanJoints then
			local breath = math.sin(self.angle * 2.2)
			model:PivotTo(self.leanRoot * CFrame.new(0, breath * 0.03, 0))
			for _, j in self.leanJoints do
				local name = j.joint.Name
				if name == "Waist" then
					j.joint.C0 = j.c0 * CFrame.Angles(math.rad(-4 + breath * 1.2), math.rad(-10), math.rad(4))
				elseif name == "Neck" then
					j.joint.C0 = j.c0 * CFrame.Angles(math.rad(6 + breath * 1.5), math.rad(24 + math.sin(self.angle * 0.7) * 4), math.rad(-6))
				end
			end
		end
		return
	end
	if self.mode == "solo" then
		self.angle += dt * 0.25
		local r = 9
		local eye = Vector3.new(math.sin(self.angle) * r, 4.2, math.cos(self.angle) * r)
		self.camera.CFrame = CFrame.lookAt(eye, Vector3.new(0, 2.6, 0))
	else
		-- Low three-quarter hero angle that pulls back as the lineup grows,
		-- with a very slow drift so it never feels frozen.
		self.angle += dt * 0.05
		local total = math.max(#self.order, 1)
		local width = total * 4.5
		local dist = math.max(13, width * 0.95)
		local sway = math.sin(self.angle) * 0.12
		local eye = Vector3.new(dist * (0.55 + sway), 3.2 + total * 0.15, dist * 0.85)
		self.camera.CFrame = CFrame.lookAt(eye, Vector3.new(0, 2.6, 0))
		self.camera.FieldOfView = math.clamp(34 + total * 1.5, 34, 50)
	end
end

function AvatarStage.destroy(self: AvatarStage)
	if self.conn then self.conn:Disconnect() end
	self.frame:Destroy()
end

return AvatarStage
