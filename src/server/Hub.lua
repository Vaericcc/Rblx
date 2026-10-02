--!strict
--[[
	Builds the hub: a floating stone plaza over a calm sea at golden hour.
	Fountain and spire in the middle, lamp posts, pillars with neon caps,
	trees on the rim, and a soft atmosphere. Everything is procedural so the
	place file needs nothing but a spawn point.
]]
local Lighting = game:GetService("Lighting")

local Hub = {}

local PLAZA_RADIUS = 72
local PLAZA_Y = 0 -- top surface of the plaza

local STONE_DARK = Color3.fromRGB(58, 60, 74)
local STONE = Color3.fromRGB(86, 88, 104)
local STONE_LIGHT = Color3.fromRGB(122, 124, 142)
local ACCENT = Color3.fromRGB(255, 196, 61)
local ACCENT2 = Color3.fromRGB(94, 200, 255)
local WOOD = Color3.fromRGB(96, 68, 48)
local LEAF_COLORS = {
	Color3.fromRGB(70, 140, 90),
	Color3.fromRGB(96, 168, 104),
	Color3.fromRGB(58, 120, 86),
	Color3.fromRGB(176, 120, 72), -- one autumn tree for warmth
}

local root: Model

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	if not props.Parent then p.Parent = root end
	return p
end

local function cylinder(radius: number, height: number, y: number, color: Color3, material: Enum.Material, extra: { [string]: any }?): Part
	local props: { [string]: any } = {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
	}
	if extra then for k, v in extra do props[k] = v end end
	return part(props)
end

local function pointLight(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

----------------------------------------------------------------------------

local function buildLighting()
	Lighting.ClockTime = 17.4 -- golden hour
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(70, 70, 90)
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 110, 130)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3
	Lighting.FogEnd = 1200

	for _, name in { "StoryDubSky", "StoryDubAtmosphere", "StoryDubBloom", "StoryDubColor", "StoryDubRays" } do
		local old = Lighting:FindFirstChild(name)
		if old then old:Destroy() end
	end

	local sky = Instance.new("Sky")
	sky.Name = "StoryDubSky"
	sky.SkyboxBk = "rbxassetid://591058823"
	sky.SkyboxDn = "rbxassetid://591059876"
	sky.SkyboxFt = "rbxassetid://591058104"
	sky.SkyboxLf = "rbxassetid://591057861"
	sky.SkyboxRt = "rbxassetid://591057625"
	sky.SkyboxUp = "rbxassetid://591059642"
	sky.StarCount = 3000
	sky.SunAngularSize = 14
	sky.Parent = Lighting

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "StoryDubAtmosphere"
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.6
	atmosphere.Color = Color3.fromRGB(214, 180, 170)
	atmosphere.Decay = Color3.fromRGB(120, 100, 140)
	atmosphere.Glare = 0.35
	atmosphere.Haze = 1.6
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "StoryDubBloom"
	bloom.Intensity = 0.6
	bloom.Size = 32
	bloom.Threshold = 1.2
	bloom.Parent = Lighting

	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "StoryDubColor"
	color.Saturation = 0.12
	color.Contrast = 0.08
	color.TintColor = Color3.fromRGB(255, 246, 236)
	color.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Name = "StoryDubRays"
	rays.Intensity = 0.06
	rays.Spread = 0.8
	rays.Parent = Lighting
end

local function buildSea()
	part({
		Name = "Sea",
		Size = Vector3.new(4000, 2, 4000),
		Position = Vector3.new(0, -26, 0),
		Color = Color3.fromRGB(28, 52, 88),
		Material = Enum.Material.Glass,
		Transparency = 0.15,
		Reflectance = 0.25,
		CanCollide = true,
	})
	-- Distant islands so the horizon isn't empty
	for i = 1, 7 do
		local angle = i / 7 * math.pi * 2 + 0.4
		local dist = 420 + (i % 3) * 110
		local w = 60 + (i % 4) * 25
		local rock = part({
			Name = "Island",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(w, w * 0.5, w),
			Position = Vector3.new(math.cos(angle) * dist, -40, math.sin(angle) * dist),
			Color = Color3.fromRGB(60, 72, 80),
			Material = Enum.Material.Slate,
		})
		rock.CastShadow = false
	end
end

