-- Craft a furnace from 8 cobblestone and place it.
local U, A = jev.u, jev.a

jev.register_skill({
	id = "craft_furnace", label = "🔥 Craft furnace", timeout = 40,
	offer = function(p, x)
		if x.furnace then
			return {ok = false, prio = 0, detail = "a furnace already stands " .. U.where(x.pos, x.furnace)}
		end
		if x.n("mcl_furnaces:furnace") > 0 then
			return {ok = true, prio = 50, detail = "place the furnace you carry next to you"}
		end
		if x.cobble < 8 then
			return {ok = false, prio = x.pick >= 2 and 45 or 5, detail = "need 8 cobblestone (have " .. x.cobble .. ")"}
		end
		local raw = x.n("mcl_raw_ores:raw_iron")
		return {ok = true, prio = raw > 0 and 67 or (x.pick >= 2 and 50 or 20),
			detail = "8 cobblestone -> furnace, placed next to you; smelts raw iron (you have " .. raw .. ") and cooks meat"}
	end,
	run = function(p)
		local tpos, why = A.ensure_table(p)
		if not tpos then
			return false, why
		end
		A.approach(p, tpos, 3.5)
		local pos, err = A.ensure_furnace(p)
		if not pos then
			return false, err
		end
		return true, "furnace at " .. U.pos_text(pos)
	end,
})
