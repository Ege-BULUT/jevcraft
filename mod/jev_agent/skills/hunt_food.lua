-- Hunt passive animals for meat (prefers sheep while wool for a bed is missing).
local U, A = jev.u, jev.a

local function needs_wool(p)
	return not jev.mem.bed and U.count(p, "group:bed") == 0 and U.count(p, "group:wool") < 3
end

jev.register_skill({
	id = "hunt_food", label = "🏹 Hunt animals", timeout = 80,
	offer = function(p, x)
		if not x.prey then
			return {ok = false, prio = x.food < 3 and 40 or 5, detail = "no cows, pigs, sheep or chickens within 32 m"}
		end
		local target = (needs_wool(p) and x.sheep) or x.prey
		local prio = x.food < 3 and (x.hunger < 12 and 82 or 64) or (x.food < 8 and 35 or 10)
		if target == x.sheep and needs_wool(p) then
			prio = math.max(prio, 50)
		end
		return {ok = true, prio = prio, detail = string.format("hunt the %s %s%s; you carry %d food items",
			target.short, U.where(x.pos, target.pos), target.short == "sheep" and " (drops wool for a bed + mutton)" or "", x.food)}
	end,
	run = function(p)
		local killed = {}
		for _ = 1, 2 do
			local mobs = U.mobs(p:get_pos(), 32)
			local t = (needs_wool(p) and U.first(mobs, function(m) return m.name == "mobs_mc:sheep" end))
				or U.first(mobs, function(m) return m.kind == "food" end)
			if not t then
				break
			end
			A.status("hunting a " .. t.short .. " " .. U.where(p:get_pos(), t.pos))
			local ok, where = A.attack(p, t.obj, 35)
			if not ok then
				if #killed == 0 then
					return false, "hunt failed: " .. tostring(where)
				end
				break
			end
			killed[#killed + 1] = t.short
			if where then
				A.wait(0.8)
				A.collect(p, where, 6)
			end
		end
		return #killed > 0, "killed " .. table.concat(killed, ", ")
	end,
})
