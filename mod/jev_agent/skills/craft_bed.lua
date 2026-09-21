-- Craft a bed from 3 wool of one colour + 3 planks.
local U, A = jev.u, jev.a

local function wool_color(p)
	for name, c in pairs(U.counts(p)) do
		if c >= 3 and minetest.get_item_group(name, "wool") > 0 then
			local color = name:match("^mcl_wool:(.+)$")
			if color and minetest.registered_items["mcl_beds:bed_" .. color .. "_bottom"] then
				return color
			end
		end
	end
end

jev.register_skill({
	id = "craft_bed", label = "🛏 Craft bed", timeout = 40,
	offer = function(p, x)
		if x.bed or x.n("group:bed") > 0 then
			return nil
		end
		local color = wool_color(p)
		local wool = x.n("group:wool")
		if not color then
			return {ok = false, prio = wool > 0 and 42 or 20, detail = "need 3 wool of one colour (have " .. wool .. ")" ..
				(x.sheep and ("; nearest sheep " .. U.where(x.pos, x.sheep.pos)) or "; no sheep within 32 m")}
		end
		if x.planks < 3 then
			return {ok = false, prio = 30, detail = "have the wool but need 3 planks (have " .. x.planks .. ")"}
		end
		return {ok = true, prio = 64, detail = "craft a " .. color .. " bed (3 wool + 3 planks); lets you sleep through nights and sets your respawn"}
	end,
	run = function(p)
		local color = wool_color(p)
		if not color then
			return false, "not enough wool"
		end
		local tpos, why = A.ensure_table(p)
		if not tpos then
			return false, why
		end
		A.approach(p, tpos, 3.5)
		local ok, err = A.craft(p, "mcl_beds:bed_" .. color .. "_bottom")
		return ok, ok and ("crafted a " .. color .. " bed") or err
	end,
})
