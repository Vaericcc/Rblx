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
local COURT = 108 -- inner courtyard width (studs)
local WALL_H = 30
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
			local roll = rng:NextInteger(1, 20)
			local shade = ({ STONE, STONE, STONE_LIGHT, STONE_DARK })[rng:NextInteger(1, 4)]
			local material = Enum.Material.Slate
			if roll == 1 and c < 3 then
				shade = Color3.fromRGB(78, 104, 70) -- moss on the low courses
				material = Enum.Material.Grass
			elseif roll == 2 then
				material = Enum.Material.Cobblestone -- a cracked, rougher block
			end
			block(Vector3.new(w - 0.25, course - 0.25, thickness), origin * CFrame.new(x + w / 2, y, 0), shade, material, name)
			x += w
		end
	end
	-- mortar backing so gaps read dark
	block(Vector3.new(length, height, thickness - 0.6), origin * CFrame.new(0, height / 2, 0), MORTAR, Enum.Material.Concrete, name .. "Core")
end

----------------------------------------------------------------------------

local function buildLighting()
	Lighting.ClockTime = 12
	Lighting.GeographicLatitude = 0 -- sun straight overhead: the sunken plaza is lit evenly, no light shafts through the merlons
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(128, 132, 142)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 156, 168)
	Lighting.EnvironmentDiffuseScale = 0.7
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.6
	Lighting.FogEnd = 1400
	for _, name in { "DubbleTakeSky", "DubbleTakeAtmosphere", "DubbleTakeBloom", "DubbleTakeColor", "DubbleTakeRays" } do
		local old = Lighting:FindFirstChild(name)
		if old then old:Destroy() end
	end
	local sky = Instance.new("Sky")
	sky.Name = "DubbleTakeSky"
	sky.SkyboxBk = "rbxassetid://591058823"
	sky.SkyboxDn = "rbxassetid://591059876"
	sky.SkyboxFt = "rbxassetid://591058104"
	sky.SkyboxLf = "rbxassetid://591057861"
	sky.SkyboxRt = "rbxassetid://591057625"
	sky.SkyboxUp = "rbxassetid://591059642"
	sky.StarCount = 1500
	sky.Parent = Lighting
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "DubbleTakeAtmosphere"
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.4
	atmosphere.Color = Color3.fromRGB(200, 206, 214)
	atmosphere.Decay = Color3.fromRGB(110, 118, 130)
	atmosphere.Glare = 0.15
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "DubbleTakeBloom"
	bloom.Intensity = 0.35
	bloom.Size = 24
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "DubbleTakeColor"
	color.Saturation = -0.05
	color.Contrast = 0.1
	color.TintColor = Color3.fromRGB(246, 248, 255)
	color.Parent = Lighting
end

