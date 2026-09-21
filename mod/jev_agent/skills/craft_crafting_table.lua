-- Craft a crafting table and place it next to the player.
local U, A = jev.u, jev.a

jev.register_skill({
	id = "craft_crafting_table", label = "🧰 Craft crafting table", timeout = 30,
	offer = function(p, x)
		local carried = x.n("mcl_crafting_table:crafting_table") > 0
		if x.table then
			return {ok = false, prio = 0, detail = "a crafting table already stands " .. U.where(x.pos, x.table)}
		end
		if carried then
			return {ok = true, prio = 60, detail = "place the crafting table you carry next to you"}
		end
		if x.planks < 4 then
			return {ok = false, prio = 40, detail = "need 4 planks (have " .. x.planks .. ", logs " .. x.logs .. ")"}
		end
		return {ok = true, prio = 78, detail = "4 planks -> crafting table, placed next to you (needed for tools); none within 16 m"}
	end,
	run = function(p)
		local pos, why = A.ensure_table(p)
		if not pos then
			return false, why
		end
		return true, "crafting table at " .. U.pos_text(pos)
	end,
})
