--!strict
--[[
	One place that answers "what kind of screen is this?".
	compact  = phone-sized: stack panels vertically, bigger touch targets
	regular  = tablet landscape / desktop: side-by-side panels

	Always reads workspace.CurrentCamera live: the camera is replaced when the
	character spawns, and a stale reference reports a tiny viewport.
]]
local UserInputService = game:GetService("UserInputService")

local Responsive = {}

function Responsive.viewport(): Vector2
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

-- True once the camera reports a believable size.
function Responsive.ready(): boolean
	local v = Responsive.viewport()
	return v.X > 200 and v.Y > 200
end

function Responsive.waitUntilReady()
	while not Responsive.ready() do
		task.wait(0.1)
	end
end

function Responsive.isCompact(): boolean
	local v = Responsive.viewport()
	return v.X < 820 or v.Y < 480
end

function Responsive.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- UI scale: layouts are designed around 1280x720. Big monitors scale up,
-- small tablets scale down, phones use the compact layout at native size.
function Responsive.scale(): number
	if Responsive.isCompact() then
		return 1
	end
	local v = Responsive.viewport()
	return math.clamp(math.min(v.X / 1280, v.Y / 720), 0.8, 1.8)
end

-- Widest a content column should get (in unscaled pixels) so forms don't
-- stretch across ultrawide screens.
Responsive.MAX_CONTENT_WIDTH = 1240

-- Minimum comfortable tap target height.
function Responsive.touchSize(): number
	return if Responsive.isTouch() then 48 else 40
end

-- Fires when the viewport changes. Re-resolved each time so camera swaps are safe.
function Responsive.onChanged(callback: () -> ()): RBXScriptConnection
	local conn: RBXScriptConnection? = nil
	local function bind()
		if conn then conn:Disconnect() end
		local camera = workspace.CurrentCamera
		if camera then
			conn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(callback)
		end
	end
	bind()
	local swap = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bind()
		callback()
	end)
	return swap
end

return Responsive
