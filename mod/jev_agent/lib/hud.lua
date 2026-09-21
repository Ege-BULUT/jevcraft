-- Top-left narration for viewers: current skill + status, and the last chosen option.
local huds = {}

local function add(p, y, size, color)
	return p:hud_add({
		type = "text",
		position = {x = 0, y = 0}, offset = {x = 14, y = y}, alignment = {x = 1, y = 1},
		text = "", number = color, size = {x = size, y = size}, style = 1, z_index = 100,
	})
end

function jev.hud_init(p)
	huds[p:get_player_name()] = {
		line1 = add(p, 12, 1.4, 0xFFFFFF),
		line2 = add(p, 44, 1, 0xFFE070),
		chosen = "",
	}
end

-- title: skill label; status: one-line detail; chosen: label of the option picked last.
function jev.hud_set(p, title, status, chosen)
	local h = p and huds[p:get_player_name()]
	if not h then
		return
	end
	if chosen then
		h.chosen = chosen
	end
	local text = title .. " - " .. (status or "")
	if #text > 90 then
		text = text:sub(1, 87) .. "..."
	end
	p:hud_change(h.line1, "text", text)
	p:hud_change(h.line2, "text", h.chosen ~= "" and ("Chose: " .. h.chosen) or "")
end
