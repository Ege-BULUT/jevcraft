-- Craft stone pickaxe, sword and axe from cobblestone.
local U, A = jev.u, jev.a

local TOOLS = {{"pick", 3, 2}, {"sword", 2, 1}, {"axe", 3, 2}}

jev.register_skill({
	id = "craft_stone_tools", label = "🔨 Craft stone tools", timeout = 45,
	offer = function(p, x)
		local want = {}
		local cob = 0
		for _, t in ipairs(TOOLS) do
			if U.tool_tier(p, t[1]) < 2 then
				want[#want + 1] = t[1]
				cob = cob + t[2]
			end
		end
		if #want == 0 then
			return {ok = false, prio = 0, detail = "you already have stone-or-better pickaxe, sword and axe"}
		end
		local prio = x.pick < 2 and 76 or 45
		if x.cobble < 3 or (x.sticks < 2 and x.planks < 2) then
			return {ok = false, prio = x.pick < 2 and 58 or 10, detail = string.format(
				"need 3 cobblestone + 2 sticks for a stone pickaxe (have %d cobble, %d sticks, %d planks)", x.cobble, x.sticks, x.planks)}
		end
		return {ok = true, prio = prio, detail = string.format("craft stone %s (all together %d cobble; you have %d cobble, %d sticks)",
			table.concat(want, ", "), cob, x.cobble, x.sticks)}
	end,
	run = function(p)
		local tpos, why = A.ensure_table(p)
		if not tpos then
			return false, why
		end
		A.approach(p, tpos, 3.5)
		local made = {}
		for _, t in ipairs(TOOLS) do
			if U.tool_tier(p, t[1]) < 2 and U.count(p, "group:cobble") >= t[2] then
				if U.count(p, "mcl_core:stick") < t[3] then
					A.craft(p, "mcl_core:stick")
				end
				if A.craft(p, "mcl_tools:" .. t[1] .. "_stone") then
					made[#made + 1] = "stone " .. t[1]
				end
			end
		end
		if #made == 0 then
			return false, "nothing crafted (missing cobblestone or sticks)"
		end
		return true, "crafted " .. table.concat(made, ", ")
	end,
})
