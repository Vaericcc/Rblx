--!strict
--[[
	The hub: a sunken stone courtyard cut into a grass hill, after the reference.
	Masonry walls ring a square flagstone floor; four tall arched gateways face
	the four platforms; a central dais; planters and wall torches. Trees and
	props are cloned from ReplicatedStorage/Assets/{Trees,Props} when present,
	otherwise built from parts. Cool daylight so the stone reads grey.
]]
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hub = {}

-- Geometry --------------------------------------------------------------------
local COURT = 96 -- inner courtyard width (studs)
local WALL_H = 34
local WALL_T = 6
local FLOOR_Y = 0 -- top of the flagstones
local HILL_SIZE = 360
local TERRACES = 4

-- Palette ---------------------------------------------------------------------
local STONE = Color3.fromRGB(118, 120, 124)
local STONE_DARK = Color3.fromRGB(78, 80, 86)
local STONE_LIGHT = Color3.fromRGB(160, 162, 166)
local STONE_PALE = Color3.fromRGB(196, 196, 198)
local MORTAR = Color3.fromRGB(58, 60, 64)
local GRASS = Color3.fromRGB(110, 140, 70)
local GRASS_DARK = Color3.fromRGB(88, 116, 56)
local SOIL = Color3.fromRGB(70, 56, 44)
local LEAF = { Color3.fromRGB(84, 134, 72), Color3.fromRGB(104, 152, 84), Color3.fromRGB(70, 118, 66) }
local TORCH = Color3.fromRGB(255, 190, 110)

local root: Model
local rng = Random.new(42)

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Slate
	p.Color = STONE
	for k, v in props do (p :: any)[k] = v end
	if not props.Parent then p.Parent = root end
	return p
end

local function block(size: Vector3, cf: CFrame, color: Color3?, material: Enum.Material?, name: string?): Part
	return part({ Name = name or "Stone", Size = size, CFrame = cf, Color = color or STONE, Material = material or Enum.Material.Slate })
end

-- Stacked masonry: alternating course offsets so walls read as blocks, not slabs.
local function masonry(origin: CFrame, length: number, height: number, thickness: number, name: string)
	local course = 3
	local courses = math.floor(height / course)
	for c = 0, courses - 1 do
		local y = c * course + course / 2
		local offset = if c % 2 == 0 then 0 else 3
		local x = -length / 2 + offset
		while x < length / 2 do
			local w = math.min(6, length / 2 - x)
			if w <= 0.5 then break end
			local shade = ({ STONE, STONE, STONE_LIGHT, STONE_DARK })[rng:NextInteger(1, 4)]
			block(Vector3.new(w - 0.25, course - 0.25, thickness), origin * CFrame.new(x + w / 2, y, 0), shade, Enum.Material.Slate, name)
			x += w
		end
	end
	-- mortar backing so gaps read dark
	block(Vector3.new(length, height, thickness - 0.6), origin * CFrame.new(0, height / 2, 0), MORTAR, Enum.Material.Concrete, name .. "Core")
end

----------------------------------------------------------------------------

local function buildLighting()
	Lighting.ClockTime = 13.2
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(96, 100, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 134, 146)
	Lighting.EnvironmentDiffuseScale = 0.7
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	Lighting.FogEnd = 1400
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
	sky.StarCount = 1500
	sky.Parent = Lighting
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "StoryDubAtmosphere"
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.4
	atmosphere.Color = Color3.fromRGB(200, 206, 214)
	atmosphere.Decay = Color3.fromRGB(110, 118, 130)
	atmosphere.Glare = 0.15
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "StoryDubBloom"
	bloom.Intensity = 0.35
	bloom.Size = 24
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "StoryDubColor"
	color.Saturation = -0.05
	color.Contrast = 0.1
	color.TintColor = Color3.fromRGB(246, 248, 255)
	color.Parent = Lighting
end

