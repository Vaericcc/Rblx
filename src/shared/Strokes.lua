--!strict
--[[
	Stroke format (shared by client renderer and server validator):
	{
		c = {r, g, b},      -- 0..1 floats
		w = number,         -- brush width in canvas pixels, relative to a 1000px canvas
		p = { x1, y1, x2, y2, ... }  -- normalized 0..1 coordinates, flat array
	}
]]
local Config = require(script.Parent.Config)

local Strokes = {}

export type Stroke = { c: { number }, w: number, p: { number } }

local function clamp01(n: number): number
	if n ~= n then return 0 end -- NaN
	return math.clamp(n, 0, 1)
end

-- Returns a sanitized copy of a stroke list, or nil if it's garbage.
function Strokes.sanitize(raw: any): { Stroke }?
	if typeof(raw) ~= "table" then
		return nil
	end
	local out: { Stroke } = {}
	for i = 1, math.min(#raw, Config.MAX_STROKES_PER_PANEL) do
		local s = raw[i]
		if typeof(s) ~= "table" or typeof(s.p) ~= "table" or typeof(s.c) ~= "table" then
			continue
		end
		local color = {
			clamp01(tonumber(s.c[1]) or 0),
			clamp01(tonumber(s.c[2]) or 0),
			clamp01(tonumber(s.c[3]) or 0),
		}
		local width = math.clamp(tonumber(s.w) or 6, Config.MIN_BRUSH, Config.MAX_BRUSH)
		local points: { number } = {}
		local maxNums = Config.MAX_POINTS_PER_STROKE * 2
		for j = 1, math.min(#s.p, maxNums) do
			points[j] = clamp01(tonumber(s.p[j]) or 0)
		end
		if #points % 2 == 1 then
			points[#points] = nil
		end
		if #points >= 2 then
			table.insert(out, { c = color, w = width, p = points })
		end
	end
	return out
end

function Strokes.toColor3(c: { number }): Color3
	return Color3.new(c[1], c[2], c[3])
end

function Strokes.fromColor3(c: Color3): { number }
	return { c.R, c.G, c.B }
end

return Strokes
