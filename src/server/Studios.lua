--!strict
--[[
	Private studios. Each match teleports its players into a sealed room far
	from the hub so proximity voice chat only carries their own group. Studios
	are built lazily and reused.
]]
local Players = game:GetService("Players")

local Studios = {}

local STUDIO_SIZE = Vector3.new(40, 1, 40)
local STUDIO_HEIGHT = 500 -- well above the hub
local STUDIO_SPACING = 300 -- visual separation only; audio isolation is enforced by VoiceIsolation
local GRID_COLUMNS = 8 -- studios are laid out in a grid so coordinates stay small with many matches
local RETURN_POSITION = Vector3.new(0, 6, 18) -- just off the dais

type Studio = { index: number, model: Model, floor: Part, inUse: boolean }
local studios: { Studio } = {}

local function build(index: number): Studio
	local col = (index - 1) % GRID_COLUMNS
	local row = (index - 1) // GRID_COLUMNS
	local origin = Vector3.new((col + 1) * STUDIO_SPACING, STUDIO_HEIGHT, (row + 1) * STUDIO_SPACING)
	local model = Instance.new("Model")
	model.Name = ("Studio%d"):format(index)

	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = STUDIO_SIZE
	floor.Position = origin
	floor.Color = Color3.fromRGB(36, 36, 48)
	floor.Material = Enum.Material.SmoothPlastic
	floor.Parent = model

	-- Walls keep players inside and make the space feel like a room.
	local wallHeight = 16
	local half = STUDIO_SIZE.X / 2
	for _, def in {
		{ Vector3.new(0, 0, half), Vector3.new(STUDIO_SIZE.X, wallHeight, 1) },
		{ Vector3.new(0, 0, -half), Vector3.new(STUDIO_SIZE.X, wallHeight, 1) },
		{ Vector3.new(half, 0, 0), Vector3.new(1, wallHeight, STUDIO_SIZE.Z) },
		{ Vector3.new(-half, 0, 0), Vector3.new(1, wallHeight, STUDIO_SIZE.Z) },
	} do
		local wall = Instance.new("Part")
		wall.Anchored = true
		wall.Size = def[2]
		wall.Position = origin + def[1] + Vector3.new(0, wallHeight / 2, 0)
		wall.Color = Color3.fromRGB(24, 24, 32)
		wall.Transparency = 0.2
		wall.Parent = model
	end
	local ceiling = Instance.new("Part")
	ceiling.Anchored = true
	ceiling.Size = Vector3.new(STUDIO_SIZE.X, 1, STUDIO_SIZE.Z)
	ceiling.Position = origin + Vector3.new(0, wallHeight, 0)
	ceiling.Color = Color3.fromRGB(24, 24, 32)
	ceiling.Parent = model

	local light = Instance.new("PointLight")
	light.Range = 40
	light.Brightness = 1.5
	light.Parent = floor

	model.Parent = workspace
	return { index = index, model = model, floor = floor, inUse = false }
end

function Studios.acquire(): Studio
	for _, s in studios do
		if not s.inUse then
			s.inUse = true
			return s
		end
	end
	local s = build(#studios + 1)
	s.inUse = true
	table.insert(studios, s)
	return s
end

function Studios.release(studio: Studio)
	studio.inUse = false
end

local function moveTo(player: Player, position: Vector3, facing: Vector3?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local cf = if facing then CFrame.lookAt(position, facing) else CFrame.new(position)
		root.CFrame = cf
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

-- Arrange the group in a circle facing the middle.
function Studios.enter(studio: Studio, players: { Player })
	local center = studio.floor.Position + Vector3.new(0, 4, 0)
	local radius = math.min(10, 3 + #players)
	for i, player in players do
		local angle = (i - 1) / math.max(#players, 1) * math.pi * 2
		local pos = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		moveTo(player, pos, center)
	end
end

function Studios.leave(players: { Player })
	for i, player in players do
		if player.Parent then
			local angle = (i - 1) / math.max(#players, 1) * math.pi * 2
			moveTo(player, RETURN_POSITION + Vector3.new(math.cos(angle) * 6, 0, math.sin(angle) * 6))
		end
	end
end

-- If someone respawns mid-match, put them back in their studio.
function Studios.watchRespawns(studio: Studio, players: { Player }): { RBXScriptConnection }
	local conns = {}
	for _, player in players do
		table.insert(conns, player.CharacterAdded:Connect(function()
			task.wait(0.3)
			if studio.inUse then
				moveTo(player, studio.floor.Position + Vector3.new(0, 4, 0))
			end
		end))
	end
	return conns
end

export type Studio = Studio
return Studios