-- Grass hill in stepped terraces, with the courtyard cut out of the middle.
local function buildHill()
	local outer = COURT / 2 + WALL_T + 4
	for t = 1, TERRACES do
		local size = HILL_SIZE - (t - 1) * 60
		local top = FLOOR_Y + WALL_H - (t - 1) * 7 -- terraces step down toward the walls
		local thickness = 7
		local color = if t % 2 == 0 then GRASS_DARK else GRASS
		local half = size / 2
		-- four slabs around the hole so the courtyard stays open
		local hole = if t == 1 then outer else outer + (t - 1) * 12
		local span = half - hole
		if span <= 0 then continue end
		for _, def in {
			{ Vector3.new(size, thickness, span), Vector3.new(0, 0, -(hole + span / 2)) },
			{ Vector3.new(size, thickness, span), Vector3.new(0, 0, hole + span / 2) },
			{ Vector3.new(span, thickness, hole * 2), Vector3.new(-(hole + span / 2), 0, 0) },
			{ Vector3.new(span, thickness, hole * 2), Vector3.new(hole + span / 2, 0, 0) },
		} do
			block(def[1], CFrame.new(def[2] + Vector3.new(0, top - thickness / 2, 0)), color, Enum.Material.Grass, "Terrace")
			-- soil face
			block(Vector3.new(def[1].X, 1.2, def[1].Z), CFrame.new(def[2] + Vector3.new(0, top - thickness - 0.6, 0)), SOIL, Enum.Material.Ground, "Soil")
		end
	end
	-- Deep base so nothing floats
	block(Vector3.new(HILL_SIZE + 40, 30, HILL_SIZE + 40), CFrame.new(0, FLOOR_Y - 18, 0), SOIL, Enum.Material.Ground, "Base")
end

-- Flagstone floor: alternating pale/grey tiles with a darker border and a dais.
local function buildFloor()
	local tile = 8
	local n = COURT / tile
	for ix = 0, n - 1 do
		for iz = 0, n - 1 do
			local x = -COURT / 2 + ix * tile + tile / 2
			local z = -COURT / 2 + iz * tile + tile / 2
			local edge = ix == 0 or iz == 0 or ix == n - 1 or iz == n - 1
			local color = if edge then STONE_DARK elseif (ix + iz) % 2 == 0 then STONE_PALE else STONE_LIGHT
			block(Vector3.new(tile - 0.3, 1, tile - 0.3), CFrame.new(x, FLOOR_Y - 0.5, z), color, Enum.Material.Slate, "Flag")
		end
	end
	block(Vector3.new(COURT, 1.2, COURT), CFrame.new(0, FLOOR_Y - 1.1, 0), MORTAR, Enum.Material.Concrete, "FloorCore")
	-- Central dais: three steps and a plinth with a glowing emblem
	for i, s in { 22, 17, 12 } do
		block(Vector3.new(s, 1, s), CFrame.new(0, FLOOR_Y + i - 0.5, 0), if i % 2 == 0 then STONE_LIGHT else STONE_PALE, Enum.Material.Slate, "Dais")
	end
	local plinth = block(Vector3.new(5, 6, 5), CFrame.new(0, FLOOR_Y + 6, 0), STONE_DARK, Enum.Material.Slate, "Plinth")
	for _, rot in { 0, 90, 180, 270 } do
		block(Vector3.new(3.4, 3.4, 0.4), CFrame.Angles(0, math.rad(rot), 0) * CFrame.new(0, FLOOR_Y + 7, 2.6), Color3.fromRGB(255, 196, 61), Enum.Material.Neon, "Emblem")
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 196, 61)
	light.Range = 30
	light.Brightness = 1.2
	light.Parent = plinth
	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.fromOffset(420, 110)
	sign.StudsOffset = Vector3.new(0, 8, 0)
	sign.MaxDistance = 260
	sign.Parent = plinth
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Bangers
	label.TextScaled = true
	label.RichText = true
	label.Text = "<font color=\"#f0eadc\">STORY</font><font color=\"#ff466e\">DUB</font>"
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(18, 16, 20)
	label.Parent = sign
end

