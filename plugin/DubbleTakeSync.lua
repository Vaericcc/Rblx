--[[
	Dubble Take Sync - Roblox Studio plugin

	Pulls this repository straight from GitHub and installs it into the open place,
	following the same mapping as default.project.json (Rojo conventions):

		*.server.lua  -> Script
		*.client.lua  -> LocalScript
		*.lua         -> ModuleScript
		directories   -> Folder
		$properties   -> set on the created instance (Vector3 / Color3 / Enum handled)

	Install: Studio -> Plugins tab -> Plugins Folder, drop this file in, restart Studio.
	Or: paste into a Script in Studio, right click -> Save as Local Plugin.

	Private repos need a GitHub personal access token with "Contents: read".
]]

local HttpService = game:GetService("HttpService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")

local DEFAULT_REPO = "Vaericcc/Rblx"
local DEFAULT_BRANCH = "claude/lucid-bardeen-xi7ati"
local PROJECT_FILE = "default.project.json"

----------------------------------------------------------------------------
-- GitHub

local function request(url: string, token: string?, accept: string?): string
	local headers: { [string]: string } = {
		["User-Agent"] = "DubbleTakeSync",
		["Accept"] = accept or "application/vnd.github+json",
	}
	if token and token ~= "" then
		headers["Authorization"] = "Bearer " .. token
	end
	local response = HttpService:RequestAsync({ Url = url, Method = "GET", Headers = headers })
	if not response.Success then
		local hint = ""
		if response.StatusCode == 404 then
			hint = " (not found: check owner/repo and branch; private repos need a token)"
		elseif response.StatusCode == 401 or response.StatusCode == 403 then
			hint = " (unauthorized: token missing, expired, or lacks Contents read access)"
		end
		error(("GitHub %d for %s%s"):format(response.StatusCode, url, hint))
	end
	return response.Body
end

local function fetchRaw(repo: string, branch: string, path: string, token: string?): string
	-- raw.githubusercontent.com works for private repos when a token is sent.
	local url = ("https://raw.githubusercontent.com/%s/%s/%s"):format(repo, branch, path)
	return request(url, token, "application/vnd.github.raw")
end

local function fetchTree(repo: string, branch: string, token: string?): { any }
	local url = ("https://api.github.com/repos/%s/git/trees/%s?recursive=1"):format(repo, branch)
	local data = HttpService:JSONDecode(request(url, token))
	if data.truncated then
		warn("[Dubble Take Sync] tree was truncated by GitHub; some files may be missing")
	end
	return data.tree or {}
end

----------------------------------------------------------------------------
-- Instance building

local function classForFile(fileName: string): (string?, string?)
	local name = fileName:match("^(.*)%.server%.luau?$")
	if name then return "Script", name end
	name = fileName:match("^(.*)%.client%.luau?$")
	if name then return "LocalScript", name end
	name = fileName:match("^(.*)%.luau?$")
	if name then return "ModuleScript", name end
	return nil, nil
end

-- Convert a JSON property value to a Roblox value, based on the property name.
local VECTOR_PROPS = { Size = true, Position = true, Orientation = true, Velocity = true }
local COLOR_PROPS = { Color = true, Color3 = true }

local function convertProperty(name: string, value: any): any
	if typeof(value) == "table" and #value == 3 then
		if VECTOR_PROPS[name] then
			return Vector3.new(value[1], value[2], value[3])
		elseif COLOR_PROPS[name] then
			return Color3.new(value[1], value[2], value[3])
		end
	end
	if typeof(value) == "string" then
		local enumType = (Enum :: any)[name]
		if enumType then
			local ok, item = pcall(function() return enumType[value] end)
			if ok then return item end
		end
	end
	return value
end

local function applyProperties(instance: Instance, props: { [string]: any }?)
	if not props then return end
	for name, value in props do
		local ok, err = pcall(function()
			(instance :: any)[name] = convertProperty(name, value)
		end)
		if not ok then
			warn(("[Dubble Take Sync] could not set %s.%s: %s"):format(instance.Name, name, tostring(err)))
		end
	end
end

