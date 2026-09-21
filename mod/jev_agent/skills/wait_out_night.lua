-- Stay inside the shelter (or a sealed tunnel) until morning; eats if hungry.
local U, A = jev.u, jev.a

jev.register_skill({
	id = "wait_out_night", label = "🌙 Wait out the night", timeout = 75,
	offer = function(p, x)
		if not x.night then
			return nil
		end
		if not x.sheltered then
			return {ok = false, prio = 30, detail = "not inside a shelter" ..
				(x.shelter and (" (yours is " .. U.where(x.pos, x.shelter) .. ")") or "")}
		end
		return {ok = true, prio = 86, detail = string.format("stay put in the shelter for about a minute (it is %s; day starts at 05:30)", x.clock)}
	end,
	run = function(p)
		local t = 0
		while t < 60 and U.is_night() do
			A.status("waiting for morning (" .. U.clock() .. ")")
			A.wait(2)
			t = t + 2
			if mcl_hunger.get_hunger(p) < 12 then
				local food = A.best_food(p)
				if food then A.eat(p, food) end
			end
		end
		return true, "waited until " .. U.clock()
	end,
})
