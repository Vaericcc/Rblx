--!strict
--[[
	Claim phase: every story's cast is listed; tap a character to claim it.
	Claims are live (server broadcasts ClaimState), so you can see what's taken.
	Submit = "I'm done"; unclaimed roles are handed out automatically.
]]
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local UI = script.Parent.Parent.UI
local Make = require(UI.Make)
local Theme = require(UI.Theme)
local Layout = require(UI.Layout)
local Responsive = require(UI.Responsive)

local Claim = {}

function Claim.show(container: Frame, data: any, ctx: any)
	local me = Players.LocalPlayer.UserId
	local root = Layout.form(container)
	local roles = data.roles or {}
	local chipsByKey: { [string]: TextButton } = {}
	local solo = #data.projects == 1 and (data.projects[1].ownerId == me or data.shared == true)

	Make.label(
		if data.shared
			then ("%s: tap up to 2 characters to voice in your team's comic."):format(data.teamName or "Your team")
			elseif solo then "You're testing alone, so you voice your own cast. Tap the characters you want."
			else ("Claim up to %d characters per story. You can't voice your own story."):format(data.maxRoles or 2),
		14, { TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = root })

	local function paint()
		for key, chip in chipsByKey do
			local projectIndex, character = key:match("^(%d+)|(.*)$")
			local holder = roles[projectIndex] and roles[projectIndex][character]
			if holder and holder.userId == me then
				chip.BackgroundColor3 = Theme.accent
				chip.TextColor3 = Theme.bg
				chip.Text = ("%s  ·  you"):format(character)
			elseif holder then
				chip.BackgroundColor3 = Theme.panel
				chip.TextColor3 = Theme.textDim
				chip.Text = ("%s  ·  %s"):format(character, holder.name)
			else
				chip.BackgroundColor3 = Theme.panelAlt
				chip.TextColor3 = Theme.text
				chip.Text = ("%s  ·  open"):format(character)
			end
		end
	end

	for _, p in data.projects do
		local mine = p.ownerId == me and not data.shared
		local card = Make.card({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Make.list(nil, 8), Parent = root })
		Make.heading(("%s  <font color=\"#aaaabe\" size=\"13\">by %s%s</font>"):format(p.title, p.ownerName, if mine and not solo then " (yours)" else ""), 18, {
			RichText = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = card,
		})
		if p.logline ~= "" then
			Make.label(p.logline, 13, { TextColor3 = Theme.textDim, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = card })
		end
		for _, c in p.cast do
			local row = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, Responsive.touchSize()), Parent = card })
			local chip = Make.button(c.name, Theme.panelAlt, function()
				if mine and not solo then return end
				Net.remote:FireServer(Net.C2S.Claim, { projectIndex = p.index, character = c.name })
			end, { Size = UDim2.new(0.5, -6, 1, 0), TextSize = 14, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 12)
			pad.Parent = chip
			Make.label(c.trait or "", 13, {
				TextColor3 = Theme.textDim, Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(0.5, 6, 0, 0),
				TextYAlignment = Enum.TextYAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
			})
			chipsByKey[("%d|%s"):format(p.index, c.name)] = chip
		end
	end
	paint()

	return {
		collect = function() return { done = true } end,
		onClaimState = function(state: any)
			roles = state.roles or {}
			paint()
		end,
		destroy = function() container:ClearAllChildren() end,
	}
end

return Claim
