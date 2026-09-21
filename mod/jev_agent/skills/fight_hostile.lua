-- Attack the nearest hostile mob within 10 m until it dies.
local U, A = jev.u, jev.a

local function weapon_text(p)
	local best, bd = "bare hands", 1
	for _, st in ipairs(p:get_inventory():get_list("main")) do
		local c = minetest.registered_tools[st:get_name()] and st:get_tool_capabilities()
		local d = c and c.damage_groups and c.damage_groups.fleshy or 0
		if d > bd then
			best, bd = U.desc(st:get_name()), d
		end
	end
	return best .. " (" .. bd .. " damage)"
end

jev.register_skill({
	id = "fight_hostile", label = "⚔ Fight hostile", timeout = 60,
	offer = function(p, x)
		local h = x.hostile
		if not h then
			return nil
		end
		if h.dist > 10 then
			return {ok = false, detail = "nearest hostile " .. h.short .. " is " .. U.where(x.pos, h.pos) .. " (over 10 m)", prio = 10}
		end
		local e = h.obj:get_luaentity()
		return {ok = true, prio = x.hp >= 10 and 92 or 55,
			detail = string.format("attack %s %s (its HP %d) with %s; your HP %d/20", h.short, U.where(x.pos, h.pos),
				math.floor(e and e.health or 0), weapon_text(p), x.hp)}
	end,
	run = function(p)
		local h = U.first(U.mobs(p:get_pos(), 12), function(m) return m.kind == "hostile" end)
		if not h then
			return false, "no hostile mob nearby any more"
		end
		A.status("fighting " .. h.short)
		local ok, where = A.attack(p, h.obj, 50)
		if not ok then
			return false, where
		end
		if where then
			A.collect(p, where, 5)
		end
		return true, "killed " .. h.short
	end,
})