-- Grass hill: concentric square rings that step DOWN away from the walls,
-- so the courtyard reads as cut into a mound.
local function buildHill()
	local inner = COURT / 2 + WALL_T + 12 -- leave room for the gate passages behind each wall
	local ringW = 16
	for t = 1, TERRACES do
		local lo = inner + (t - 1) * ringW
		local hi = lo + ringW
		local top = FLOOR_Y + WALL_H - 2 - (t - 1) * 6
		local thick = 6 + (t - 1) * 6 -- deeper rings further out so the mound has a solid side
		local color = if t % 2 == 0 then GRASS_DARK else GRASS
		for _, def in {
			{ Vector3.new(hi * 2, thick, ringW), Vector3.new(0, 0, -(lo + ringW / 2)) },
			{ Vector3.new(hi * 2, thick, ringW), Vector3.new(0, 0, lo + ringW / 2) },
			{ Vector3.new(ringW, thick, lo * 2), Vector3.new(-(lo + ringW / 2), 0, 0) },
			{ Vector3.new(ringW, thick, lo * 2), Vector3.new(lo + ringW / 2, 0, 0) },
		} do
			block(def[1], CFrame.new(def[2] + Vector3.new(0, top - thick / 2, 0)), color, Enum.Material.Grass, "Terrace")
			block(Vector3.new(def[1].X, 1.2, def[1].Z), CFrame.new(def[2] + Vector3.new(0, top - thick - 0.6, 0)), SOIL, Enum.Material.Ground, "Soil")
		end
	end
	-- Flat meadow beyond the mound, built as four slabs so it never covers the
	-- courtyard floor, and a deep base so nothing floats
	local meadowTop = FLOOR_Y + WALL_H - 2 - TERRACES * 6
	local hole = inner + TERRACES * ringW
	local half = (HILL_SIZE + 200) / 2
	for _, def in {
		{ Vector3.new(half * 2, 4, half - hole), Vector3.new(0, 0, -(hole + (half - hole) / 2)) },
		{ Vector3.new(half * 2, 4, half - hole), Vector3.new(0, 0, hole + (half - hole) / 2) },
		{ Vector3.new(half - hole, 4, hole * 2), Vector3.new(-(hole + (half - hole) / 2), 0, 0) },
		{ Vector3.new(half - hole, 4, hole * 2), Vector3.new(hole + (half - hole) / 2, 0, 0) },
	} do
		block(def[1], CFrame.new(def[2] + Vector3.new(0, meadowTop - 2, 0)), GRASS, Enum.Material.Grass, "Meadow")
	end
	block(Vector3.new(half * 2, 30, half * 2), CFrame.new(0, FLOOR_Y - 17, 0), SOIL, Enum.Material.Ground, "Base")
	-- Flat grass shelf directly behind the walls, under the gate passages, at wall-top height
	local shelfTop = FLOOR_Y + WALL_H - 2
	local shelfIn = COURT / 2 + WALL_T
	for _, def in {
		{ Vector3.new(inner * 2, 6, inner - shelfIn), Vector3.new(0, 0, -(shelfIn + (inner - shelfIn) / 2)) },
		{ Vector3.new(inner * 2, 6, inner - shelfIn), Vector3.new(0, 0, shelfIn + (inner - shelfIn) / 2) },
		{ Vector3.new(inner - shelfIn, 6, shelfIn * 2), Vector3.new(-(shelfIn + (inner - shelfIn) / 2), 0, 0) },
		{ Vector3.new(inner - shelfIn, 6, shelfIn * 2), Vector3.new(shelfIn + (inner - shelfIn) / 2, 0, 0) },
	} do
		block(def[1], CFrame.new(def[2] + Vector3.new(0, shelfTop - 3, 0)), GRASS_DARK, Enum.Material.Grass, "Shelf")
	end
end

