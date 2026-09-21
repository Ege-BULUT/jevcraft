-- Craft an iron pickaxe (then sword) from iron ingots.
local U, A = jev.u, jev.a

jev.register_skill({
	id = "craft_iron_tools", label = "⚒ Craft iron tools", timeout = 45,
	offer = function(p, x)
		local iron = x.n("mcl_core:iron_ingot")
		if x.pick >= 4 and x.sword >= 4 then
			return nil
		end
		local want = x.pick < 4 and "pickaxe (3 ingots + 2 sticks)" or "sword (2 ingots + 1 stick)"
		local need = x.pick < 4 and 3 or 2
		if iron < need then
			local raw = x.n("mcl_raw_ores:raw_iron")
			return {ok = false, prio = x.pick >= 2 and 50 or 5, detail = string.format("iron %s needs %d iron ingots (have %d ingots, %d raw iron to smelt)",
				want, need, iron, raw)}
		end
		return {ok = true, prio = x.pick < 4 and 82 or 55, detail = "craft iron " .. want .. "; you have " .. iron .. " ingots"}
	end,
	run = function(p)
		local tpos, why = A.ensure_table(p)
		if not tpos then
			return false, why
		end
		A.approach(p, tpos, 3.5)
		local made = {}
		for _, t in ipairs({{"pick", 3, 2}, {"sword", 2, 1}}) do
			if U.tool_tier(p, t[1]) < 4 and U.count(p, "mcl_core:iron_ingot") >= t[2] then
				if U.count(p, "mcl_core:stick") < t[3] then
					A.craft(p, "mcl_core:stick")
				end
				if A.craft(p, "mcl_tools:" .. t[1] .. "_iron") then
					made[#made + 1] = "iron " .. t[1]
				end
			end
		end
		return #made > 0, #made > 0 and ("crafted " .. table.concat(made, ", ")) or "could not craft (sticks?)"
	end,
})