local function replaceChild(parent: Instance, name: string, className: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then existing:Destroy() end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

-- Mirror one source directory (e.g. "src/shared") into `parent`.
local function syncDirectory(parent: Instance, dirPath: string, files: { [string]: string }, log: (string) -> ())
	local count = 0
	for path, source in files do
		if path:sub(1, #dirPath + 1) ~= dirPath .. "/" then continue end
		local relative = path:sub(#dirPath + 2)
		local segments = relative:split("/")
		local fileName = table.remove(segments) :: string
		local className, scriptName = classForFile(fileName)
		if not className or not scriptName then continue end

		-- Walk/create folders for intermediate segments
		local container = parent
		for _, segment in segments do
			local folder = container:FindFirstChild(segment)
			if not folder then
				folder = Instance.new("Folder")
				folder.Name = segment
				folder.Parent = container
			end
			container = folder
		end
		local script = replaceChild(container, scriptName, className) :: any
		script.Source = source
		count += 1
	end
	log(("  %s -> %s (%d scripts)"):format(dirPath, parent:GetFullName(), count))
end

-- Recursively realize a node of the project tree under `parent`.
local function buildNode(parent: Instance?, name: string, node: { [string]: any }, files: { [string]: string }, log: (string) -> ())
	local instance: Instance
	if parent == nil then
		instance = game -- DataModel root
	elseif parent == game then
		instance = game:GetService(node["$className"] or name)
	else
		local className = node["$className"] or "Folder"
		instance = replaceChild(parent, name, className)
	end

	if instance ~= game then
		applyProperties(instance, node["$properties"])
	end

	if node["$path"] then
		-- Clear previous sync output for this folder, then mirror the directory.
		if instance ~= game and instance.Parent ~= game then
			instance:ClearAllChildren()
		end
		syncDirectory(instance, node["$path"], files, log)
	end

	for key, child in node do
		if typeof(key) == "string" and key:sub(1, 1) ~= "$" and typeof(child) == "table" then
			buildNode(instance, key, child, files, log)
		end
	end
end

----------------------------------------------------------------------------
-- Sync

local function sync(repo: string, branch: string, token: string?, log: (string) -> ())
	log(("Fetching %s@%s ..."):format(repo, branch))
	local project = HttpService:JSONDecode(fetchRaw(repo, branch, PROJECT_FILE, token))

	-- Collect every directory the project references so we only download what's used.
	local wanted: { string } = {}
	local function collectPaths(node: { [string]: any })
		if node["$path"] then table.insert(wanted, node["$path"]) end
		for key, child in node do
			if typeof(key) == "string" and key:sub(1, 1) ~= "$" and typeof(child) == "table" then
				collectPaths(child)
			end
		end
	end
	collectPaths(project.tree)

	local tree = fetchTree(repo, branch, token)
	local files: { [string]: string } = {}
	local total = 0
	for _, entry in tree do
		if entry.type ~= "blob" then continue end
		for _, dir in wanted do
			if entry.path:sub(1, #dir + 1) == dir .. "/" and classForFile(entry.path:match("[^/]+$")) then
				total += 1
				break
			end
		end
	end
	log(("Downloading %d scripts ..."):format(total))
	local done = 0
	for _, entry in tree do
		if entry.type ~= "blob" then continue end
		for _, dir in wanted do
			if entry.path:sub(1, #dir + 1) == dir .. "/" and classForFile(entry.path:match("[^/]+$")) then
				files[entry.path] = fetchRaw(repo, branch, entry.path, token)
				done += 1
				if done % 5 == 0 then log(("  %d/%d"):format(done, total)) end
				break
			end
		end
	end

	local recording = ChangeHistoryService:TryBeginRecording("Dubble Take Sync")
	buildNode(nil, "DataModel", project.tree, files, log)
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	log(("Done. %s installed into this place. Press Play to test."):format(project.name or repo))
end

----------------------------------------------------------------------------
-- UI

local toolbar = plugin:CreateToolbar("DubbleTake")
local button = toolbar:CreateButton("Sync from GitHub", "Pull the latest Dubble Take code from GitHub into this place", "rbxassetid://4458901886")

local widget = plugin:CreateDockWidgetPluginGui("DubbleTakeSync", DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float, false, false, 360, 330, 320, 300
))
widget.Title = "Dubble Take Sync"

local root = Instance.new("Frame")
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.fromRGB(36, 36, 48)
root.BorderSizePixel = 0
root.Parent = widget

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 12)
padding.PaddingBottom = UDim.new(0, 12)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.Parent = root

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = root

local function label(text: string, order: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Text = text
	l.Font = Enum.Font.Gotham
	l.TextSize = 13
	l.TextColor3 = Color3.fromRGB(170, 170, 190)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 16)
	l.LayoutOrder = order
	l.Parent = root
	return l
end

local function input(placeholder: string, value: string, order: number): TextBox
	local box = Instance.new("TextBox")
	box.PlaceholderText = placeholder
	box.Text = value
	box.Font = Enum.Font.Gotham
	box.TextSize = 14
	box.TextColor3 = Color3.fromRGB(245, 245, 250)
	box.PlaceholderColor3 = Color3.fromRGB(120, 120, 140)
	box.BackgroundColor3 = Color3.fromRGB(46, 46, 62)
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Size = UDim2.new(1, 0, 0, 30)
	box.LayoutOrder = order
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = box
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = box
	box.Parent = root
	return box
end

label("Repository (owner/repo)", 1)
local repoBox = input(DEFAULT_REPO, plugin:GetSetting("repo") or DEFAULT_REPO, 2)
label("Branch", 3)
local branchBox = input(DEFAULT_BRANCH, plugin:GetSetting("branch") or DEFAULT_BRANCH, 4)
label("GitHub token (only needed for private repos)", 5)
local tokenBox = input("ghp_...", plugin:GetSetting("token") or "", 6)
tokenBox.TextSize = 12

local syncButton = Instance.new("TextButton")
syncButton.Text = "Sync into this place"
syncButton.Font = Enum.Font.GothamBold
syncButton.TextSize = 15
syncButton.TextColor3 = Color3.fromRGB(24, 24, 32)
syncButton.BackgroundColor3 = Color3.fromRGB(255, 196, 61)
syncButton.BorderSizePixel = 0
syncButton.Size = UDim2.new(1, 0, 0, 36)
syncButton.LayoutOrder = 7
local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 8)
btnCorner.Parent = syncButton
syncButton.Parent = root

local status = Instance.new("TextLabel")
status.Text = "Ready."
status.Font = Enum.Font.Code
status.TextSize = 12
status.TextColor3 = Color3.fromRGB(245, 245, 250)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextWrapped = true
status.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
status.BorderSizePixel = 0
status.Size = UDim2.new(1, 0, 1, -230)
status.LayoutOrder = 8
local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 6)
statusCorner.Parent = status
local statusPad = Instance.new("UIPadding")
statusPad.PaddingTop = UDim.new(0, 6)
statusPad.PaddingLeft = UDim.new(0, 8)
statusPad.PaddingRight = UDim.new(0, 8)
statusPad.Parent = status
status.Parent = root

local lines: { string } = {}
local function log(line: string)
	table.insert(lines, line)
	while #lines > 10 do table.remove(lines, 1) end
	status.Text = table.concat(lines, "\n")
	print("[Dubble Take Sync] " .. line)
end

local busy = false
syncButton.Activated:Connect(function()
	if busy then return end
	busy = true
	lines = {}
	syncButton.Text = "Syncing..."
	syncButton.AutoButtonColor = false

	local repo = repoBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
	local branch = branchBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
	local token = tokenBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
	plugin:SetSetting("repo", repo)
	plugin:SetSetting("branch", branch)
	plugin:SetSetting("token", token)

	local ok, err = pcall(sync, repo, branch, token, log)
	if not ok then
		log("ERROR: " .. tostring(err))
		if tostring(err):find("Http requests are not enabled") then
			log("Enable HTTP: Game Settings -> Security -> Allow HTTP Requests.")
		end
	end
	syncButton.Text = "Sync into this place"
	syncButton.AutoButtonColor = true
	busy = false
end)

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