-- Flagstone floor: alternating pale/grey tiles with a darker border and a dais.
local function buildFloor()
	local tile = 6
	local n = COURT / tile
	local walk = 2 -- tiles of raised walkway along the walls
	for ix = 0, n - 1 do
		for iz = 0, n - 1 do
			local x = -COURT / 2 + ix * tile + tile / 2
			local z = -COURT / 2 + iz * tile + tile / 2
			local ring = math.min(ix, iz, n - 1 - ix, n - 1 - iz)
			local raised = ring < walk
			local color = if raised then (if (ix + iz) % 2 == 0 then STONE_LIGHT else STONE) elseif (ix + iz) % 2 == 0 then Color3.fromRGB(222, 220, 214) else STONE_PALE
			local y = if raised then FLOOR_Y + 1.5 else FLOOR_Y
			local thick = if raised then 2.5 else 1
			block(Vector3.new(tile - 0.25, thick, tile - 0.25), CFrame.new(x, y - thick / 2, z), color, Enum.Material.Slate, "Flag")
		end
	end
	-- step between walkway and plaza
	local inner = COURT / 2 - walk * tile
	for _, def in {
		{ Vector3.new(inner * 2 + 2, 0.75, 1), Vector3.new(0, 0, inner + 0.5) },
		{ Vector3.new(inner * 2 + 2, 0.75, 1), Vector3.new(0, 0, -(inner + 0.5)) },
		{ Vector3.new(1, 0.75, inner * 2), Vector3.new(inner + 0.5, 0, 0) },
		{ Vector3.new(1, 0.75, inner * 2), Vector3.new(-(inner + 0.5), 0, 0) },
	} do
		block(def[1], CFrame.new(def[2] + Vector3.new(0, FLOOR_Y + 0.375, 0)), STONE_LIGHT, Enum.Material.Slate, "Step")
	end
	block(Vector3.new(COURT, 1.2, COURT), CFrame.new(0, FLOOR_Y - 1.1, 0), MORTAR, Enum.Material.Concrete, "FloorCore")
	-- Central dais: three steps and a plinth with a glowing emblem
	for i, s in { 22, 17, 12 } do
		block(Vector3.new(s, 1, s), CFrame.new(0, FLOOR_Y + i - 0.5, 0), if i % 2 == 0 then STONE_LIGHT else STONE_PALE, Enum.Material.Slate, "Dais")
	end
	local plinth = block(Vector3.new(5, 6, 5), CFrame.new(0, FLOOR_Y + 6, 0), STONE_DARK, Enum.Material.Slate, "Plinth")
	block(Vector3.new(6, 0.8, 6), CFrame.new(0, FLOOR_Y + 9.4, 0), STONE_LIGHT, Enum.Material.Slate, "PlinthCap")
	-- recessed emblem: a shallow dark niche with a thin warm inlay, not a glowing cube
	for _, rot in { 0, 90, 180, 270 } do
		local r = CFrame.Angles(0, math.rad(rot), 0)
		block(Vector3.new(2.6, 2.6, 0.3), r * CFrame.new(0, FLOOR_Y + 6.5, 2.45), MORTAR, Enum.Material.Concrete, "Niche")
		local inlay = block(Vector3.new(1.2, 1.2, 0.15), r * CFrame.new(0, FLOOR_Y + 6.5, 2.55), Color3.fromRGB(214, 170, 70), Enum.Material.Metal, "Emblem")
		inlay.Reflectance = 0.3
		inlay.CastShadow = false
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 210, 140)
	light.Range = 14
	light.Brightness = 0.3
	light.Parent = plinth
	-- Soft fill so the sunken floor isn't permanently in the walls' shadow
	local fill = Instance.new("PointLight")
	fill.Color = Color3.fromRGB(230, 236, 255)
	fill.Range = 110
	fill.Brightness = 0.35
	fill.Shadows = false
	fill.Parent = plinth
	-- Floating sign: anchored to an invisible point straight above the plinth
	-- (no billboard offset), so it stays centred from every angle.
	local signAnchor = block(Vector3.new(1, 1, 1), CFrame.new(0, FLOOR_Y + 24, 0), STONE, Enum.Material.SmoothPlastic, "SignAnchor")
	signAnchor.Transparency = 1
	signAnchor.CanCollide = false
	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.new(24, 0, 6.5, 0) -- studs, so it keeps its world size on every screen
	sign.MaxDistance = 300
	sign.Parent = signAnchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Bangers
	label.TextScaled = true
	label.RichText = true
	label.Text = "<font color=\"#f0eadc\">DUBBLE</font><font color=\"#ff466e\">TAKE</font>"
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(18, 16, 20)
	label.Parent = sign
end