-- A gothic gateway: two piers, an arch built from stacked offset blocks, a dark doorway.
local function buildGateway(cf: CFrame)
	local pierW, gapW, archH = 6, 14, 26
	local total = pierW * 2 + gapW
	for side = -1, 1, 2 do
		local x = side * (gapW / 2 + pierW / 2)
		masonry(cf * CFrame.new(x, 0, 0), pierW, archH, WALL_T + 2, "Pier")
		-- capital and pinnacle
		block(Vector3.new(pierW + 1.5, 1.5, WALL_T + 3.5), cf * CFrame.new(x, archH + 0.75, 0), STONE_LIGHT, Enum.Material.Slate, "Capital")
		block(Vector3.new(3, 8, 3), cf * CFrame.new(x, archH + 5.5, 0), STONE, Enum.Material.Slate, "Pinnacle")
		block(Vector3.new(1.4, 3, 1.4), cf * CFrame.new(x, archH + 11, 0), STONE_LIGHT, Enum.Material.Slate, "Spike")
	end
	-- Pointed arch: stepped blocks rising to a peak
	local steps = 7
	for i = 1, steps do
		local frac = i / steps
		local halfSpan = gapW / 2 * (1 - frac * frac)
		local y = archH + 1.5 + (i - 1) * 2.2
		for side = -1, 1, 2 do
			block(Vector3.new(3.6, 2.2, WALL_T + 2.5), cf * CFrame.new(side * (halfSpan + 1.6), y, 0), if i % 2 == 0 then STONE else STONE_LIGHT, Enum.Material.Slate, "Arch")
		end
	end
	block(Vector3.new(4, 3, WALL_T + 3), cf * CFrame.new(0, archH + 1.5 + steps * 2.2, 0), STONE_LIGHT, Enum.Material.Slate, "Keystone")
	-- Wall above the arch up to full height, and the dark doorway behind
	local above = WALL_H + 12 - (archH + 1.5 + steps * 2.2 + 1.5)
	if above > 0 then
		masonry(cf * CFrame.new(0, archH + 1.5 + steps * 2.2 + 1.5, 0), total, above, WALL_T, "Lintel")
	end
	block(Vector3.new(gapW, archH + 14, 1), cf * CFrame.new(0, (archH + 14) / 2, WALL_T / 2 + 2), Color3.fromRGB(14, 14, 18), Enum.Material.SmoothPlastic, "Doorway")
	-- Torches flanking the doorway
	for side = -1, 1, 2 do
		local tx = side * (gapW / 2 + 1)
		local bracket = block(Vector3.new(0.6, 2.4, 0.6), cf * CFrame.new(tx, 9, -WALL_T / 2 - 0.6), Color3.fromRGB(40, 36, 34), Enum.Material.Metal, "Bracket")
		local flame = block(Vector3.new(1, 1.4, 1), cf * CFrame.new(tx, 10.6, -WALL_T / 2 - 0.6), TORCH, Enum.Material.Neon, "Flame")
		local l = Instance.new("PointLight")
		l.Color = TORCH
		l.Range = 22
		l.Brightness = 1.4
		l.Parent = flame
		local fire = Instance.new("Fire")
		fire.Size = 3
		fire.Heat = 6
		fire.Parent = flame
		bracket.Parent = root
	end
end

-- Ring walls with a gateway in the middle of each side, buttresses between.
local function buildWalls()
	local half = COURT / 2 + WALL_T / 2
	local gateTotal = 26
	local segment = (COURT - gateTotal) / 2
	for side = 1, 4 do
		local rot = CFrame.Angles(0, math.rad((side - 1) * 90), 0)
		local wallCf = rot * CFrame.new(0, FLOOR_Y, -half) -- wall plane facing inward
		for dir = -1, 1, 2 do
			masonry(wallCf * CFrame.new(dir * (gateTotal / 2 + segment / 2), 0, 0), segment, WALL_H, WALL_T, "Wall")
			-- buttress
			local bx = dir * (gateTotal / 2 + segment * 0.55)
			block(Vector3.new(4, WALL_H - 4, WALL_T + 4), wallCf * CFrame.new(bx, (WALL_H - 4) / 2, 0), STONE_DARK, Enum.Material.Slate, "Buttress")
			block(Vector3.new(5, 1.5, WALL_T + 5), wallCf * CFrame.new(bx, WALL_H - 3.25, 0), STONE_LIGHT, Enum.Material.Slate, "ButtressCap")
			-- tall slit window
			block(Vector3.new(1.6, 9, 0.4), wallCf * CFrame.new(bx + dir * 9, WALL_H * 0.55, -WALL_T / 2 - 0.1), Color3.fromRGB(14, 14, 18), Enum.Material.SmoothPlastic, "Window")
		end
		-- parapet along the top
		block(Vector3.new(COURT + WALL_T * 2, 1.5, WALL_T + 2), wallCf * CFrame.new(0, WALL_H + 0.75, 0), STONE_LIGHT, Enum.Material.Slate, "Parapet")
		for i = -6, 6 do
			block(Vector3.new(3, 2.2, WALL_T + 2), wallCf * CFrame.new(i * 8, WALL_H + 2.6, 0), STONE, Enum.Material.Slate, "Merlon")
		end
		buildGateway(wallCf)
		-- corner tower
		local corner = rot * CFrame.new(half + 1, FLOOR_Y, -half - 1)
		masonry(corner, 10, WALL_H + 6, 10, "Tower")
		block(Vector3.new(12, 1.5, 12), corner * CFrame.new(0, WALL_H + 6.75, 0), STONE_LIGHT, Enum.Material.Slate, "TowerCap")
	end
end