local function buildPlaza()
	-- Stacked discs so the island has a visible edge and underside
	cylinder(PLAZA_RADIUS, 2, PLAZA_Y - 1, STONE, Enum.Material.Slate, { Name = "Plaza" })
	cylinder(PLAZA_RADIUS - 2, 6, PLAZA_Y - 5, STONE_DARK, Enum.Material.Slate, { Name = "PlazaBase" })
	cylinder(PLAZA_RADIUS - 10, 10, PLAZA_Y - 13, Color3.fromRGB(44, 46, 58), Enum.Material.Rock, { Name = "PlazaRock" })
	-- Pattern rings on top
	cylinder(PLAZA_RADIUS - 8, 0.2, PLAZA_Y + 0.1, STONE_LIGHT, Enum.Material.Slate, { Name = "Ring1" })
	cylinder(PLAZA_RADIUS - 10, 0.2, PLAZA_Y + 0.15, STONE, Enum.Material.Slate, { Name = "Ring1Inner" })
	cylinder(26, 0.2, PLAZA_Y + 0.1, STONE_LIGHT, Enum.Material.Slate, { Name = "Ring2" })
	cylinder(24, 0.2, PLAZA_Y + 0.15, STONE, Enum.Material.Slate, { Name = "Ring2Inner" })
	-- Radial paths to each platform
	for i = 1, 4 do
		local angle = (i - 1) / 4 * math.pi * 2
		local len = 20
		local mid = 23
		part({
			Name = "Path",
			Size = Vector3.new(6, 0.2, len),
			CFrame = CFrame.new(math.cos(angle) * mid, PLAZA_Y + 0.12, math.sin(angle) * mid) * CFrame.Angles(0, -angle + math.pi / 2, 0),
			Color = STONE_LIGHT,
			Material = Enum.Material.Slate,
		})
	end
	-- Low rim wall in segments
	local segments = 36
	for i = 1, segments do
		local angle = i / segments * math.pi * 2
		local r = PLAZA_RADIUS - 1.5
		local seg = part({
			Name = "Rim",
			Size = Vector3.new(2 * math.pi * r / segments + 0.4, 1.6, 1.2),
			CFrame = CFrame.new(math.cos(angle) * r, PLAZA_Y + 0.8, math.sin(angle) * r) * CFrame.Angles(0, -angle + math.pi / 2, 0),
			Color = STONE_DARK,
			Material = Enum.Material.Slate,
		})
		seg.CastShadow = false
	end
end

local function buildFountain()
	cylinder(12, 1.6, PLAZA_Y + 0.8, STONE_LIGHT, Enum.Material.Slate, { Name = "Basin" })
	cylinder(10.6, 0.6, PLAZA_Y + 1.3, Color3.fromRGB(70, 150, 210), Enum.Material.Glass, { Name = "Water", Transparency = 0.35, Reflectance = 0.3, CanCollide = false })
	cylinder(3.2, 2.2, PLAZA_Y + 2.1, STONE_DARK, Enum.Material.Slate, { Name = "Pedestal" })

	local spire = part({
		Name = "Spire",
		Size = Vector3.new(1.2, 18, 1.2),
		Position = Vector3.new(0, PLAZA_Y + 11, 0),
		Color = ACCENT,
		Material = Enum.Material.Neon,
	})
	pointLight(spire, ACCENT, 46, 1.6)

	-- Slowly spinning ring, driven by physics so it replicates smoothly
	local ring = part({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 9, 9),
		CFrame = CFrame.new(0, PLAZA_Y + 14, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = ACCENT2,
		Material = Enum.Material.Neon,
		Anchored = false,
		CanCollide = false,
		Massless = true,
	})
	local hole = Instance.new("Part")
	hole.Name = "RingHole"
	hole.Shape = Enum.PartType.Cylinder
	hole.Size = Vector3.new(0.8, 7.4, 7.4)
	hole.CFrame = ring.CFrame
	hole.Color = Color3.fromRGB(24, 24, 32)
	hole.Material = Enum.Material.SmoothPlastic
	hole.Anchored = false
	hole.CanCollide = false
	hole.Massless = true
	hole.Parent = root
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = ring
	weld.Part1 = hole
	weld.Parent = ring

	local a0 = Instance.new("Attachment")
	a0.CFrame = CFrame.new(0, 14 - 11, 0) * CFrame.Angles(0, 0, math.rad(90))
	a0.Parent = spire
	local a1 = Instance.new("Attachment")
	a1.Parent = ring
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = a0
	hinge.Attachment1 = a1
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.AngularVelocity = 0.6
	hinge.MotorMaxTorque = 1e6
	hinge.Parent = ring

	-- Sparkles rising from the water
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxassetid://241594419"
	emitter.Color = ColorSequence.new(ACCENT, ACCENT2)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Lifetime = NumberRange.new(2, 3.5)
	emitter.Rate = 14
	emitter.Speed = NumberRange.new(2, 4)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.Parent = (root:FindFirstChild("Water") :: Part)

	-- Floating sign over the spire
	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.fromOffset(360, 90)
	sign.StudsOffset = Vector3.new(0, 12, 0)
	sign.MaxDistance = 220
	sign.Parent = spire
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.RichText = true
	label.Text = "<font color=\"#f5f5fa\">STORY</font><font color=\"#ffc43d\">DUB</font>"
	label.TextStrokeTransparency = 0.6
	label.Parent = sign