-- A gothic gateway: two piers, an arch built from stacked offset blocks, a dark doorway.
local function buildGateway(cf: CFrame)
	local pierW, gapW, archH = 6, 14, 15 -- arch springs at 15 so it reads from the floor
	local total = pierW * 2 + gapW
	for side = -1, 1, 2 do
		local x = side * (gapW / 2 + pierW / 2)
		masonry(cf * CFrame.new(x, 0, 0), pierW, archH, WALL_T + 2, "Pier")
		-- engaged column on the courtyard face (+z is the courtyard side), with base and capital
		local colZ = WALL_T / 2 + 1.6
		part({ Name = "ColumnBase", Size = Vector3.new(2.6, 1, 2.6), CFrame = cf * CFrame.new(x, 0.5, colZ), Color = STONE_LIGHT })
		part({ Name = "Column", Shape = Enum.PartType.Cylinder, Size = Vector3.new(archH - 2, 2, 2), CFrame = cf * CFrame.new(x, archH / 2, colZ) * CFrame.Angles(0, 0, math.rad(90)), Color = STONE_PALE, Material = Enum.Material.Marble })
		part({ Name = "Capital", Size = Vector3.new(2.8, 1.2, 2.8), CFrame = cf * CFrame.new(x, archH - 0.4, colZ), Color = STONE_LIGHT })
		-- pinnacle above the pier
		block(Vector3.new(pierW + 1.5, 1.5, WALL_T + 3.5), cf * CFrame.new(x, WALL_H + 0.75, 0), STONE_LIGHT, Enum.Material.Slate, "PierCap")
		block(Vector3.new(3, 7, 3), cf * CFrame.new(x, WALL_H + 5, 0), STONE, Enum.Material.Slate, "Pinnacle")
		block(Vector3.new(1.4, 3, 1.4), cf * CFrame.new(x, WALL_H + 10, 0), STONE_LIGHT, Enum.Material.Slate, "Spike")
	end
	-- Pointed arch of voussoirs: wedge blocks rotated along the curve, proud of the wall so it reads from inside
	local steps = 8
	local peak = archH + 7
	for i = 1, steps do
		local frac = i / steps
		local halfSpan = gapW / 2 * (1 - frac * frac)
		local y = archH + (i - 1) * (peak - archH) / steps
		for side = -1, 1, 2 do
			-- radial stones: upright at the spring, lying flat at the peak
			local tilt = -side * (90 - 82 * frac)
			block(Vector3.new(3.4, 2.2, WALL_T + 4), cf * CFrame.new(side * (halfSpan + 1.5), y, 0) * CFrame.Angles(0, 0, math.rad(tilt)),
				if i % 2 == 0 then STONE_LIGHT else STONE_PALE, Enum.Material.Slate, "Voussoir")
		end
	end
	block(Vector3.new(3.6, 3.2, WALL_T + 4.4), cf * CFrame.new(0, peak + 0.6, 0), STONE_PALE, Enum.Material.Slate, "Keystone")
	-- Masonry above the arch up to the parapet, and the dark doorway recessed behind
	local above = WALL_H - (peak + 2)
	if above > 0 then
		masonry(cf * CFrame.new(0, peak + 2, 0), total, above, WALL_T, "Lintel")
	end
	-- The opening is a real tunnel through the wall: stone reveals either side, a
	-- vaulted top, and a dark back wall set deep so it reads as depth, with a dim lamp.
	local depth = WALL_T + 8
	for side = -1, 1, 2 do
		block(Vector3.new(1.2, peak, depth), cf * CFrame.new(side * (gapW / 2 + 0.6), peak / 2, -(depth - WALL_T) / 2), STONE_DARK, Enum.Material.Slate, "Reveal")
	end
	block(Vector3.new(gapW + 2.4, 1.2, depth), cf * CFrame.new(0, peak + 0.6, -(depth - WALL_T) / 2), STONE_DARK, Enum.Material.Slate, "Vault")
	block(Vector3.new(gapW, peak, 1), cf * CFrame.new(0, peak / 2, -(depth - WALL_T / 2)), Color3.fromRGB(10, 10, 14), Enum.Material.SmoothPlastic, "Doorway")
	local lamp = block(Vector3.new(1, 1, 1), cf * CFrame.new(0, peak - 2, -(depth - WALL_T / 2) + 1), TORCH, Enum.Material.Neon, "TunnelLamp")
	local tl = Instance.new("PointLight")
	tl.Color = TORCH
	tl.Range = 16
	tl.Brightness = 1
	tl.Parent = lamp
	-- Stone gatehouse around the passage outside the wall (roof and flanks), so no earth shows inside
	local outZ = -(WALL_T / 2 + (depth - WALL_T) / 2)
	block(Vector3.new(gapW + 2.4 + 6, 3, depth - WALL_T + 1), cf * CFrame.new(0, peak + 2.7, outZ), STONE_DARK, Enum.Material.Slate, "GateRoof")
	for side = -1, 1, 2 do
		block(Vector3.new(3, peak + 4, depth - WALL_T + 1), cf * CFrame.new(side * (gapW / 2 + 2.7), (peak + 4) / 2, outZ), STONE_DARK, Enum.Material.Slate, "GateFlank")
	end
	-- Iron portcullis bars so the void reads as a gate
	for i = -3, 3 do
		block(Vector3.new(0.3, peak - 1, 0.3), cf * CFrame.new(i * (gapW / 7), (peak - 1) / 2, -(depth - WALL_T / 2) + 2.5), Color3.fromRGB(40, 36, 34), Enum.Material.Metal, "Bar")
	end
	-- Torches flanking the doorway
	for side = -1, 1, 2 do
		local tx = side * (gapW / 2 + 1)
		local bracket = block(Vector3.new(0.6, 2.4, 0.6), cf * CFrame.new(tx + side * 2.2, 9, WALL_T / 2 + 0.8), Color3.fromRGB(40, 36, 34), Enum.Material.Metal, "Bracket")
		local flame = block(Vector3.new(1, 1.4, 1), cf * CFrame.new(tx + side * 2.2, 10.6, WALL_T / 2 + 0.8), TORCH, Enum.Material.Neon, "Flame")
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
			-- pilaster on the courtyard face
			local bx = dir * (gateTotal / 2 + segment * 0.55)
			block(Vector3.new(3, WALL_H - 2, 1.6), wallCf * CFrame.new(bx, (WALL_H - 2) / 2, WALL_T / 2 + 0.8), STONE_DARK, Enum.Material.Slate, "Pilaster")
			block(Vector3.new(3.8, 1.2, 2.4), wallCf * CFrame.new(bx, WALL_H - 1.4, WALL_T / 2 + 1.2), STONE_LIGHT, Enum.Material.Slate, "PilasterCap")
			-- tall slit window with a lit interior
			block(Vector3.new(1.6, 9, 0.6), wallCf * CFrame.new(bx + dir * 9, WALL_H * 0.55, WALL_T / 2 + 0.2), Color3.fromRGB(14, 14, 18), Enum.Material.SmoothPlastic, "Window")
			local glow = block(Vector3.new(1.2, 8, 0.2), wallCf * CFrame.new(bx + dir * 9, WALL_H * 0.55, WALL_T / 2 + 0.45), Color3.fromRGB(255, 200, 120), Enum.Material.Neon, "WindowGlow")
			glow.Transparency = 0.6
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
	for _, p in { Vector3.new(20, 0, 20), Vector3.new(-20, 0, 20), Vector3.new(20, 0, -20), Vector3.new(-20, 0, -20) } do table.insert(spots, p) end
	for _, pos in spots do
		-- corner planters sit on the raised walkway
		local lift = if math.abs(pos.X) > COURT / 2 - 14 or math.abs(pos.Z) > COURT / 2 - 14 then 1.5 else 0
		pos = pos + Vector3.new(0, lift, 0)
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

