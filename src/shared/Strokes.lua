--!strict
--[[
	Stroke format (shared by client renderer and server validator):
	{
		t = "p" | "r" | "c" | "bg",  -- path, rectangle, circle, background fill (default "p")
		c = {r, g, b},               -- 0..1 floats
		w = number,                  -- outline width in canvas pixels, relative to a 1000px canvas
		a = number?,                 -- opacity 0.05..1 (default 1)
		s = boolean?,                -- paths only: soft edge (airbrush)
		f = boolean?,                -- shapes only: filled instead of outlined
		p = { x1, y1, x2, y2, ... }  -- normalized 0..1 coordinates, flat array
		                             -- paths: polyline; shapes: two opposite corners; bg: unused
	}
]]
local Config = require(script.Parent.Config)

local Strokes = {}

export type Stroke = { t: string?, c: { number }, w: number, a: number?, s: boolean?, f: boolean?, p: { number } }

local KINDS = { p = true, r = true, c = true, bg = true }

local function clamp01(n: number): number
	if n ~= n then return 0 end -- NaN
	return math.clamp(n, 0, 1)
end

-- Sanitize one stroke, or nil if it's garbage.
function Strokes.sanitizeOne(s: any): Stroke?
	if typeof(s) ~= "table" or typeof(s.c) ~= "table" then
		return nil
	end
	local kind = if typeof(s.t) == "string" and KINDS[s.t] then s.t else "p"
	local color = {
		clamp01(tonumber(s.c[1]) or 0),
		clamp01(tonumber(s.c[2]) or 0),
		clamp01(tonumber(s.c[3]) or 0),
	}
	local width = math.clamp(tonumber(s.w) or 6, Config.MIN_BRUSH, Config.MAX_BRUSH)
	local alpha = math.clamp(tonumber(s.a) or 1, 0.05, 1)
	local soft = s.s == true
	local points: { number } = {}
	if typeof(s.p) == "table" then
		local maxNums = if kind == "p" then Config.MAX_POINTS_PER_STROKE * 2 else 4
		for j = 1, math.min(#s.p, maxNums) do
			points[j] = clamp01(tonumber(s.p[j]) or 0)
		end
	end
	if #points % 2 == 1 then
		points[#points] = nil
	end
	if kind == "bg" then
		return { t = "bg", c = color, w = width, a = alpha, p = {} }
	end
	if kind ~= "p" and #points ~= 4 then
		return nil
	end
	if #points < 2 then
		return nil
	end
	return { t = kind, c = color, w = width, a = alpha, s = if kind == "p" and soft then true else nil, f = if kind ~= "p" then s.f == true else nil, p = points }
end

-- Returns a sanitized copy of a stroke list, or nil if it's garbage.
function Strokes.sanitize(raw: any): { Stroke }?
	if typeof(raw) ~= "table" then
		return nil
	end
	local out: { Stroke } = {}
	for i = 1, math.min(#raw, Config.MAX_STROKES_PER_PANEL) do
		local s = Strokes.sanitizeOne(raw[i])
		if s then table.insert(out, s) end
	end
	return out
end

function Strokes.copy(s: Stroke): Stroke
	return { t = s.t, c = table.clone(s.c), w = s.w, a = s.a, s = s.s, f = s.f, p = table.clone(s.p) }
end

-- Geometry helpers used by the client's transform tool.
function Strokes.bounds(s: Stroke): (number, number, number, number)
	local minX, minY, maxX, maxY = 1, 1, 0, 0
	for i = 1, #s.p - 1, 2 do
		minX = math.min(minX, s.p[i]); maxX = math.max(maxX, s.p[i])
		minY = math.min(minY, s.p[i + 1]); maxY = math.max(maxY, s.p[i + 1])
	end
	return minX, minY, maxX, maxY
end

function Strokes.translate(s: Stroke, dx: number, dy: number)
	for i = 1, #s.p - 1, 2 do
		s.p[i] = clamp01(s.p[i] + dx)
		s.p[i + 1] = clamp01(s.p[i + 1] + dy)
	end
end

function Strokes.scaleAbout(s: Stroke, cx: number, cy: number, k: number)
	for i = 1, #s.p - 1, 2 do
		s.p[i] = clamp01(cx + (s.p[i] - cx) * k)
		s.p[i + 1] = clamp01(cy + (s.p[i + 1] - cy) * k)
	end
	s.w = math.clamp(s.w * k, Config.MIN_BRUSH, Config.MAX_BRUSH)
end

function Strokes.mirrorX(s: Stroke): Stroke
	local copy = Strokes.copy(s)
	for i = 1, #copy.p - 1, 2 do
		copy.p[i] = 1 - copy.p[i]
	end
	return copy
end

-- Shapes are axis-aligned; rotating or warping them turns them into paths.
-- Fill is lost in the process (a Frame can't be an arbitrary polygon).
function Strokes.toPath(s: Stroke): Stroke
	if s.t ~= "r" and s.t ~= "c" then return s end
	local minX, minY, maxX, maxY = Strokes.bounds(s)
	local pts = {}
	if s.t == "r" then
		pts = { minX, minY, maxX, minY, maxX, maxY, minX, maxY, minX, minY }
	else
		local cx, cy = (minX + maxX) / 2, (minY + maxY) / 2
		local rx, ry = (maxX - minX) / 2, (maxY - minY) / 2
		for i = 0, 32 do
			local a = i / 32 * math.pi * 2
			table.insert(pts, cx + math.cos(a) * rx)
			table.insert(pts, cy + math.sin(a) * ry)
		end
	end
	return { t = "p", c = table.clone(s.c), w = s.w, a = s.a, p = pts }
end

function Strokes.rotateAbout(s: Stroke, cx: number, cy: number, radians: number): Stroke
	local out = Strokes.toPath(s)
	local cosA, sinA = math.cos(radians), math.sin(radians)
	for i = 1, #out.p - 1, 2 do
		local dx, dy = out.p[i] - cx, out.p[i + 1] - cy
		out.p[i] = clamp01(cx + dx * cosA - dy * sinA)
		out.p[i + 1] = clamp01(cy + dx * sinA + dy * cosA)
	end
	return out
end

-- Non-uniform scale about a point (used by edge handles).
function Strokes.scaleXY(s: Stroke, cx: number, cy: number, kx: number, ky: number)
	for i = 1, #s.p - 1, 2 do
		s.p[i] = clamp01(cx + (s.p[i] - cx) * kx)
		s.p[i + 1] = clamp01(cy + (s.p[i + 1] - cy) * ky)
	end
	s.w = math.clamp(s.w * math.sqrt(math.abs(kx * ky)), Config.MIN_BRUSH, Config.MAX_BRUSH)
end

function Strokes.mirrorY(s: Stroke, cy: number)
	for i = 2, #s.p, 2 do
		s.p[i] = clamp01(2 * cy - s.p[i])
	end
end

-- Bilinear warp: map the stroke's bounding box corners (TL, TR, BR, BL) onto
-- four new corners. Each point is expressed in box-relative (u, v) and
-- re-projected into the warped quad.
function Strokes.warp(s: Stroke, box: { number }, quad: { number }): Stroke
	local out = Strokes.toPath(s)
	local minX, minY, maxX, maxY = box[1], box[2], box[3], box[4]
	local w, h = math.max(maxX - minX, 1e-6), math.max(maxY - minY, 1e-6)
	for i = 1, #out.p - 1, 2 do
		local u = (out.p[i] - minX) / w
		local v = (out.p[i + 1] - minY) / h
		-- quad = {tlx,tly, trx,try, brx,bry, blx,bly}
		local topX = quad[1] + (quad[3] - quad[1]) * u
		local topY = quad[2] + (quad[4] - quad[2]) * u
		local botX = quad[7] + (quad[5] - quad[7]) * u
		local botY = quad[8] + (quad[6] - quad[8]) * u
		out.p[i] = clamp01(topX + (botX - topX) * v)
		out.p[i + 1] = clamp01(topY + (botY - topY) * v)
	end
	return out
end

-- Ray-casting point-in-polygon; poly is a flat {x1,y1,x2,y2,...}.
function Strokes.pointInPolygon(poly: { number }, x: number, y: number): boolean
	local inside = false
	local n = #poly // 2
	local j = n
	for i = 1, n do
		local xi, yi = poly[i * 2 - 1], poly[i * 2]
		local xj, yj = poly[j * 2 - 1], poly[j * 2]
		if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / ((yj - yi) + 1e-9) + xi) then
			inside = not inside
		end
		j = i
	end
	return inside
end

-- True if most of the stroke's points fall inside the lasso polygon.
function Strokes.insideLasso(s: Stroke, poly: { number }): boolean
	if s.t == "bg" then return false end
	local pts = s.p
	if s.t == "r" or s.t == "c" then
		local minX, minY, maxX, maxY = Strokes.bounds(s)
		pts = { minX, minY, maxX, minY, maxX, maxY, minX, maxY, (minX + maxX) / 2, (minY + maxY) / 2 }
	end
	local hits, total = 0, 0
	for i = 1, #pts - 1, 2 do
		total += 1
		if Strokes.pointInPolygon(poly, pts[i], pts[i + 1]) then hits += 1 end
	end
	return total > 0 and hits / total >= 0.6
end

-- Distance from a point to the stroke (for picking with the transform tool).
function Strokes.distanceTo(s: Stroke, x: number, y: number): number
	if s.t == "bg" then return math.huge end
	if s.t == "r" or s.t == "c" then
		local minX, minY, maxX, maxY = Strokes.bounds(s)
		if x >= minX and x <= maxX and y >= minY and y <= maxY then return 0 end
		local dx = math.max(minX - x, 0, x - maxX)
		local dy = math.max(minY - y, 0, y - maxY)
		return math.sqrt(dx * dx + dy * dy)
	end
	local best = math.huge
	for i = 1, #s.p - 1, 2 do
		local dx, dy = s.p[i] - x, s.p[i + 1] - y
		best = math.min(best, dx * dx + dy * dy)
	end
	return math.sqrt(best)
end

function Strokes.toColor3(c: { number }): Color3
	return Color3.new(c[1], c[2], c[3])
end

function Strokes.fromColor3(c: Color3): { number }
	return { c.R, c.G, c.B }
end

return Strokes
