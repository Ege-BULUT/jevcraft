-- Craft a wooden pickaxe (and sword when wood allows) at a crafting table.
local U, A = jev.u, jev.a

jev.register_skill({
	id = "craft_wooden_tools", label = "⛏ Craft wooden tools", timeout = 45,
	offer = function(p, x)
		if x.pick >= 1 then
			return {ok = false, prio = 0, detail = "you already have a pickaxe"}
		end
		local need = 3 + (x.sticks >= 2 and 0 or 2) + ((x.table or x.n("mcl_crafting_table:crafting_table") > 0) and 0 or 4)
		local have = x.planks + x.logs * 4
		if have < need then
			return {ok = false, prio = 60, detail = string.format("need %d planks worth of wood incl. sticks/table (have %d planks, %d logs)",
				need, x.planks, x.logs)}
		end
		return {ok = true, prio = 77, detail = "craft a wooden pickaxe (3 planks + 2 sticks) and a wooden sword if wood is left; " ..
			(x.table and ("crafting table " .. U.where(x.pos, x.table)) or "will place a crafting table")}
	end,
	run = function(p)
		-- Enough planks for table (4, if missing) + pickaxe (3) + sticks (2) + sword (2).
		for _ = 1, 4 do
			if U.count(p, "group:wood") >= 11 then
				break
			end
			local log = U.slot(p, "group:tree")
			if not log then
				break
			end
			local name = p:get_inventory():get_stack("main", log):get_name()
			local r = minetest.get_craft_result({method = "normal", width = 1, items = {name}})
			if not A.craft(p, r.item:get_name()) then
				break
			end
		end
		local tpos, why = A.ensure_table(p)
		if not tpos then
			return false, why
		end
		A.approach(p, tpos, 3.5)
		if U.count(p, "mcl_core:stick") < 3 then
			A.craft(p, "mcl_core:stick")
		end
		local ok, err = A.craft(p, "mcl_tools:pick_wood")
		if not ok then
			return false, "pickaxe: " .. err
		end
		local extra = ""
		if U.count(p, "group:wood") >= 2 and A.craft(p, "mcl_tools:sword_wood") then
			extra = " and wooden sword"
		end
		return true, "crafted wooden pickaxe" .. extra
	end,
})