-- Four spawn points, one per courtyard corner on the plaza floor, clear of the
-- platforms, planters and dais. Invisible: the flagstones are the floor.
local function buildSpawns()
	-- the old single spawn in front of the dais may still exist in a synced place
	local old = workspace:FindFirstChild("SpawnLocation")
	if old then old:Destroy() end
	local d = COURT / 2 - 18
	for _, c in { Vector2.new(1, 1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.new(-1, -1) } do
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn"
		spawn.Anchored = true
		spawn.Size = Vector3.new(8, 1, 8)
		spawn.CFrame = CFrame.new(c.X * d, FLOOR_Y + 0.5, c.Y * d)
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Parent = root
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
	local inner = COURT / 2 + WALL_T + 2
	local positions = {}
	for t = 2, TERRACES do
		local ring = inner + (t - 1) * 16 + 8
		local top = FLOOR_Y + WALL_H - 2 - (t - 1) * 6
		local count = 10 + t * 3
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
	-- a loose belt of trees on the meadow beyond the mound
	local meadowTop = FLOOR_Y + WALL_H - 2 - TERRACES * 6
	for i = 1, 40 do
		local a = i / 40 * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local r = inner + TERRACES * 16 + rng:NextNumber(10, 60)
		local x, z = math.cos(a) * r, math.sin(a) * r
		if math.abs(x) < 18 or math.abs(z) < 18 then continue end
		table.insert(positions, Vector3.new(x, meadowTop, z))
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

-- The Baseplate template's slab tops out at y=0, exactly the flagstone plane,
-- so it z-fights the floor (white shapes "clipping through"). Remove template
-- leftovers before building.
local function clearTemplate()
	for _, name in { "Baseplate", "SpawnLocation" } do
		local inst = workspace:FindFirstChild(name)
		if inst and not inst:IsDescendantOf(root) then inst:Destroy() end
	end
	-- anything else big and flat at floor level (a terrain-less template floor)
	for _, inst in workspace:GetChildren() do
		if inst:IsA("BasePart") and inst.Size.X >= 400 and inst.Size.Z >= 400 then inst:Destroy() end
	end
end

function Hub.build()
	clearTemplate()
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
	buildSpawns()
	buildTrees()
	-- Hall of Fame against the wall between the first gateway and a corner
	require(script.Parent.Leaderboard).init(CFrame.new(-28, FLOOR_Y + 1.5 + 6.5, -(COURT / 2 - 3)) * CFrame.Angles(0, 0, 0))
end

Hub.FLOOR_Y = FLOOR_Y
Hub.COURT = COURT

return Hub