-- Planters with greenery in the corners and along the walls.
local function buildPlanters()
	local spots = {}
	local d = COURT / 2 - 10
	for _, p in { Vector3.new(d, 0, d), Vector3.new(-d, 0, d), Vector3.new(d, 0, -d), Vector3.new(-d, 0, -d) } do table.insert(spots, p) end
	for _, p in { Vector3.new(0, 0, 24), Vector3.new(0, 0, -24), Vector3.new(24, 0, 0), Vector3.new(-24, 0, 0) } do table.insert(spots, p) end
	for _, pos in spots do
		block(Vector3.new(7, 2.4, 7), CFrame.new(pos + Vector3.new(0, FLOOR_Y + 1.2, 0)), STONE_DARK, Enum.Material.Slate, "Planter")
		block(Vector3.new(6, 0.6, 6), CFrame.new(pos + Vector3.new(0, FLOOR_Y + 2.5, 0)), SOIL, Enum.Material.Ground, "PlanterSoil")
		for i = 1, 3 do
			local s = rng:NextNumber(2.2, 3.4)
			part({ Name = "Shrub", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.8, s),
				Position = pos + Vector3.new(rng:NextNumber(-1.4, 1.4), FLOOR_Y + 3.2 + rng:NextNumber(0, 0.6), rng:NextNumber(-1.4, 1.4)),
				Color = LEAF[rng:NextInteger(1, #LEAF)], Material = Enum.Material.Grass })
		end
	end
end

-- Trees on the terraces: clone player-supplied models if present, else build.
local function treeModels(): { Instance }
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Trees")
	return if folder then folder:GetChildren() else {}
end

local function placeModel(model: Instance, position: Vector3, yaw: number)
	local clone = model:Clone()
	if clone:IsA("Model") then
		clone:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
	elseif clone:IsA("BasePart") then
		clone.CFrame = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	end
	clone.Parent = root
end

local function buildTree(position: Vector3)
	local h = rng:NextNumber(9, 14)
	block(Vector3.new(1.4, h, 1.4), CFrame.new(position + Vector3.new(0, h / 2, 0)), Color3.fromRGB(86, 62, 44), Enum.Material.Wood, "Trunk")
	-- layered canopy: a stack of flattened spheres, wider low, narrower high
	local layers = 3
	for i = 1, layers do
		local s = (8 - i * 1.6) * rng:NextNumber(0.9, 1.15)
		part({ Name = "Canopy", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.7, s),
			Position = position + Vector3.new(rng:NextNumber(-0.8, 0.8), h - 2 + i * 2.2, rng:NextNumber(-0.8, 0.8)),
			Color = LEAF[((i + rng:NextInteger(0, 1)) % #LEAF) + 1], Material = Enum.Material.Grass })
	end
end

local function buildTrees()
	local models = treeModels()
	local outer = COURT / 2 + WALL_T + 14
	local positions = {}
	for t = 1, TERRACES do
		local ring = outer + (t - 1) * 14 + 6
		local top = FLOOR_Y + WALL_H - (t - 1) * 7
		local count = 10 + t * 2
		for i = 1, count do
			local a = i / count * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
			-- square-ish ring so trees follow the terraces
			local x, z = math.cos(a), math.sin(a)
			local m = math.max(math.abs(x), math.abs(z))
			x, z = x / m * ring, z / m * ring
			-- keep the four gateway approaches clear
			if math.abs(x) < 16 or math.abs(z) < 16 then continue end
			table.insert(positions, Vector3.new(x, top, z))
		end
	end
	for _, pos in positions do
		if #models > 0 then
			placeModel(models[rng:NextInteger(1, #models)], pos, rng:NextNumber(0, math.pi * 2))
		else
			buildTree(pos)
		end
	end
	-- Props folder (benches, lanterns, barrels) scattered inside the courtyard edge
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local props = assets and assets:FindFirstChild("Props")
	if props and #props:GetChildren() > 0 then
		local list = props:GetChildren()
		for i = 1, 12 do
			local a = i / 12 * math.pi * 2 + 0.2
			local x, z = math.cos(a), math.sin(a)
			local m = math.max(math.abs(x), math.abs(z))
			local r = COURT / 2 - 5
			placeModel(list[rng:NextInteger(1, #list)], Vector3.new(x / m * r, FLOOR_Y, z / m * r), -a)
		end
	end
end

function Hub.build()
	local old = workspace:FindFirstChild("Hub")
	if old then old:Destroy() end
	root = Instance.new("Model")
	root.Name = "Hub"
	root.Parent = workspace
	buildLighting()
	buildHill()
	buildFloor()
	buildWalls()
	buildPlanters()
	buildTrees()
end

Hub.FLOOR_Y = FLOOR_Y
Hub.COURT = COURT

return Hub
