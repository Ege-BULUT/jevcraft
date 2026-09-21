-- Mine the most useful visible ore vein within 24 m that the current pickaxe can harvest.
local U, A = jev.u, jev.a

-- kind, minimum pickaxe tier, base priority
local KINDS = {
	{"diamond", 4, 78}, {"obsidian", 5, 74}, {"iron", 2, 70}, {"coal", 1, 58}, {"gold", 4, 30},
}

local function choose(p, x)
	local blocked
	for _, k in ipairs(KINDS) do
		local o = x.ores[k[1]]
		if o then
			if x.pick >= k[2] then
				local prio = k[3]
				if k[1] == "coal" and x.n("mcl_core:coal_lump") >= 8 then prio = 20 end
				if k[1] == "iron" and x.pick >= 4 and x.n("mcl_core:iron_ingot") + x.n("mcl_raw_ores:raw_iron") >= 6 then prio = 25 end
				if k[1] == "obsidian" and x.n("mcl_core:obsidian") >= 10 then prio = 5 end
				return k, o, prio
			end
			blocked = blocked or {k, o}
		end
	end
	return nil, blocked
end

jev.register_skill({
	id = "mine_ores", label = "💎 Mine ores", timeout = 120,
	offer = function(p, x)
		local k, o, prio = choose(p, x)
		if k then
			return {ok = true, prio = prio, detail = string.format("mine %s %s (vein); you have %s", k[1],
				U.where(x.pos, o.pos), x.pick > 0 and ("a " .. ({"wooden", "stone", "golden", "iron", "diamond", "netherite"})[x.pick] .. " pickaxe") or "no pickaxe")}
		end
		if o then
			local tiers = {"wooden", "stone", "", "iron", "diamond"}
			return {ok = false, prio = 35, detail = o[1][1] .. " " .. U.where(x.pos, o[2].pos) .. " needs a " .. tiers[o[1][2]] .. " pickaxe"}
		end
		return {ok = false, prio = x.pick >= 1 and 35 or 5, detail = "no coal/iron/diamond seen within 24 m; staircase down (mine_stone) or explore"}
	end,
	run = function(p, x)
		local k = choose(p, x)
		if not k then
			return false, "no minable ore in range"
		end
		local names = jev.ORES[k[1]]
		local item_before = U.counts(p)
		local mined = 0
		for _ = 1, 10 do
			local o = U.nearest_node(p:get_pos(), names, mined == 0 and 24 or 5)
			if not o then
				break
			end
			A.status("going to " .. k[1] .. " " .. U.where(p:get_pos(), o))
			local ok, why = A.approach(p, o, 4)
			if not ok then
				if mined == 0 then
					return false, "could not reach the " .. k[1] .. ": " .. (why or "no path")
				end
				break
			end
			A.status("mining " .. k[1])
			if A.dig(p, o) then
				mined = mined + 1
			else
				break
			end
			A.collect(p, o, 4)
		end
		local gained = {}
		for name, c in pairs(U.counts(p)) do
			if c > (item_before[name] or 0) and not name:find("cobble") then
				gained[#gained + 1] = "+" .. (c - (item_before[name] or 0)) .. " " .. U.desc(name)
			end
		end
		return mined > 0, "mined " .. mined .. " " .. k[1] .. " blocks " .. table.concat(gained, ", ")
	end,
})
