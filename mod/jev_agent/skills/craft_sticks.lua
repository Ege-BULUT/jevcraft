-- Turn planks into sticks.
local A = jev.a

jev.register_skill({
	id = "craft_sticks", label = "🥢 Craft sticks", timeout = 20,
	offer = function(p, x)
		if x.planks < 2 then
			return {ok = false, prio = x.sticks < 2 and 20 or 0, detail = "need 2 planks (have " .. x.planks .. ")"}
		end
		return {ok = true, prio = x.sticks < 2 and 73 or (x.sticks < 6 and 35 or 4),
			detail = "2 planks -> 4 sticks (you have " .. x.sticks .. " sticks, " .. x.planks .. " planks); tools need 1-2 sticks each"}
	end,
	run = function(p)
		local ok, n = A.craft(p, "mcl_core:stick")
		return ok, ok and ("+" .. n .. " sticks") or n
	end,
})
