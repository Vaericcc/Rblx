--!strict
-- Side panel that shows a project's premise + cast (+ optional free prompt).
local Make = require(script.Parent.Make)
local Theme = require(script.Parent.Theme)

local StoryInfo = {}

function StoryInfo.build(parent: Instance, opts: { premise: any?, cast: any?, roles: any?, prompt: string?, ownerName: string?, lines: any? }): Frame
	local card = Make.card({
		Size = UDim2.new(1, 0, 1, 0),
		Make.list(nil, 8),
		Parent = parent,
	})
	if opts.ownerName then
		Make.label("Story by " .. opts.ownerName, 13, { TextColor3 = Theme.textDim, Parent = card })
	end
	if opts.prompt then
		Make.heading("Your prompt", 14, { TextColor3 = Theme.accent, Parent = card })
		Make.label(opts.prompt, 18, { Size = UDim2.new(1, 0, 0, 90), Parent = card })
	end
	if opts.premise then
		Make.heading(opts.premise.title ~= "" and opts.premise.title or "Untitled", 22, { Parent = card })
		if opts.premise.logline and opts.premise.logline ~= "" then
			Make.label(opts.premise.logline, 15, { TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 60), Parent = card })
		end
	end
	if opts.cast and #opts.cast > 0 then
		Make.heading("Cast", 14, { TextColor3 = Theme.accent, Parent = card })
		for _, c in opts.cast do
			local role = opts.roles and opts.roles[c.name]
			local who = if role then ("  <font color=\"#ffc43d\">🎤 %s</font>"):format(role.name) else ""
			Make.label(("<b>%s</b>  <font color=\"#aaaabe\">%s</font>%s"):format(c.name, c.trait or "", who), 15, {
				RichText = true,
				Size = UDim2.new(1, 0, 0, 22),
				Parent = card,
			})
		end
	end
	if opts.lines and #opts.lines > 0 then
		Make.heading("Script", 14, { TextColor3 = Theme.accent, Parent = card })
		local byPanel: { [number]: { any } } = {}
		for _, l in opts.lines do
			byPanel[l.panel] = byPanel[l.panel] or {}
			table.insert(byPanel[l.panel], l)
		end
		local panels = {}
		for p in byPanel do table.insert(panels, p) end
		table.sort(panels)
		for _, p in panels do
			Make.label(("Panel %d"):format(p), 13, { TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 18), Parent = card })
			for _, l in byPanel[p] do
				Make.label(("<b>%s:</b> %s"):format(l.character, l.text), 14, { RichText = true, Size = UDim2.new(1, 0, 0, 36), Parent = card })
			end
		end
	end
	return card
end

return StoryInfo
