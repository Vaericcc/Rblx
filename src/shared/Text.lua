--!strict
-- Text sanitation helpers shared by client (for live limits) and server (for trust).
local Text = {}

function Text.clean(value: any, maxLen: number): string
	if typeof(value) ~= "string" then
		return ""
	end
	-- collapse whitespace, strip control chars
	local s = value:gsub("[%c]", " "):gsub("%s+", " ")
	s = s:match("^%s*(.-)%s*$") or ""
	if #s > maxLen then
		s = s:sub(1, maxLen)
	end
	return s
end

function Text.orDefault(value: string, default: string): string
	if value == "" then
		return default
	end
	return value
end

return Text