end

local function buildPillars()
	for i = 1, 8 do
		local angle = (i - 0.5) / 8 * math.pi * 2
		local r = PLAZA_RADIUS - 6
		local x, z = math.cos(angle) * r, math.sin(angle) * r
		part({ Name = "PillarBase", Size = Vector3.new(4, 1, 4), Position = Vector3.new(x, PLAZA_Y + 0.5, z), Color = STONE_DARK, Material = Enum.Material.Slate })
		part({ Name = "Pillar", Size = Vector3.new(2.4, 14, 2.4), Position = Vector3.new(x, PLAZA_Y + 8, z), Color = STONE_LIGHT, Material = Enum.Material.Slate })
		local cap = part({ Name = "PillarCap", Size = Vector3.new(3, 0.6, 3), Position = Vector3.new(x, PLAZA_Y + 15.3, z), Color = ACCENT2, Material = Enum.Material.Neon })
		pointLight(cap, ACCENT2, 24, 0.8)
	end
end

local function buildLamps()
	for i = 1, 12 do
		local angle = i / 12 * math.pi * 2 + 0.13
		local r = 52
		local x, z = math.cos(angle) * r, math.sin(angle) * r
		part({ Name = "LampPost", Size = Vector3.new(0.5, 7, 0.5), Position = Vector3.new(x, PLAZA_Y + 3.5, z), Color = Color3.fromRGB(40, 40, 52), Material = Enum.Material.Metal })
		local bulb = part({ Name = "LampBulb", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), Position = Vector3.new(x, PLAZA_Y + 7.4, z), Color = Color3.fromRGB(255, 226, 160), Material = Enum.Material.Neon })
		pointLight(bulb, Color3.fromRGB(255, 214, 150), 18, 1)
	end
end

local function buildTrees()
	local rng = Random.new(7)
	for i = 1, 18 do
		local angle = i / 18 * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local r = PLAZA_RADIUS - 11 - rng:NextNumber(0, 3)
		-- leave gaps where the radial paths meet the rim
		local nearPath = false
		for k = 1, 4 do
			local pa = (k - 1) / 4 * math.pi * 2
			local d = math.abs(math.atan2(math.sin(angle - pa), math.cos(angle - pa)))
			if d < 0.22 then nearPath = true end
		end
		if nearPath then continue end
		local x, z = math.cos(angle) * r, math.sin(angle) * r
		local h = rng:NextNumber(6, 9)
		part({ Name = "Trunk", Size = Vector3.new(1, h, 1), Position = Vector3.new(x, PLAZA_Y + h / 2, z), Color = WOOD, Material = Enum.Material.Wood })
		local leaf = LEAF_COLORS[rng:NextInteger(1, #LEAF_COLORS)]
		for j = 1, 3 do
			local s = rng:NextNumber(4, 6.5)
			part({
				Name = "Leaves",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(s, s * 0.85, s),
				Position = Vector3.new(x + rng:NextNumber(-1.6, 1.6), PLAZA_Y + h + rng:NextNumber(-0.5, 2), z + rng:NextNumber(-1.6, 1.6)),
				Color = leaf,
				Material = Enum.Material.Grass,
			})
		end
	end
end

local function buildBenches()
	for i = 1, 8 do
		local angle = (i - 0.5) / 8 * math.pi * 2
		local r = 30
		local cf = CFrame.new(math.cos(angle) * r, PLAZA_Y + 0.9, math.sin(angle) * r) * CFrame.Angles(0, -angle + math.pi / 2, 0)
		part({ Name = "Bench", Size = Vector3.new(5, 0.4, 1.6), CFrame = cf, Color = WOOD, Material = Enum.Material.WoodPlanks })
		part({ Name = "BenchBack", Size = Vector3.new(5, 1.4, 0.3), CFrame = cf * CFrame.new(0, 0.8, -0.65), Color = WOOD, Material = Enum.Material.WoodPlanks })
		part({ Name = "BenchLeg", Size = Vector3.new(4.4, 0.7, 1.2), CFrame = cf * CFrame.new(0, -0.55, 0), Color = STONE_DARK, Material = Enum.Material.Slate })
	end
end

function Hub.build()
	local old = workspace:FindFirstChild("Hub")
	if old then old:Destroy() end
	root = Instance.new("Model")
	root.Name = "Hub"
	root.Parent = workspace

	buildLighting()
	buildSea()
	buildPlaza()
	buildFountain()
	buildPillars()
	buildLamps()
	buildTrees()
	buildBenches()
end

Hub.PLAZA_Y = PLAZA_Y

return Hub
