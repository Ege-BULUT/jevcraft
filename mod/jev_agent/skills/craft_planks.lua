-- Turn logs into planks.
local U, A = jev.u, jev.a

local function planks_of(log)
	local r = minetest.get_craft_result({method = "normal", width = 1, items = {log}})
	return not r.item:is_empty() and r.item:get_name() or nil
end

jev.register_skill({
	id = "craft_planks", label = "🪵 Craft planks", timeout = 30,
	offer = function(p, x)
		if x.logs == 0 then
			return {ok = false, prio = x.planks < 4 and 30 or 0, detail = "no logs to cut (gather_wood first)"}
		end
		local n = math.min(x.logs, 4)
		return {ok = true, prio = x.planks < 8 and 76 or (x.planks < 16 and 30 or 8),
			detail = string.format("cut %d of your %d logs into %d planks (you have %d planks)", n, x.logs, n * 4, x.planks)}
	end,
	run = function(p)
		local made = 0
		for _ = 1, 4 do
			local log
			for name in pairs(U.counts(p)) do
				if minetest.get_item_group(name, "tree") > 0 and planks_of(name) then
					log = name
					break
				end
			end
			if not log then
				break
			end
			local ok, n = A.craft(p, planks_of(log))
			if not ok then
				return made > 0, n
			end
			made = made + n
		end
		return made > 0, "+" .. made .. " planks"
	end,
})
